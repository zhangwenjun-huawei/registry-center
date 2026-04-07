# A2A-T Agent Registry Center

A2A-T智能体AgentCard注册中心，提供RESTful API服务用于管理和查询AI Agent卡片信息。

## 项目概述

本项目是一个基于FastAPI的Agent注册中心服务，实现了A2A-T协议规范，提供Agent的注册、查询和管理功能。服务支持TLS/SSL安全连接、流量控制、审计日志等企业级特性。

## 核心功能

### 1. Agent注册与查询
- **注册Agent**: 通过POST接口注册新的Agent，支持唯一性校验（name + organization）
- **查询Agent**: 支持精确查询，按name和organization字段过滤
- **数据持久化**: 使用JSON文件存储Agent数据，支持自动加载和保存

### 2. 安全特性
- **TLS/SSL支持**: 支持双向TLS认证，支持CRL证书吊销列表
- **密码套件转换**: 支持IANA到OpenSSL密码套件格式转换
- **客户端认证**: 支持基于证书的客户端身份验证
- **API签名验证**: 支持基于非对称加密的API请求签名验证（规划中）

### 3. 流量控制
- **限流机制**: 基于IP的请求频率限制（注册/查询独立配置）
- **并发控制**: 支持注册和查询的并发数限制
- **连接限制**: 最大连接数控制
- **超时控制**: 请求处理超时控制

### 4. 数据验证
- **AgentCard验证**: 基于Pydantic的完整数据模型验证
- **字段长度限制**: 对各字段设置最大长度限制
- **格式校验**: URL格式、字符集等格式验证
- **安全字符检查**: 防止注入攻击的字符过滤

### 5. 审计与日志
- **操作审计**: 记录所有关键操作（注册、查询、服务启动等）
- **日志管理**: 基于loguru的结构化日志

## 项目结构

```
registry-center/
├── agent_registry/          # 核心注册服务模块
│   ├── server.py           # FastAPI服务器，提供REST API接口
│   ├── core.py             # 核心注册逻辑，Agent存储和管理
│   ├── start.py            # 服务启动入口，SSL配置
│   ├── config.py           # 配置常量定义
│   ├── persistence.py       # 数据持久化（JSON文件）
│   ├── middleware.py        # 中间件（连接限制、超时）
│   ├── cipher_converter.py  # 密码套件格式转换
│   ├── registry_instance.py # 注册中心单例
│   └── model/              # 数据模型
│       └── validated_agentcard.py  # AgentCard验证模型
├── common/                  # 公共模块
│   ├── custom/             # 自定义处理器机制
│   │   ├── custom_handle.py      # 处理器注册表
│   │   └── interface_type.py     # 接口类型枚举
│   ├── util/               # 工具类
│   │   ├── authenticate_util.py  # 认证工具
│   │   ├── cipher_util.py       # 加密工具
│   │   ├── config_util.py       # 配置工具
│   │   └── conf_util.py         # 配置对象
│   ├── cert/               # 证书相关
│   │   ├── cert_parser.py       # 证书解析
│   │   ├── cert_validater.py    # 证书验证
│   │   └── x509_obj.py          # X.509对象
│   └── log/                # 日志相关
├── docs/                    # 文档目录
│   └── signature_verification_design.md  # 签名验证设计文档
├── etc/                    # 配置文件
│   ├── server.conf         # 服务器配置
│   ├── server.properties   # 属性配置
│   └── log_config.conf     # 日志配置
├── bin/                    # 启动脚本
│   ├── start.sh            # 启动脚本
│   └── stop.sh             # 停止脚本
├── tests/                  # 测试代码
│   └── test_register.py    # 注册功能测试
├── requirements.txt        # Python依赖
└── README.md              # 项目说明
```

## API接口

### Agent管理接口

#### 注册Agent
```
POST /rest/a2a-t/v1/agents/register
Content-Type: application/json

请求体：AgentCard对象
响应：201 Created (成功) / 409 Conflict (重复) / 400 Bad Request (数据无效)
```

#### 查询Agent
```
GET /rest/a2a-t/v1/agents/query?name={name}&organization={organization}

参数：
- name: Agent名称（可选）
- organization: 组织名称（可选）

响应：AgentCard列表
```

### 公钥管理接口（规划中）

#### 新增公钥
```
POST /rest/a2a-t/v1/keys/public
Content-Type: application/json

请求体：
{
    "key_id": "client-001",
    "public_key": "-----BEGIN PUBLIC KEY-----\n...",
    "algorithm": "RSA",
    "metadata": {
        "owner": "client-app",
        "description": "Client application public key"
    }
}

响应：200 OK
```

#### 删除公钥
```
DELETE /rest/a2a-t/v1/keys/public/{key_id}

响应：200 OK
```

#### 查询公钥
```
GET /rest/a2a-t/v1/keys/public/{key_id}

响应：公钥详细信息
```

#### 列出所有公钥
```
GET /rest/a2a-t/v1/keys/public

响应：公钥列表
```

## 配置说明

主要配置项（etc/server.conf）：
- `connection.max`: 最大连接数
- `connection.timeout`: 连接超时时间
- `flowcontrol.ratelimit.register`: 注册接口限流
- `flowcontrol.ratelimit.query`: 查询接口限流
- `flowcontrol.parallelism.register`: 注册并发数
- `flowcontrol.parallelism.query`: 查询并发数
- `agent.num.max`: 最大Agent数量
- `tls.version`: TLS版本
- `tls.cipher`: 密码套件
- `ssl_certfile`: 服务器证书路径
- `ssl_keyfile`: 服务器私钥路径
- `ssl_ca_certs`: 信任证书路径
- `verify_client`: 是否验证客户端证书

## 依赖项

- a2a-sdk>=0.3.2: A2A协议SDK
- fastapi>=0.115.11: Web框架
- uvicorn>=0.34.0: ASGI服务器
- loguru>=0.7.3: 日志库
- cryptography~=46.0.5: 加密库
- limits~=4.0.0: 限流库
- starlette~=0.50.0: ASGI工具包

## 启动方式

### Linux/WSL环境

```bash
# 使用启动脚本
./bin/start.sh

# 或直接运行Python模块
python -m agent_registry.start
```

### Windows环境

```bash
# 使用Python模块启动
py -m agent_registry.start

# 或使用批处理脚本
start.bat
```

### Docker环境

```bash
# 构建镜像
docker build -t agent-registry .

# 运行容器
docker run -p 5000:5000 agent-registry
```

## 安全特性

### 1. 数据安全
- **敏感数据保护**：敏感数据文件权限设置为600
- **数据加密**：支持数据加密存储
- **文件大小限制**：最大文件大小限制（100MB）
- **输入验证**：严格的输入数据验证

### 2. 网络安全
- **TLS/SSL加密**：强制TLS/SSL加密传输
- **双向认证**：支持客户端证书认证
- **CRL支持**：支持证书吊销列表
- **密码套件**：支持强密码套件配置

### 3. 应用安全
- **输入验证**：严格的输入数据验证
- **防注入攻击**：防止SQL注入、命令注入等攻击
- **请求大小限制**：防止大文件攻击
- **URL长度限制**：防止长URL攻击

## 扩展机制

项目提供了自定义处理器机制，通过`HandlerRegistry`可以扩展以下功能：

- **AUTHENTICATE**: 认证处理器
- **AUDIT**: 审计处理器
- **INSERT**: 插入处理器
- **QUERY**: 查询处理器
- **DECRYPT**: 解密处理器

通过继承`BaseHandler`并实现`handle`方法，可以自定义这些接口的实现。

## API签名验证（规划中）

### 设计概述

系统规划实现基于非对称加密的API请求签名验证功能，包括：

1. **签名验证器**：验证API请求的签名有效性
2. **公钥管理器**：管理客户端公钥的增删查操作
3. **多种签名算法**：支持RSA-PSS、ECDSA、Ed25519等算法
4. **防重放攻击**：时间戳验证和Nonce机制

### 主要功能

- **公钥管理**：新增、删除、查询客户端公钥
- **签名验证**：自动验证API请求的签名
- **算法支持**：支持多种签名算法
- **安全防护**：防重放攻击、时间戳验证

### 详细设计

详细的设计文档请参考：[docs/signature_verification_design.md](docs/signature_verification_design.md)

## 开发指南

### 环境准备

1. **Python环境**：Python 3.8+
2. **依赖安装**：`pip install -r requirements.txt`
3. **SSL证书**：生成或配置SSL证书

### 代码结构

- **agent_registry**: 核心业务逻辑
- **common**: 公共工具和组件
- **tests**: 测试代码

### 测试

```bash
# 运行测试
pytest tests/

# 运行特定测试
pytest tests/test_register.py
```

## 故障排查

### 常见问题

1. **SSL证书错误**
   - 检查证书文件路径
   - 验证证书格式
   - 确认私钥密码正确

2. **端口占用**
   - 检查端口是否被占用
   - 修改配置文件中的端口

3. **权限错误**
   - 检查文件权限设置
   - 确认运行用户权限

4. **依赖缺失**
   - 重新安装依赖：`pip install -r requirements.txt`

## 版本信息

当前版本：2.0.0

## 贡献指南

欢迎贡献代码！请遵循以下步骤：

1. Fork项目
2. 创建特性分支
3. 提交更改
4. 推送到分支
5. 创建Pull Request

## 许可证

请参考LICENSE文件了解许可证信息。

## 联系方式

如有问题或建议，请通过以下方式联系：

- 项目Issues：[GitHub Issues](https://github.com/your-repo/issues)
- 邮件：your-email@example.com

## 更新日志

### v2.0.0 (当前版本)
- 完整的Agent注册和查询功能
- TLS/SSL安全支持
- 流量控制和并发管理
- 审计日志功能
- 证书验证和管理

### 未来规划
- API签名验证功能
- 公钥管理API
- 密钥轮换机制
- 多租户支持
- 性能优化