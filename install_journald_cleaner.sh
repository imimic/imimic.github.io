#!/bin/bash

# 确保脚本以 root 权限运行
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 权限运行此脚本 (例如: sudo bash script.sh)"
  exit 1
fi

echo "⏳ 正在部署 systemd-journald 原生日志管控规则..."

# 1. 创建专门的 drop-in 配置目录（如果不存在）
mkdir -p /etc/systemd/journald.conf.d/

# 2. 写入你的专属配置，优先级设为 99（最高）
cat > /etc/systemd/journald.conf.d/99-custom-cleanup.conf << "EOF"
[Journal]
SystemMaxUse=50M
MaxRetentionSec=1day
EOF

# 3. 重启系统日志服务，让配置立刻永久生效
systemctl restart systemd-journald

# 4. 顺手执行一次手动清理，把以前堆积的老垃圾直接扬了
echo "🧹 正在清理当前堆积的历史日志..."
journalctl --vacuum-time=1d
journalctl --vacuum-size=50M

# 5. 完工撒花
echo -e "\n✅ 原生日志管控部署完成！"
echo "👉 以后系统将自动接管，日志最多保留 1天 且 永远不会超过 50M。"