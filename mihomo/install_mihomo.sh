#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要 root 权限，请切换到 root 或使用 sudo 运行。" 1>&2
    exit 1
fi

echo "开始从官方源安装最新版 mihomo (v3 架构)..."

# 1. 安装必要的依赖 (gzip 用于解压 .gz)
apt-get update
apt-get install -y curl wget jq gzip

# 2. 获取 GitHub 官方最新版本号
echo "正在获取最新版本号..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | jq -r .tag_name)

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
    echo "❌ 获取最新版本号失败，请检查网络或 GitHub API 限制。"
    exit 1
fi
echo "当前官方最新版本为: $LATEST_VERSION"

# 3. 锁定 Linux amd64 v3 架构
ARCH="amd64-v3"
FILENAME="mihomo-linux-${ARCH}-${LATEST_VERSION}.gz"
DOWNLOAD_URL="https://github.com/MetaCubeX/mihomo/releases/download/${LATEST_VERSION}/${FILENAME}"

echo "正在下载: $FILENAME"
# 下载并增加严格的失败拦截
if ! wget -O "/tmp/$FILENAME" "$DOWNLOAD_URL"; then
    echo "❌ 下载失败！请检查网络或版本号。"
    rm -f "/tmp/$FILENAME"
    exit 1
fi

# 4. 解压并安装
echo "正在解压并安装..."
cd /tmp
# 解压 .gz 文件
gunzip -f "$FILENAME"
UNZIPPED_NAME="mihomo-linux-${ARCH}-${LATEST_VERSION}"

# 安全替换：如果旧服务在运行，先停止它
systemctl stop mihomo 2>/dev/null

# 放置二进制文件并赋权
mv "$UNZIPPED_NAME" /usr/local/bin/mihomo
chmod +x /usr/local/bin/mihomo

# 5. 配置 Systemd 服务 (采用与 sing-box 完全一致的精简 root 逻辑)
echo "正在配置 systemd..."
cat > /etc/systemd/system/mihomo.service << 'EOF'
[Unit]
Description=mihomo service
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# 6. 生成配置目录和默认空配置
mkdir -p /etc/mihomo
if [ ! -f /etc/mihomo/config.yaml ]; then
    touch /etc/mihomo/config.yaml
    echo "已创建初始空配置：/etc/mihomo/config.yaml"
fi

# 7. 启动服务
systemctl daemon-reload
systemctl enable mihomo

echo ""
echo "======================================================"
echo "✅ 官方版 mihomo $LATEST_VERSION ($ARCH) 安装成功！"
echo "======================================================"
echo "二进制文件: /usr/local/bin/mihomo"
echo "配置目录:   /etc/mihomo/"
echo "主配置文件: /etc/mihomo/config.yaml"
echo "------------------------------------------------------"
echo "请将你的 YAML 节点配置写入 config.yaml，然后执行启动："
echo "  sudo systemctl start mihomo"
echo "查看运行日志："
echo "  journalctl -u mihomo -f"
echo "======================================================"