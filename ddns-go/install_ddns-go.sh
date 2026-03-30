# 1. 更新并安装必要依赖 (加入 curl 用于请求 API)
sudo apt update && sudo apt install -y curl wget tar vim && \

# 2. 自动检测系统架构
ARCH=$(uname -m) && \
if [ "$ARCH" = "x86_64" ]; then FILE_ARCH="x86_64"; elif [ "$ARCH" = "aarch64" ]; then FILE_ARCH="arm64"; else echo "不支持的架构: $ARCH" && exit 1; fi && \

# 3. 核心魔法：从 GitHub API 动态抓取最新版下载链接
echo "正在获取 ddns-go 最新版本..." && \
LATEST_URL=$(curl -s https://api.github.com/repos/jeessy2/ddns-go/releases/latest | grep "browser_download_url" | grep "linux_${FILE_ARCH}.tar.gz" | head -n 1 | cut -d '"' -f 4) && \
echo "最新版本直链: $LATEST_URL" && \

# 4. 创建临时目录并下载解压
cd ~ && rm -rf ddns-go-temp && mkdir -p ddns-go-temp && cd ddns-go-temp && \
wget -O ddns-go.tar.gz "$LATEST_URL" && \
tar -zxvf ddns-go.tar.gz && \

# 5. 停止旧服务（如果是用来升级，这一步能防止文件被占用）
sudo /usr/local/bin/ddns-go -s uninstall 2>/dev/null ; \

# 6. 安装二进制文件并注册系统服务
sudo install -m 0755 ddns-go /usr/local/bin/ddns-go && \
sudo /usr/local/bin/ddns-go -s install && \

# 7. 清理临时文件
cd ~ && rm -rf ddns-go-temp && \

# 8. 完工撒花
echo -e "\n✅ ddns-go 最新版安装/升级完成并已启动！\n👉 请在浏览器中访问 http://<你的服务器IP>:9876 进行配置。"