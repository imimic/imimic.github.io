#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限，请切换到 root 或使用 sudo 运行。" 1>&2
   exit 1
fi

REPO="SagerNet/sing-box"

# 1. 安装必要的依赖
apt-get update
apt-get install -y curl wget tar jq

# ================= 新增：版本类型选择菜单 =================
echo "------------------------------------------------------"
echo "请选择要安装的 sing-box 官方版本类型："
echo "1) Latest Release (稳定版)"
echo "2) Pre-release / Latest (最新测试版/预发布版，如 beta/rc 版)"
echo "------------------------------------------------------"
# 关键修复：增加 < /dev/tty 强制从终端读取键盘输入，支持 curl | bash 远程一键流式运行
read -p "请输入数字 [1-2] (默认 1): " TYPE_CHOICE < /dev/tty
[ -z "$TYPE_CHOICE" ] && TYPE_CHOICE=1

echo "开始从官方源 (${REPO}) 获取版本信息..."

# 2. 获取 GitHub 官方版本数据
if [ "$TYPE_CHOICE" == "2" ]; then
    echo "正在检索最新预发布版 (Pre-release)..."
    # 获取完整的 release 列表，并精准过滤出第一个 prerelease 属性为 true 的对象
    RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases" | jq '[.[] | select(.prerelease == true)][0]')
    
    # 兜底：如果官方刚好这段时间没有 Pre-release，则退回获取最新发布的版本
    if [ -z "$RELEASE_JSON" ] || [ "$RELEASE_JSON" == "null" ]; then
        echo "提示: 未找到特定标记的 Pre-release，将获取最新发布项..."
        RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases" | jq '.[0]')
    fi
else
    echo "正在检索最新稳定版 (Release)..."
    RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest")
fi

# 提取带 v 的原始 tag（用于路径拼接），并去掉 v 得到纯数字版本号（用于文件名拼接）
TAG_NAME=$(echo "$RELEASE_JSON" | jq -r .tag_name)
LATEST_VERSION=$(echo "$TAG_NAME" | sed 's/^v//')

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
    echo "❌ 获取最新版本号失败，请检查网络或 API 速率限制。"
    exit 1
fi
echo "🎯 目标安装版本为: v$LATEST_VERSION"
# ====================================================

# 3. 锁定官方唯一的高性能版本 (amd64-glibc)
ARCH="amd64"
FILENAME="sing-box-${LATEST_VERSION}-linux-${ARCH}-glibc.tar.gz"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG_NAME}/${FILENAME}"

echo "正在下载: $FILENAME"
echo "下载地址: $DOWNLOAD_URL"

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
Wants=network-online.target

[Service]
Type=simple
User=root
LimitNOFILE=infinity
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json -D /etc/sing-box
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s

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
echo "✅ 官方版 sing-box v$LATEST_VERSION ($ARCH-glibc) 安装成功！"
echo "======================================================"
echo "已下载目标:   $FILENAME"
echo "二进制文件:   /usr/local/bin/sing-box"
echo "配置文件:     /etc/sing-box/config.json"
echo "------------------------------------------------------"
echo "请将你的代理配置填入 config.json 后，执行以下命令启动："
echo "  sudo systemctl start sing-box"
echo "======================================================"
