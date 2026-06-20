#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限，请切换到 root 或使用 sudo 运行。" 1>&2
   exit 1
fi

# 更改为你的目标自定义源
REPO="reF1nd/sing-box-releases"

# 1. 安装必要的依赖
apt-get update
apt-get install -y curl wget tar jq

# ================= 修复版：版本类型选择菜单 =================
echo "------------------------------------------------------"
echo "请选择要安装的 sing-box 版本类型："
echo "1) Latest Release (稳定版)"
echo "2) Pre-release / Latest (最新测试版/预发布版)"
echo "------------------------------------------------------"
# 关键修复：增加 < /dev/tty 强制从终端读取键盘输入，防止 curl 管道穿透
read -p "请输入数字 [1-2] (默认 1): " TYPE_CHOICE < /dev/tty
[ -z "$TYPE_CHOICE" ] && TYPE_CHOICE=1

echo "开始从自定义源 (${REPO}) 获取版本信息..."

# 3. 获取目标仓库的 Release 数据
if [ "$TYPE_CHOICE" == "2" ]; then
    echo "正在检索最新预发布版 (Pre-release)..."
    # 获取完整的 release 列表，并精准过滤出第一个 prerelease 属性为 true 的对象
    RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases" | jq '[.[] | select(.prerelease == true)][0]')
    
    # 兜底：如果该仓库没有标记为 prerelease 的版本，则退回获取最新发布的版本
    if [ -z "$RELEASE_JSON" ] || [ "$RELEASE_JSON" == "null" ]; then
        echo "提示: 未找到特定标记的 Pre-release，将获取最新发布项..."
        RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases" | jq '.[0]')
    fi
else
    echo "正在检索最新稳定版 (Release)..."
    RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest")
fi

LATEST_VERSION=$(echo "$RELEASE_JSON" | jq -r .tag_name)

if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
    echo "❌ 获取最新版本号失败，请检查网络或 API 速率限制。"
    exit 1
fi
echo "🎯 目标安装版本为: $LATEST_VERSION"
# ====================================================

# 2. 智能检测系统架构与微架构版本 (v3 嗅探)
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)
        if grep -q "avx2" /proc/cpuinfo && grep -q "bmi2" /proc/cpuinfo && grep -q "movbe" /proc/cpuinfo; then
            echo "💡 检测到当前 CPU 支持 x86-64-v3 高级指令集优化。"
            ARCH_PATTERN="linux-amd64v3"
        else
            echo "💡 当前 CPU 未完全支持 v3，将降级选择标准版 (amd64)。"
            ARCH_PATTERN="linux-amd64"
        fi
        ;;
    aarch64|arm64)
        ARCH_PATTERN="linux-arm64"
        ;;
    *)
        echo "❌ 错误: 暂不支持的系统架构 ${ARCH}"
        exit 1
        ;;
esac

# 4. 精准提取匹配架构与 C 库的下载链接
# 优先匹配：架构关键字 + glibc + 以 .tar.gz 结尾 的资产
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg pattern "$ARCH_PATTERN" '.assets[] | .browser_download_url | select(contains($pattern) and contains("glibc") and endswith(".tar.gz"))' | head -n 1)

# 【兜底逻辑 1】如果选了 v3 但刚好该版本没有 glibc 包，尝试寻找 v3 的 purego
if [ -z "$DOWNLOAD_URL" ] && [[ "$ARCH_PATTERN" == *"v3"* ]]; then
    echo "提示: 未找到 v3-glibc 包，尝试寻找 v3-purego 包..."
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg pattern "$ARCH_PATTERN" '.assets[] | .browser_download_url | select(contains($pattern) and contains("purego") and endswith(".tar.gz"))' | head -n 1)
fi

# 【兜底逻辑 2】如果依然没有，彻底降级到普通架构的 glibc 包
if [ -z "$DOWNLOAD_URL" ]; then
    echo "提示: 未能匹配到特定的 glibc 优化包，执行全局架构兜底搜索..."
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg pattern "$ARCH_PATTERN" '.assets[] | .browser_download_url | select(contains($pattern) and endswith(".tar.gz"))' | head -n 1)
fi

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    echo "❌ 错误: 未能在该 Release 中找到符合架构要求的 .tar.gz 下载链接。"
    exit 1
fi

# 从 URL 中提取最终的文件名
FILENAME=$(basename "$DOWNLOAD_URL")

echo "正在下载: $FILENAME"
echo "下载地址: $DOWNLOAD_URL"

# 下载并增加严格的失败拦截
if ! wget -O "/tmp/$FILENAME" "$DOWNLOAD_URL"; then
    echo "❌ 下载失败！请检查网络或版本号。"
    rm -f "/tmp/$FILENAME"
    exit 1
fi

# 5. 解压并安装
echo "正在解压并安装..."
cd /tmp
tar -xzf "$FILENAME"

# 使用 find 动态锁定解压出的文件夹名称（防止第三方打包的根目录名称与官方不一致）
DIR_NAME=$(tar -tzf "$FILENAME" | head -n 1 | cut -f1 -d"/")

# 安全替换：如果旧服务在运行，先停止它
systemctl stop sing-box 2>/dev/null

# 放置二进制文件并赋权
mv "$DIR_NAME/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# 清理垃圾
rm -rf "$FILENAME" "$DIR_NAME"

# 6. 配置 Systemd 服务 (保持你指定的精简 Root 权限版)
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

# 7. 生成默认空配置
mkdir -p /etc/sing-box
if [ ! -f /etc/sing-box/config.json ]; then
    echo "{}" > /etc/sing-box/config.json
    echo "已创建初始空配置：/etc/sing-box/config.json"
fi

# 8. 启动服务
systemctl daemon-reload
systemctl enable sing-box

echo ""
echo "======================================================"
echo "✅ 特化版 sing-box $LATEST_VERSION 安装成功！"
echo "======================================================"
echo "已下载目标:   $FILENAME"
echo "二进制文件:   /usr/local/bin/sing-box"
echo "配置文件:     /etc/sing-box/config.json"
echo "------------------------------------------------------"
echo "请将你的代理配置填入 config.json 后，执行以下命令启动："
echo "  sudo systemctl start sing-box"
echo "======================================================"
