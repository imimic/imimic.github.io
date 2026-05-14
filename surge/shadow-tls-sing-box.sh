#!/bin/bash

# ==========================================
# shadow-tls (sing-box core) 自动化部署脚本
# ==========================================

# 确保以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo "错误：此脚本必须以 root 权限运行，请使用 sudo 或 root 账户执行。" 
   exit 1
fi

# 安装必要依赖
echo ">> 正在检查并安装必要依赖 (curl, unzip)..."
apt-get update -y >/dev/null 2>&1 || yum update -y >/dev/null 2>&1
apt-get install -y curl unzip >/dev/null 2>&1 || yum install -y curl unzip >/dev/null 2>&1

# ------------------------------------------
# 步骤 1：读取 snell-server 端口
# ------------------------------------------
echo ">> 正在读取 Snell 端口..."
SNELL_CONF="/etc/snell-server.conf"

if [ ! -f "$SNELL_CONF" ]; then
    echo "错误：找不到 $SNELL_CONF 文件！请确认 Snell 已安装。"
    exit 1
fi

# 提取 listen 字段中的端口号 (例如：listen = 0.0.0.0:12345 提取 12345)
SNELL_PORT=$(grep -E "^listen" "$SNELL_CONF" | awk -F':' '{print $NF}' | tr -d ' \r')

if [ -z "$SNELL_PORT" ]; then
    echo "错误：无法从 $SNELL_CONF 中读取到端口号！"
    exit 1
fi

echo ">> 成功读取到 Snell 端口: $SNELL_PORT"

# ------------------------------------------
# 步骤 2：下载并解压核心文件
# ------------------------------------------
echo ">> 正在下载 shadow-tls..."
TMP_DIR=$(mktemp -d)
curl -L -o "$TMP_DIR/shadow-tls.zip" "https://raw.githubusercontent.com/imimic/imimic.github.io/main/surge/shadow-tls.zip"

echo ">> 正在解压并赋予权限..."
unzip -o "$TMP_DIR/shadow-tls.zip" -d "$TMP_DIR" >/dev/null

# 提取并重命名二进制文件，移动到 /usr/local/bin 目录
BINARY_FILE=$(find "$TMP_DIR" -type f ! -name "*.zip" | head -n 1)
if [ -n "$BINARY_FILE" ]; then
    mv "$BINARY_FILE" /usr/local/bin/shadow-tls
    chmod +x /usr/local/bin/shadow-tls
else
    echo "错误：下载的压缩包内没有找到可执行文件！"
    rm -rf "$TMP_DIR"
    exit 1
fi

rm -rf "$TMP_DIR"

# ------------------------------------------
# 步骤 3：建立 systemd 服务文件和相应文件夹
# ------------------------------------------
echo ">> 正在配置工作目录和 systemd 服务..."
mkdir -p /etc/shadow-tls

# 使用 'EOF' 防止 bash 解析 $MAINPID
# 注意这里的 ExecStart 路径已更新为 /usr/local/bin/shadow-tls
cat << 'EOF' > /etc/systemd/system/shadow-tls.service
[Unit]
Description=shadow-tls service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
LimitNOFILE=infinity
ExecStart=/usr/local/bin/shadow-tls -C /etc/shadow-tls run
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# ------------------------------------------
# 步骤 4：生成 JSON 配置文件
# ------------------------------------------
echo ">> 正在生成 JSON 配置文件..."

# 这里使用 EOF (不加引号)，允许 bash 把 $SNELL_PORT 变量替换进 json 里
cat << EOF > /etc/shadow-tls/config.json
{
  "log": {
    "disabled": true,
    "level": "warn",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "address": "8.8.8.8"
      }
    ]
  },
  "inbounds": [
    {
      "type": "shadowtls",
      "tag": "shadowtls",
      "listen": "0.0.0.0",
      "listen_port": 8443,
      "version": 3,
      "users": [
        {
          "password": "mimic365"
        }
      ],
      "handshake": {
        "server": "gateway.icloud.com",
        "server_port": 443
      },
      "strict_mode": true
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "direct",
      "tag": "snell",
      "override_address": "127.0.0.1",
      "override_port": $SNELL_PORT
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": "shadowtls",
        "outbound": "snell"
      }
    ]
  }
}
EOF

# ------------------------------------------
# 步骤 5：启动服务并设置开机自启
# ------------------------------------------
echo ">> 正在启动 shadow-tls 服务并设置开机自启..."
systemctl daemon-reload
systemctl enable --now shadow-tls

# 检查服务运行状态
if systemctl is-active --quiet shadow-tls; then
    echo "======================================================="
    echo "部署成功！shadow-tls 服务正在运行。"
    echo "监听端口: 8443"
    echo "转发至 Snell 端口: $SNELL_PORT"
    echo "======================================================="
else
    echo "======================================================="
    echo "部署完成，但 shadow-tls 服务未能成功启动。"
    echo "请使用命令查看报错原因: journalctl -u shadow-tls -f"
    echo "======================================================="
fi
