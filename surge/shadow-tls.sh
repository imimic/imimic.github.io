#!/bin/bash

# 1. 权限检查
if [[ $EUID -ne 0 ]]; then
   echo "错误：请使用 root 权限运行此脚本"
   exit 1
fi

echo "=================================================="
echo "开始部署原生 Shadow-TLS (对接本地 Snell v5)"
echo "=================================================="

# 2. 检查 Snell 配置文件并提取端口
SNELL_CONF="/etc/snell-server.conf"

if [ ! -f "$SNELL_CONF" ]; then
    echo "错误：未找到 $SNELL_CONF 文件！"
    echo "请确保你已经正确安装并配置了 Snell Server。"
    exit 1
fi

# 核心逻辑：精准提取 listen 字段末尾的端口号（去除空格和换行符防干扰）
SNELL_PORT=$(grep -i "^listen" "$SNELL_CONF" | tr -d ' \r' | grep -oE "[0-9]+$")

if [ -z "$SNELL_PORT" ]; then
    echo "错误：无法从 $SNELL_CONF 中读取到正确的端口号，请检查文件格式。"
    exit 1
fi

echo "✅ 成功读取到本地 Snell 监听端口: $SNELL_PORT"

# 3. 下载 Shadow-TLS 二进制文件
STLS_BIN="/usr/local/bin/shadow-tls"
STLS_URL="https://raw.githubusercontent.com/imimic/imimic.github.io/main/surge/shadow-tls"

echo "⏳ 正在下载 Shadow-TLS 二进制文件..."
curl -L -o "$STLS_BIN" "$STLS_URL"

if [ $? -ne 0 ]; then
    echo "❌ 错误：下载失败，请检查你的服务器网络连接。"
    exit 1
fi

# 赋予执行权限
chmod +x "$STLS_BIN"
echo "✅ Shadow-TLS 二进制文件已就绪 (/usr/local/bin/shadow-tls)"

# 4. 生成 Systemd 配置文件
SERVICE_FILE="/etc/systemd/system/shadow-tls.service"
echo "⏳ 正在生成 Systemd 守护进程配置..."

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Shadow-TLS Server Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
LimitNOFILE=infinity
Environment="MONOIO_FORCE_LEGACY_DRIVER=1"
ExecStart=/usr/local/bin/shadow-tls --v3 --strict server --listen 0.0.0.0:8443 --server 127.0.0.1:${SNELL_PORT} --tls gateway.icloud.com --password mimic365
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

echo "✅ Systemd 配置写入完成"

# 5. 重载、自启并运行服务
echo "⏳ 正在启动 Shadow-TLS 服务..."
systemctl daemon-reload
systemctl enable shadow-tls >/dev/null 2>&1
systemctl restart shadow-tls

echo "=================================================="
echo "🎉 部署完成！底层双进程防线已建立。"
echo "=================================================="
echo "➜ 对外监听端口 : 8443"
echo "➜ 流量内网转发 : 127.0.0.1:$SNELL_PORT (Snell)"
echo "➜ 伪装 TLS 域名: gateway.icloud.com"
echo "➜ STLS 握手密码: mimic365"
echo "=================================================="
echo "正在输出服务运行状态 (按 Q 键退出查看)："
sleep 2
systemctl status shadow-tls --no-pager
