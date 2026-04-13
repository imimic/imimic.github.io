#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本 (例如: sudo bash $0)"
  exit 1
fi

echo "======================================================"
echo "          开始安装 dnsproxy 并配置服务                "
echo "======================================================"

# 1. 获取 dnsproxy 的最新版本号
echo "[1/6] 正在获取 dnsproxy 最新版本号..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/AdguardTeam/dnsproxy/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo "❌ 获取最新版本失败，请检查网络连接或 GitHub 访问权限。"
    exit 1
fi
echo "✅ 最新版本为: $LATEST_VERSION"

# 2. 下载并解压安装
echo "[2/6] 正在下载并安装 dnsproxy-linux-amd64..."
DOWNLOAD_URL="https://github.com/AdguardTeam/dnsproxy/releases/download/${LATEST_VERSION}/dnsproxy-linux-amd64-${LATEST_VERSION}.tar.gz"

wget -qO dnsproxy.tar.gz "$DOWNLOAD_URL"
if [ $? -ne 0 ]; then
    echo "❌ 下载失败！"
    exit 1
fi

tar -zxvf dnsproxy.tar.gz
cp linux-amd64/dnsproxy /usr/local/bin/
chmod +x /usr/local/bin/dnsproxy

# 清理安装包
rm -rf dnsproxy.tar.gz linux-amd64
echo "✅ 安装成功。可执行文件位于 /usr/local/bin/dnsproxy"

# 3. 创建配置目录及配置文件
echo "[3/6] 正在创建配置文件..."
mkdir -p /etc/dnsproxy

# 写入 config.yaml
cat <<EOF > /etc/dnsproxy/config.yaml
listen-addrs:
- "127.0.0.1"
listen-ports:
- 53
max-go-routines: 0
ratelimit: 0
udp-buf-size: 1232
bootstrap:
- "8.8.8.8"
upstream:
- "/etc/dnsproxy/1stream.conf"
- "8.8.8.8"
- "8.8.4.4"
all_servers: true
fastest-addr: true
cache: true
cache-size: 10485760
cache-optimistic: true
cache-min-ttl: 120
cache-max-ttl: 86400
ipv6-disabled: false
EOF

# 写入 1stream.conf
cat <<EOF > /etc/dnsproxy/1stream.conf
# > Netflix
[/netflix.com/]https://hkg.core.access.zznet.fun/dns-query
[/netflix.net/]https://hkg.core.access.zznet.fun/dns-query
[/nflximg.com/]https://hkg.core.access.zznet.fun/dns-query
[/nflximg.net/]https://hkg.core.access.zznet.fun/dns-query
[/nflxvideo.net/]https://hkg.core.access.zznet.fun/dns-query
[/nflxext.com/]https://hkg.core.access.zznet.fun/dns-query
[/nflxso.net/]https://hkg.core.access.zznet.fun/dns-query
# > Disney+
[/bamgrid.com/]https://hkg.core.access.zznet.fun/dns-query
[/disney-plus.net/]https://hkg.core.access.zznet.fun/dns-query
[/disneyplus.com/]https://hkg.core.access.zznet.fun/dns-query
[/dssott.com/]https://hkg.core.access.zznet.fun/dns-query
[/disneystreaming.com/]https://hkg.core.access.zznet.fun/dns-query
[/cdn.registerdisney.go.com/]https://hkg.core.access.zznet.fun/dns-query
# > HBO / Max
[/discomax.com/]https://hkg.core.access.zznet.fun/dns-query
[/hbo.com/]https://hkg.core.access.zznet.fun/dns-query
[/hbomax.com/]https://hkg.core.access.zznet.fun/dns-query
[/hbomaxcdn.com/]https://hkg.core.access.zznet.fun/dns-query
[/max.com/]https://hkg.core.access.zznet.fun/dns-query
# > Hotstar
[/hotstar.com/]https://hkg.core.access.zznet.fun/dns-query
[/hotstarext.com/]https://hkg.core.access.zznet.fun/dns-query
# > TikTok
[/byteoversea.com/]https://hkg.core.access.zznet.fun/dns-query
[/ibytedtos.com/]https://hkg.core.access.zznet.fun/dns-query
[/ipstatp.com/]https://hkg.core.access.zznet.fun/dns-query
[/muscdn.com/]https://hkg.core.access.zznet.fun/dns-query
[/musical.ly/]https://hkg.core.access.zznet.fun/dns-query
[/tiktok.com/]https://hkg.core.access.zznet.fun/dns-query
[/tik-tokapi.com/]https://hkg.core.access.zznet.fun/dns-query
[/tiktokv.com/]https://hkg.core.access.zznet.fun/dns-query
[/tiktokv.us/]https://hkg.core.access.zznet.fun/dns-query
# > OpenAI / Claude
[/openai.com/]https://hkg.core.access.zznet.fun/dns-query
[/chatgpt.com/]https://hkg.core.access.zznet.fun/dns-query
[/sora.com/]https://hkg.core.access.zznet.fun/dns-query
[/oaistatic.com/]https://hkg.core.access.zznet.fun/dns-query
[/oaiusercontent.com/]https://hkg.core.access.zznet.fun/dns-query
[/anthropic.com/]https://hkg.core.access.zznet.fun/dns-query
[/claude.ai/]https://hkg.core.access.zznet.fun/dns-query
EOF
echo "✅ 配置文件创建完成。"

# 4. 创建 systemd 服务文件
echo "[4/6] 正在创建 systemd 服务..."
cat <<EOF > /etc/systemd/system/dnsproxy.service
[Unit]
Description=DNS Proxy Service
After=network-online.target

[Service]
Type=simple
User=root
LimitNOFILE=infinity
ExecStart=/usr/local/bin/dnsproxy --config-path=/etc/dnsproxy/config.yaml
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF
echo "✅ 服务文件创建完成。"

# 5. 启动服务并设置开机自启
echo "[5/6] 正在启动 dnsproxy 服务..."
systemctl daemon-reload
systemctl enable dnsproxy
systemctl restart dnsproxy

# 6. 检查状态
echo "[6/6] 检查运行状态..."
sleep 1
if systemctl is-active --quiet dnsproxy; then
    echo "======================================================"
    echo " 🎉 安装成功！dnsproxy 正在运行中。 "
    echo "======================================================"
else
    echo "======================================================"
    echo " ⚠️ dnsproxy 服务启动失败，请使用以下命令查看日志： "
    echo " journalctl -u dnsproxy.service -e "
    echo " 注意: 如果报错 'bind: address already in use'，"
    echo " 请检查 53 端口是否被 systemd-resolved 占用。"
    echo "======================================================"
fi