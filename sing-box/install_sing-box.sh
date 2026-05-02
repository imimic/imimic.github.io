#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限，请切换到 root 或使用 sudo 运行。" 1>&2
   exit 1
fi

echo "开始从官方源安装最新版 sing-box..."

# 1. 安装必要的依赖
apt-get update
apt-get install -y curl wget tar jq

# 2. 获取 GitHub 官方最新版本号
echo "正在获取最新版本号..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/^v//')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
    echo "获取最新版本号失败，请检查网络。"
    exit 1
fi
echo "当前官方最新版本为: $LATEST_VERSION"

# 3. 锁定官方唯一的高性能版本 (amd64-glibc)
ARCH="amd64"
FILENAME="sing-box-${LATEST_VERSION}-linux-${ARCH}-glibc.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/${FILENAME}"

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
tar -xzf "$FILENAME"
DIR_NAME="sing-box-${LATEST_VERSION}-linux-${ARCH}-glibc"

# 安全替换：如果旧服务在运行，先停止它
systemctl stop sing-box 2>/dev/null

# 放置二进制文件并赋权
mv "$DIR_NAME/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# 清理垃圾
rm -rf "$FILENAME" "$DIR_NAME"

# 5. 配置 Systemd 服务 (使用你指定的精简 Root 权限版)
echo "正在配置 systemd..."
cat > /etc/systemd/system/sing-box.service << 'EOF'
[Unit]
Description=sing-box service
After=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

# 6. 生成默认空配置
mkdir -p /etc/sing-box
if [ ! -f /etc/sing-box/config.json ]; then
    echo "{}" > /etc/sing-box/config.json
    echo "已创建初始空配置：/etc/sing-box/config.json"
fi

# 7. 启动服务
systemctl daemon-reload
systemctl enable sing-box

echo ""
echo "======================================================"
echo "✅ 官方版 sing-box $LATEST_VERSION ($ARCH-glibc) 安装成功！"
echo "======================================================"
echo "二进制文件: /usr/local/bin/sing-box"
echo "配置文件:   /etc/sing-box/config.json"
echo "------------------------------------------------------"
echo "请将你的代理配置填入 config.json 后，执行以下命令启动："
echo "  sudo systemctl start sing-box"
echo "======================================================"
