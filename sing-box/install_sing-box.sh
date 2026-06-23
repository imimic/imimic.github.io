#!/bin/bash

# 确保以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本需要 root 权限，请切换到 root 或使用 sudo 运行。" 1>&2
   exit 1
fi

# 1. 安装必要的依赖
apt-get update
apt-get install -y curl wget tar jq

echo "======================================================"
echo "          欢迎使用 sing-box 智能安装脚本"
echo "======================================================"

# ================= 步骤 1：选择内核版本源 =================
echo "请选择要安装的 sing-box 内核源："
echo "1) 官方原版 (SagerNet/sing-box)"
echo "2) reF1nd版 (reF1nd/sing-box-releases)"
echo "------------------------------------------------------"
read -p "请输入数字 [1-2] (默认 1): " REPO_CHOICE < /dev/tty
[ -z "$REPO_CHOICE" ] && REPO_CHOICE=1

if [ "$REPO_CHOICE" == "2" ]; then
    REPO="reF1nd/sing-box-releases"
    IS_OFFICIAL=false
    echo "▶ 已选择: reF1nd版"
else
    REPO="SagerNet/sing-box"
    IS_OFFICIAL=true
    echo "▶ 已选择: 官方原版"
fi

# ================= 步骤 2：版本类型选择菜单 =================
echo "------------------------------------------------------"
echo "请选择要安装的 sing-box 版本类型："
echo "1) Latest Release (稳定版)"
echo "2) Pre-release / Latest (最新测试版/预发布版，如 beta/rc 版)"
echo "------------------------------------------------------"
read -p "请输入数字 [1-2] (默认 1): " TYPE_CHOICE < /dev/tty
[ -z "$TYPE_CHOICE" ] && TYPE_CHOICE=1

echo "------------------------------------------------------"
echo "开始从源 (${REPO}) 获取版本信息..."

# ================= 步骤 3：获取 GitHub 官方版本数据 =================
if [ "$TYPE_CHOICE" == "2" ]; then
    echo "正在检索最新预发布版 (Pre-release)..."
    RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases" | jq '[.[] | select(.prerelease == true)][0]')
    
    if [ -z "$RELEASE_JSON" ] || [ "$RELEASE_JSON" == "null" ]; then
        echo "提示: 未找到特定标记的 Pre-release，将获取最新发布项..."
        RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases" | jq '.[0]')
    fi
else
    echo "正在检索最新稳定版 (Release)..."
    RELEASE_JSON=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest")
fi

TAG_NAME=$(echo "$RELEASE_JSON" | jq -r .tag_name)

if [ -z "$TAG_NAME" ] || [ "$TAG_NAME" == "null" ]; then
    echo "❌ 获取最新版本号失败，请检查网络或 API 速率限制。"
    exit 1
fi
echo "🎯 目标安装版本标签为: $TAG_NAME"

# ================= 步骤 4：智能检测系统架构并提取下载链接 =================
ARCH=$(uname -m)

if [ "$IS_OFFICIAL" = true ]; then
    # 【官方原版逻辑】固定为高性能的 amd64-glibc 
    LATEST_VERSION=$(echo "$TAG_NAME" | sed 's/^v//')
    ARCH_NAME="amd64"
    FILENAME="sing-box-${LATEST_VERSION}-linux-${ARCH_NAME}-glibc.tar.gz"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG_NAME}/${FILENAME}"
else
    # 【reF1nd版逻辑】支持多架构、v3 嗅探及性能阶梯式兜底
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
            echo "❌ 错误: reF1nd版暂不支持当前系统架构 ${ARCH}"
            exit 1
            ;;
    esac

    # 阶梯式优先级搜索下载链接
    echo "正在检索最适配当前架构的内核构建..."
    
    # 优先级 1: 架构关键字 + glibc (最高性能)
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg pattern "$ARCH_PATTERN" '.assets[] | .browser_download_url | select(contains($pattern) and contains("glibc") and endswith(".tar.gz"))' | head -n 1)

    # 优先级 2: 架构关键字 + musl (高性能次优兜底)
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        echo "提示: 未找到 glibc 包，尝试寻找 musl 高性能兜底包..."
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg pattern "$ARCH_PATTERN" '.assets[] | .browser_download_url | select(contains($pattern) and contains("musl") and endswith(".tar.gz"))' | head -n 1)
    fi

    # 优先级 3: 彻底降级（仅保障系统架构契合）
    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        echo "提示: 未能匹配到特定 C 库优化包，执行全局架构盲搜..."
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r --arg pattern "$ARCH_PATTERN" '.assets[] | .browser_download_url | select(contains($pattern) and endswith(".tar.gz"))' | head -n 1)
    fi

    if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
        echo "❌ 错误: 未能在该 Release 中找到符合架构要求的 .tar.gz 下载链接。"
        exit 1
    fi
    FILENAME=$(basename "$DOWNLOAD_URL")
fi

echo "正在下载: $FILENAME"
echo "下载地址: $DOWNLOAD_URL"

# ================= 步骤 5：下载与拦截 =================
if ! wget -O "/tmp/$FILENAME" "$DOWNLOAD_URL"; then
    echo "❌ 下载失败！请检查网络或版本号。"
    rm -f "/tmp/$FILENAME"
    exit 1
fi

# ================= 步骤 6：解压并安装 =================
echo "正在解压并安装..."
cd /tmp
tar -xzf "$FILENAME"

if [ "$IS_OFFICIAL" = true ]; then
    DIR_NAME="sing-box-${LATEST_VERSION}-linux-${ARCH_NAME}-glibc"
else
    # 动态锁定解压出的文件夹名称
    DIR_NAME=$(tar -tzf "$FILENAME" | head -n 1 | cut -f1 -d"/")
fi

# 安全替换：如果旧服务在运行，先停止它
systemctl stop sing-box 2>/dev/null

# 放置二进制文件并赋权
mv "$DIR_NAME/sing-box" /usr/local/bin/
chmod +x /usr/local/bin/sing-box

# 清理垃圾
rm -rf "$FILENAME" "$DIR_NAME"

# ================= 步骤 7：配置 Systemd 服务 =================
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

# ================= 步骤 8：生成默认空配置 =================
mkdir -p /etc/sing-box
if [ ! -f /etc/sing-box/config.json ]; then
    echo "{}" > /etc/sing-box/config.json
    echo "已创建初始空配置：/etc/sing-box/config.json"
fi

# ================= 步骤 9：启动服务 =================
systemctl daemon-reload
systemctl enable sing-box

echo ""
echo "======================================================"
echo "✅ sing-box 安装/更新成功！"
echo "======================================================"
echo "所选内核源:   $( [ "$IS_OFFICIAL" = true ] && echo "官方原版" || echo "reF1nd版" )"
echo "已下载目标:   $FILENAME"
echo "二进制文件:   /usr/local/bin/sing-box"
echo "配置文件:     /etc/sing-box/config.json"
echo "------------------------------------------------------"
echo "请将你的代理配置填入 config.json 后，执行以下命令启动："
echo "  sudo systemctl start sing-box"
echo "======================================================"