#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TARGET_DIR="${SCRIPT_DIR}/agent_registry"

# 规范化路径（解析符号链接和相对路径）
if [ -d "$TARGET_DIR" ]; then
    TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
else
    echo "错误：目标目录不存在: $TARGET_DIR"
    exit 1
fi

# 判断是否为 root 用户
if [ "$EUID" -eq 0 ]; then
    # root 用户：打印风险提示
    echo "⚠️  ===== 安全警告 ====="
    echo "您当前以 root 身份运行！"
    echo "以 root 身份执行命令可能存在安全风险，请谨慎操作。"
    echo "   建议仅在必要时使用 root 权限。"
    echo "========================="
fi

# 进入目标目录
cd "$TARGET_DIR" || {
    echo "错误：无法进入目录 $TARGET_DIR"
    exit 1
}

PYTHON_SCRIPT="start.py"

# 检查 Python 脚本是否存在
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "错误：Python 脚本 $PYTHON_SCRIPT 不存在于 $TARGET_DIR"
    exit 1
fi

# 执行 Python 脚本
echo "启动 Python 脚本: $PYTHON_SCRIPT"
python3 "$PYTHON_SCRIPT"


exit 0