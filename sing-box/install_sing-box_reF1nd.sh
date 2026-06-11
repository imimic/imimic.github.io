#!/bin/bash

# 检查是否为 Root 用户
if [ "$(id -u)" != "0" ]; then
    echo "错误: 请以 root 用户运行此脚本。"
    exit 1
fi

REPO="reF1nd/sing-box-releases"

# 1. 智能检测系统架构与微架构版本
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)
        # 检查 CPU 是否支持 v3 指令集
        if grep -q "avx2" /proc/cpuinfo && grep -q "bmi2" /proc/cpuinfo && grep -q "movbe" /proc/cpuinfo; then
            echo "检测到当前 CPU 支持 x86-64-v3 高级指令集优化。"
            # 注意：对接图片中的命名，作者写的是 amd64v3，去掉了中间的短横线
            ARCH_PATTERN="linux-amd64v3"
        else
            echo "当前 CPU 未完全支持 v3，将降级选择标准版 (amd64)。"
            ARCH_PATTERN="linux-amd64"
        fi
        ;;
    aarch64|arm64)
        ARCH_PATTERN="linux-arm64"
        ;;
    *)
        echo "错误: 不支持的架构 ${ARCH}"
        exit 1
        ;;
esac

echo "正在获取 ${REPO} 的最新版本信息..."

# 获取最新 Release 的 Tag Name
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "${LATEST_RELEASE}" ]; then
    echo "错误: 无法获取最新版本，请检查网络或 API 速率限制。"
    exit 1
fi

echo "最新版本: ${LATEST_RELEASE}"

# 2. 精准提取下载链接（锁定架构 + glibc）
ALL_URLS=$(curl -s "https://api.github.com/repos/${REPO}/releases/latest" | grep '"browser_download_url":' | sed -E 's/.*"([^"]+)".*/\1/')

# 尝试寻找 对应架构 + glibc 的压缩包
DOWNLOAD_URL=$(echo "${ALL_URLS}" | grep "${ARCH_PATTERN}" | grep "glibc" | grep -E '\.tar\.gz$|\.zip$' | head -n 1)

# 【兜底逻辑 1】如果选了 v3 但该版本没有对应的 glibc 包，尝试找 v3 的 purego
if [ -z "${DOWNLOAD_URL}" ] && [[ "${ARCH_PATTERN}" == *"v3"* ]]; then
    echo "提示: 未找到 v3-glibc 包，尝试寻找 v3-purego 包..."
    DOWNLOAD_URL=$(echo "${ALL_URLS}" | grep "${ARCH_PATTERN}" | grep "purego" | grep -E '\.tar\.gz$|\.zip$' | head -n 1)
fi

# 【兜底逻辑 2】如果依然没有，彻底降级到普通 amd64-glibc
if [ -z "${DOWNLOAD_URL}" ]; then
    echo "提示: 未能匹配到特定优化包，执行全局架构兜底搜索..."
    DOWNLOAD_URL=$(echo "${ALL_URLS}" | grep "${ARCH_PATTERN}" | grep -E '\.tar\.gz$|\.zip$' | head -n 1)
fi

if [ -z "${DOWNLOAD_URL}" ]; then
    echo "错误: 未能在该 Release 中找到符合要求的下载链接。"
    exit 1
fi

echo "最终决定下载: ${DOWNLOAD_URL}"

# 3. 创建临时目录并下载解压
TMP_DIR=$(mktemp -d)
cd "${TMP_DIR}" || exit

if [[ "${DOWNLOAD_URL}" == *".tar.gz" ]]; then
    curl -L "${DOWNLOAD_URL}" -o sing-box.tar.gz
    tar -zxf sing-box.tar.gz
elif [[ "${DOWNLOAD_URL}" == *".zip" ]]; then
    curl -L "${DOWNLOAD_URL}" -o sing-box.zip
    unzip sing-box.zip
fi

# 寻找到解压后的 sing-box 二进制文件并安装
BINARY_PATH=$(find . -type f -name "sing-box" | head -n 1)

if [ -z "${BINARY_PATH}" ]; then
    echo "错误: 解压文件中未找到 sing-box 二进制程序。"
    rm -rf "${TMP_DIR}"
    exit 1
fi

chmod +x "${BINARY_PATH}"
mv "${BINARY_PATH}" /usr/local/bin/sing-box

# 清理临时文件
rm -rf "${TMP_DIR}"

# 验证安装
if [ -x "$(command -v sing-box)" ]; then
    echo "--------------------------------------------------"
    echo "sing-box 安装成功！"
    sing-box version
    echo "--------------------------------------------------"
else
    echo "错误: sing-box 安装失败。"
    exit 1
fi