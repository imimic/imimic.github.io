#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限，请切换到 root 或使用 sudo 运行。" 1>&2
   exit 1
fi

# 1. 指定版本号和相关参数
VERSION="1.10.7"
ARCH="amd64"
FILENAME="sing-box-${VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/${FILENAME}"
DIR_NAME="sing-box-${VERSION}-linux-${ARCH}"

echo "开始安装指定版 sing-box v${VERSION}..."

# 2. 安装必要的依赖 (移除了不需要的 jq 和 curl)
apt-get update
apt-get install -y wget tar

# 3. 下载指定的安装包
echo "正在下载: $FILENAME"
# 下载并增加严格的失败拦截
if ! wget -O "/tmp/$FILENAME" "$DOWNLOAD_URL"; then
    echo "❌ 下载失败！请检查网络或链接是否有效。"
    rm -f "/tmp/$FILENAME"
    exit 1
fi

# 4. 解压并安装
echo "正在解压并安装..."
cd /tmp
tar -xzf "$FILENAME"

# 安全替换：如果旧服务在运行，先停止它
systemctl stop sing-box 2>/dev/null

# 放置二进制文件并赋权
mv "$DIR_NAME/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# 清理垃圾包和临时文件夹
rm -rf "$FILENAME" "$DIR_NAME"

# 5. 配置 Systemd 服务 (维持精简 Root 权限版)
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
echo "✅ sing-box v$VERSION ($ARCH) 安装成功！"
echo "======================================================"
echo "二进制文件: /usr/local/bin/sing-box"
echo "配置文件:   /etc/sing-box/config.json"
echo "------------------------------------------------------"
echo "请将你的代理配置填入 config.json 后，执行以下命令启动："
echo "  sudo systemctl start sing-box"
echo "======================================================"