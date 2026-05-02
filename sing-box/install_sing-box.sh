#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限，请切换到 root 或使用 sudo 运行。" 1>&2
   exit 1
fi

echo "开始安装最新版 sing-box..."

# 1. 安装必要的依赖 (curl 用于请求 API，jq 用于解析 JSON)
apt-get update
apt-get install -y curl wget tar jq

# 2. 获取 GitHub 上最新的版本号
echo "正在获取最新版本号..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r .tag_name | sed 's/^v//')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
    echo "获取最新版本号失败，请检查你的网络是否能正常访问 GitHub。"
    exit 1
fi
echo "当前最新版本为: $LATEST_VERSION"

# 3. 智能检测 CPU 架构 (决定使用 amd64 还是 amd64v3)
if grep -q "avx2" /proc/cpuinfo; then
    ARCH="amd64v3"
    echo "检测到 CPU 支持 AVX2，将为你下载性能更优的 $ARCH 版本。"
else
    ARCH="amd64"
    echo "未检测到 AVX2，将为你下载兼容性最强的 $ARCH 版本。"
fi

# 4. 拼接下载链接并下载 (统一使用 glibc 稳定版)
FILENAME="sing-box-${LATEST_VERSION}-linux-${ARCH}-glibc.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VERSION}/${FILENAME}"

echo "正在下载: $FILENAME"
wget -O "/tmp/$FILENAME" "$DOWNLOAD_URL"

# 5. 解压并放置二进制文件
echo "正在解压并安装..."
cd /tmp
tar -xzf "$FILENAME"
DIR_NAME="sing-box-${LATEST_VERSION}-linux-${ARCH}-glibc"

# 移动二进制文件并赋予执行权限
mv "$DIR_NAME/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# 清理临时文件
rm -rf "$FILENAME" "$DIR_NAME"

# 6. 配置 Systemd 后台服务
echo "正在配置 systemd 守护进程..."
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

# 创建配置文件目录
mkdir -p /etc/sing-box
if [ ! -f /etc/sing-box/config.json ]; then
    echo "{}" > /etc/sing-box/config.json
    echo "已创建初始空配置：/etc/sing-box/config.json"
fi

# 7. 重载 systemd 并设置开机自启
systemctl daemon-reload
systemctl enable sing-box

echo ""
echo "======================================================"
echo "✅ sing-box $LATEST_VERSION ($ARCH-glibc) 安装成功！"
echo "======================================================"
echo "二进制文件: /usr/local/bin/sing-box"
echo "配置文件:   /etc/sing-box/config.json"
echo "------------------------------------------------------"
echo "注意：由于目前配置文件为空，服务已设为【开机自启】但【尚未启动】。"
echo "请将你的代理节点信息填入 config.json 后，执行以下命令启动："
echo ""
echo "  sudo systemctl start sing-box"
echo ""
echo "查看实时运行日志的命令："
echo "  sudo journalctl -u sing-box -f"
echo "======================================================"