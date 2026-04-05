#!/bin/bash

# 1. 询问并设置自定义端口 (强制从终端 /dev/tty 读取键盘输入)
read -p "👉 请输入 ddns-go 的监听端口 (直接回车默认使用 9876): " CUSTOM_PORT < /dev/tty
CUSTOM_PORT=${CUSTOM_PORT:-9876}
echo "✅ 确认使用端口: $CUSTOM_PORT"

# 2. 更新并安装必要依赖
sudo apt update && sudo apt install -y curl wget tar vim

# 3. 自动检测系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then FILE_ARCH="x86_64"; elif [ "$ARCH" = "aarch64" ]; then FILE_ARCH="arm64"; else echo "不支持的架构: $ARCH" && exit 1; fi

# 4. 从 GitHub API 动态抓取最新版下载链接
echo "正在获取 ddns-go 最新版本..."
LATEST_URL=$(curl -s https://api.github.com/repos/jeessy2/ddns-go/releases/latest | grep "browser_download_url" | grep "linux_${FILE_ARCH}.tar.gz" | head -n 1 | cut -d '"' -f 4)
echo "最新版本直链: $LATEST_URL"

# 5. 创建临时目录并下载解压
cd ~ && rm -rf ddns-go-temp && mkdir -p ddns-go-temp && cd ddns-go-temp
wget -O ddns-go.tar.gz "$LATEST_URL"
tar -zxvf ddns-go.tar.gz

# 6. 停止旧服务（防文件占用）
sudo /usr/local/bin/ddns-go -s uninstall 2>/dev/null

# 7. 安装二进制文件并注册系统服务 (使用自定义端口)
sudo install -m 0755 ddns-go /usr/local/bin/ddns-go
sudo /usr/local/bin/ddns-go -s install -l :$CUSTOM_PORT

# 8. 清理临时文件
cd ~ && rm -rf ddns-go-temp

# 9. 完工撒花
echo -e "\n🎉 ddns-go 最新版安装/升级完成并已启动！"
echo -e "👉 请在浏览器中访问 http://<你的服务器IP>:$CUSTOM_PORT 进行配置。\n"
