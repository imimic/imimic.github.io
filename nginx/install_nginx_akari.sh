#!/bin/bash

# 遇到错误即停止执行
set -e

# 检查是否为 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本 (例如: sudo bash $0)"
  exit 1
fi

echo "=========================================="
echo "          开始安装并配置 Nginx            "
echo "=========================================="

echo ">>> 1. 正在安装依赖并添加 Nginx 官方源..."
apt update
apt install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring

# 导入 Nginx 官方 GPG 密钥
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg --yes

# 添加 Nginx mainline 仓库源
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
https://nginx.org/packages/mainline/debian $(lsb_release -cs) nginx" \
    | tee /etc/apt/sources.list.d/nginx.list >/dev/null

echo ">>> 正在更新软件源并安装 Nginx..."
apt update
apt install -y nginx

echo ">>> 2. 正在写入 Nginx 配置文件..."
# 备份原有的配置文件（以防万一）
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

# 使用 'EOF' 写入多行文本，单引号防止 bash 提前解析 $ 符号变量
cat << 'EOF' > /etc/nginx/nginx.conf
user nginx;
worker_processes auto;

error_log /var/log/nginx/error.log notice;
pid       /var/run/nginx.pid;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

stream {

    map $ssl_preread_server_name $target_backend {
        hostnames;

        ""                          127.0.0.1:1;

        # Hotstar
        .hotstar.com                185.36.192.252:443;
        .hotstarext.com             185.36.192.252:443;

        # OpenAI / Claude / Google / Microsoft
        .openai.com                 185.36.192.252:443;
        .chatgpt.com                185.36.192.252:443;
        .sora.com                   185.36.192.252:443;
        .oaistatic.com              185.36.192.252:443;
        .oaiusercontent.com         185.36.192.252:443;
        .anthropic.com              185.36.192.252:443;
        .claude.ai                  185.36.192.252:443;
        .google.com                 185.36.192.252:443;
        .googleapis.com             185.36.192.252:443;
        .app-analytics-services.com 185.36.192.252:443;
        .copilot.microsoft.com      185.36.192.252:443;

        default                     $ssl_preread_server_name:443;
    }

    server {
        resolver 163.53.18.252 valid=60s ipv6=off;
        listen 443 reuseport;
        ssl_preread on;
        tcp_nodelay on;
        proxy_connect_timeout 5s; 
        proxy_timeout 300s;
        proxy_pass $target_backend;
    }

}
EOF

echo ">>> 3. 正在重启并启用 Nginx 服务..."
systemctl restart nginx
systemctl enable nginx

echo "=========================================="
echo " Nginx 安装和配置已全部完成！"
echo " 代理已监听在端口: 443"
echo "=========================================="
# 输出当前运行状态
systemctl status nginx --no-pager | grep "Active:"
