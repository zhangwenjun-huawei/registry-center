# API签名验证与公钥管理系统设计文档

## 1. 概述

本文档描述了A2A-T Agent Registry Center的API签名验证和公钥管理系统的设计方案。该系统用于确保API请求的安全性和完整性，防止未授权访问和数据篡改。

## 2. 现有功能分析

### 2.1 已实现的证书功能

项目目前已实现以下证书相关功能：

- **服务器TLS配置**：在`agent_registry/start.py`中配置服务器SSL证书
- **证书解析与验证**：`common/cert/cert_parser.py`和`common/cert/cert_validater.py`
- **证书格式验证**：支持X.509v3证书格式验证
- **密钥长度验证**：RSA≥3072 bits，ECDSA≥256 bits
- **CRL支持**：证书吊销列表支持
- **客户端证书认证**：基于TLS的双向认证

### 2.2 缺失的功能

当前系统缺少以下关键功能：

- **API请求签名验证**：无请求体签名验证机制
- **客户端公钥管理**：无公钥的增删查功能
- **签名算法支持**：无多种签名算法支持
- **公钥存储**：无公钥持久化存储
- **密钥轮换**：无密钥轮换机制

## 3. 系统设计

### 3.1 架构设计

```
┌─────────────────┐
│   API Client    │
└────────┬────────┘
         │
         │ 1. HTTP Request + Signature
         ▼
┌─────────────────────────────────┐
│   Signature Validation Layer   │
│   - Extract signature          │
│   - Load public key            │
│   - Verify signature          │
└────────┬────────────────────────┘
         │
         │ 2. Validated Request
         ▼
┌─────────────────────────────────┐
│   Business Logic Layer         │
│   - Agent Registry             │
│   - Query Service              │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│   Public Key Management         │
│   - Add/Remove public keys      │
│   - Key storage                 │
└─────────────────────────────────┘
```

### 3.2 核心组件

#### 3.2.1 签名验证器 (SignatureValidator)

**职责**：
- 从HTTP请求中提取签名
- 加载对应的公钥
- 验证签名有效性
- 返回验证结果

**接口设计**：
```python
class SignatureValidator:
    def validate_request(self, request: Request, public_key_id: str) -> ValidationResult
    def extract_signature(self, request: Request) -> Optional[str]
    def verify_signature(self, data: bytes, signature: str, public_key: PublicKey) -> bool
```

#### 3.2.2 公钥管理器 (PublicKeyManager)

**职责**：
- 管理客户端公钥的CRUD操作
- 公钥持久化存储
- 公钥查询和检索

**接口设计**：
```python
class PublicKeyManager:
    def add_public_key(self, key_id: str, public_key: str, metadata: dict) -> bool
    def remove_public_key(self, key_id: str) -> bool
    def get_public_key(self, key_id: str) -> Optional[PublicKey]
    def list_public_keys(self) -> List[PublicKeyInfo]
    def update_public_key(self, key_id: str, public_key: str) -> bool
```

#### 3.2.3 签名生成器 (SignatureGenerator) - 客户端工具

**职责**：
- 为客户端生成请求签名
- 支持多种签名算法

**接口设计**：
```python
class SignatureGenerator:
    def generate_signature(self, data: bytes, private_key: PrivateKey) -> str
    def sign_request(self, request: dict, private_key: PrivateKey) -> dict
```

### 3.3 数据模型

#### 3.3.1 公钥信息模型

```python
class PublicKeyInfo(BaseModel):
    key_id: str                    # 公钥唯一标识
    public_key: str                # PEM格式公钥
    algorithm: str                 # 签名算法 (RSA/ECDSA)
    key_size: int                  # 密钥长度
    created_at: datetime           # 创建时间
    updated_at: datetime           # 更新时间
    status: str                    # 状态 (active/revoked)
    metadata: dict                 # 元数据 (owner, description等)
```

#### 3.3.2 签名验证结果

```python
class ValidationResult(BaseModel):
    is_valid: bool                 # 验证是否通过
    key_id: str                    # 使用的公钥ID
    algorithm: str                 # 签名算法
    timestamp: datetime            # 验证时间
    error_message: Optional[str]   # 错误信息
```

### 3.4 API设计

#### 3.4.1 公钥管理API

**新增公钥**
```
POST /rest/a2a-t/v1/keys/public
Content-Type: application/json

Request Body:
{
    "key_id": "client-001",
    "public_key": "-----BEGIN PUBLIC KEY-----\n...",
    "algorithm": "RSA",
    "metadata": {
        "owner": "client-app",
        "description": "Client application public key"
    }
}

Response:
{
    "success": true,
    "key_id": "client-001",
    "message": "Public key added successfully"
}
```

**删除公钥**
```
DELETE /rest/a2a-t/v1/keys/public/{key_id}

Response:
{
    "success": true,
    "message": "Public key removed successfully"
}
```

**查询公钥**
```
GET /rest/a2a-t/v1/keys/public/{key_id}

Response:
{
    "key_id": "client-001",
    "algorithm": "RSA",
    "key_size": 4096,
    "created_at": "2024-01-01T00:00:00Z",
    "status": "active",
    "metadata": {
        "owner": "client-app"
    }
}
```

**列出所有公钥**
```
GET /rest/a2a-t/v1/keys/public

Response:
{
    "keys": [
        {
            "key_id": "client-001",
            "algorithm": "RSA",
            "status": "active"
        }
    ],
    "total": 1
}
```

#### 3.4.2 签名验证API

**验证签名**
```
POST /rest/a2kt-t/v1/verify/signature
Content-Type: application/json
X-Key-ID: client-001
X-Signature: <base64_encoded_signature>
X-Timestamp: <unix_timestamp>

Request Body: {原始请求数据}

Response:
{
    "is_valid": true,
    "key_id": "client-001",
    "verified_at": "2024-01-01T00:00:00Z"
}
```

### 3.5 签名方案

#### 3.5.1 签名算法支持

- **RSA-PSS**: RSA-PSS with SHA-256
- **ECDSA**: ECDSA with SHA-256 (P-256, P-384)
- **Ed25519**: Ed25519 (推荐)

#### 3.5.2 签名生成流程

1. **客户端签名生成**：
   ```
   1. 构造待签名数据：HTTP方法 + URL路径 + 请求体 + 时间戳
   2. 使用私钥对数据进行签名
   3. 将签名进行Base64编码
   4. 在HTTP头中添加：
      - X-Signature: <签名>
      - X-Key-ID: <公钥ID>
      - X-Timestamp: <时间戳>
   ```

2. **服务端签名验证**：
   ```
   1. 从HTTP头中提取签名、公钥ID、时间戳
   2. 根据公钥ID加载对应的公钥
   3. 重新构造待签名数据
   4. 使用公钥验证签名
   5. 检查时间戳防止重放攻击
   ```

#### 3.5.3 防重放攻击机制

- **时间戳验证**：请求时间戳与服务器时间差不超过5分钟
- **Nonce机制**：可选的nonce值防止重复请求
- **签名缓存**：短期缓存已验证的签名

### 3.6 存储设计

#### 3.6.1 公钥存储格式

```json
{
    "keys": {
        "client-001": {
            "public_key": "-----BEGIN PUBLIC KEY-----\n...",
            "algorithm": "RSA",
            "key_size": 4096,
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-01-01T00:00:00Z",
            "status": "active",
            "metadata": {
                "owner": "client-app",
                "description": "Client application public key"
            }
        }
    },
    "version": 1
}
```

#### 3.6.2 存储位置

- **文件路径**：`data/public_keys.json`
- **权限设置**：600 (仅所有者可读写)
- **备份机制**：每次更新前自动备份

### 3.7 安全考虑

#### 3.7.1 密钥安全

- **私钥保护**：私钥仅存储在客户端，服务端只存储公钥
- **密钥轮换**：支持定期密钥轮换
- **密钥吊销**：支持紧急吊销 compromised 密钥

#### 3.7.2 访问控制

- **管理员权限**：公钥管理API需要管理员权限
- **审计日志**：所有公钥操作记录审计日志
- **IP白名单**：可选的IP访问控制

#### 3.7.3 数据保护

- **传输加密**：强制HTTPS/TLS
- **存储加密**：可选的公钥存储加密
- **敏感信息过滤**：日志中过滤敏感信息

## 4. 实现计划

### 4.1 第一阶段：核心功能

1. **实现SignatureValidator**
   - 签名提取和验证逻辑
   - 支持RSA和ECDSA算法

2. **实现PublicKeyManager**
   - 公钥CRUD操作
   - 文件持久化

3. **实现公钥管理API**
   - 新增、删除、查询公钥接口

### 4.2 第二阶段：集成与优化

1. **集成到现有API**
   - 为Agent注册和查询API添加签名验证
   - 可选的签名验证开关

2. **客户端工具**
   - 提供Python客户端SDK
   - 签名生成工具

3. **监控和日志**
   - 签名验证失败监控
   - 操作审计日志

### 4.3 第三阶段：高级功能

1. **密钥轮换**
   - 自动密钥轮换机制
   - 密钥生命周期管理

2. **性能优化**
   - 公钥缓存机制
   - 批量验证支持

3. **多租户支持**
   - 租户级别的公钥隔离
   - 细粒度权限控制

## 5. 配置说明

### 5.1 签名验证配置

```ini
# etc/conf/server.properties

# 签名验证开关
signature_verification.enabled=true

# 支持的签名算法
signature.algorithms=RSA-PSS,ECDSA,Ed25519

# 时间戳容差（秒）
signature.timestamp_tolerance=300

# 公钥存储路径
signature.public_key_storage=data/public_keys.json

# 是否强制签名验证
signature.required=false
```

### 5.2 公钥管理配置

```ini
# 公钥管理API配置
key_management.enabled=true
key_management.admin_required=true
key_management.max_keys_per_client=10
key_management.key_rotation_days=90
```

## 6. 使用示例

### 6.1 客户端签名请求

```python
from client.signature_generator import SignatureGenerator

# 初始化签名生成器
generator = SignatureGenerator(private_key_path="client_private.pem")

# 准备请求数据
request_data = {
    "name": "TestAgent",
    "provider": {
        "organization": "TestOrg",
        "url": "https://test.org"
    }
}

# 生成签名请求
signed_request = generator.sign_request(
    method="POST",
    url="/rest/a2a-t/v1/agents/register",
    data=request_data,
    key_id="client-001"
)

# 发送请求
response = requests.post(
    "https://registry.example.com/rest/a2a-t/v1/agents/register",
    json=signed_request['data'],
    headers=signed_request['headers']
)
```

### 6.2 服务端验证

服务端自动验证签名，无需额外代码。签名验证通过中间件自动处理。

## 7. 测试计划

### 7.1 单元测试

- SignatureValidator测试
- PublicKeyManager测试
- 各种签名算法测试

### 7.2 集成测试

- 端到端签名验证流程
- 公钥管理API测试
- 错误场景测试

### 7.3 安全测试

- 签名伪造测试
- 重放攻击测试
- 密钥泄露测试

## 8. 附录

### 8.1 签名算法详情

**RSA-PSS**
- 密钥长度：≥2048 bits（推荐4096 bits）
- 哈希算法：SHA-256
- 填充方案：PSS

**ECDSA**
- 曲线：P-256, P-384
- 哈希算法：SHA-256

**Ed25519**
- 密钥长度：256 bits
- 性能最优，推荐使用

### 8.2 错误码

| 错误码 | 说明 |
|--------|------|
| SIG001 | 签名缺失 |
| SIG002 | 签名格式错误 |
| SIG003 | 公钥不存在 |
| SIG004 | 签名验证失败 |
| SIG005 | 时间戳过期 |
| SIG006 | 重放攻击检测 |

### 8.3 最佳实践

1. **使用Ed25519**：性能最优，安全性高
2. **定期轮换密钥**：建议90天轮换一次
3. **保护私钥**：使用HSM或密钥管理服务
4. **监控异常**：监控签名验证失败率
5. **审计日志**：记录所有签名相关操作