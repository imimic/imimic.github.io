#!/usr/bin/env bash

echo "=========================================="
echo "  Netflix 状态检测与 TG 通知 一键配置脚本  "
echo "=========================================="

# 1. 从终端 /dev/tty 读取键盘输入
read -p "👉 请输入 Telegram Bot Token (必填): " BOT_TOKEN < /dev/tty
read -p "👉 请输入 Telegram Chat ID (必填): " CHAT_ID < /dev/tty

# 2. 生成主检测脚本
echo "[1/4] 正在创建检测脚本 /usr/local/bin/nf_hk_check_notify.sh ..."
sudo tee /usr/local/bin/nf_hk_check_notify.sh >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ====== 自动生成的配置 ======
BOT_TOKEN="REPLACE_BOT_TOKEN"
CHAT_ID="REPLACE_CHAT_ID"
# ============================

CHECK_URL="https://raw.githubusercontent.com/1-stream/RegionRestrictionCheck/main/check.sh"
STATE_FILE="/var/lib/nf-hk-check/state"
TMP_DIR="/tmp/nf-hk-check"

mkdir -p "$(dirname "$STATE_FILE")" "$TMP_DIR"

OUT="$(
  bash <(curl -fsSL "$CHECK_URL") <<< "2" -M 4 2>&1 | tee "$TMP_DIR/last.out"
)"

# 抓 Netflix 行
NF_LINE="$(echo "$OUT" | grep -E '^[[:space:]]*Netflix:' | head -n 1 || true)"
# 去 ANSI 颜色码 + 去不可见控制字符
NF_LINE="$(printf "%s" "$NF_LINE" | sed -r 's/\x1B\[[0-9;]*[mK]//g' | tr -cd '\11\12\15\40-\176')"
# 去掉 "Netflix:" 前缀 + trim 左侧空格
NF_LINE="${NF_LINE#Netflix:}"
NF_LINE="$(echo "$NF_LINE" | sed -E 's/^[[:space:]]+//')"

# 兜底
if [[ -z "${NF_LINE}" ]]; then
  NF_LINE="未捕获到 Netflix 行"
fi

# 含 "Yes (Region: HK)" 视为正常，否则异常
if printf "%s" "$NF_LINE" | grep -Fq "Yes (Region: HK)"; then
  CUR="OK"
else
  CUR="BAD"
fi

# 读取上次状态
PREV="OK"
if [[ -f "$STATE_FILE" ]]; then
  PREV="$(sed -n '1p' "$STATE_FILE" 2>/dev/null || echo "OK")"
fi

# 保存本次状态与状态行
{
  echo "$CUR"
  echo "$NF_LINE"
} > "$STATE_FILE"

# 只在状态变化时通知：OK->BAD 或 BAD->OK
if [[ "$CUR" != "$PREV" ]]; then
  NOW="$(date '+%F %T %Z')"
  HOST="$(hostname)"
  
  # 获取公网 IPv4 地址 (设置 5 秒超时，避免网络问题导致脚本卡死)
  PUBLIC_IP="$(curl -4 -sS --max-time 5 https://api.ipify.org || echo "获取失败")"

  if [[ "$CUR" == "BAD" ]]; then
    TITLE="⚠️ <b>Netflix 状态异常</b>"
  else
    TITLE="✅ <b>Netflix 已恢复正常</b>"
  fi

  # HTML 转义
  SAFE_LINE="${NF_LINE//&/&amp;}"
  SAFE_LINE="${SAFE_LINE//</&lt;}"
  SAFE_LINE="${SAFE_LINE//>/&gt;}"

  MSG="${TITLE}
━━━━━━━━━━━━
🖥️ <b>主机</b>：${HOST}
🌐 <b>IPv4</b>：${PUBLIC_IP}
🕒 <b>时间</b>：${NOW}
📌 <b>状态</b>：<code>${SAFE_LINE}</code>
━━━━━━━━━━━━"

  curl -fsS "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "parse_mode=HTML" \
    --data-urlencode "text=${MSG}" \
    -d "disable_web_page_preview=true" >/dev/null
fi
EOF

# 替换配置变量并赋予执行权限
sudo sed -i "s/REPLACE_BOT_TOKEN/${BOT_TOKEN}/g" /usr/local/bin/nf_hk_check_notify.sh
sudo sed -i "s/REPLACE_CHAT_ID/${CHAT_ID}/g" /usr/local/bin/nf_hk_check_notify.sh
sudo chmod +x /usr/local/bin/nf_hk_check_notify.sh

# 3. 创建 systemd service
echo "[2/4] 正在创建 systemd service ..."
sudo tee /etc/systemd/system/nf-hk-check.service >/dev/null << 'EOF'
[Unit]
Description=Check Netflix HK status and notify Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nf_hk_check_notify.sh
User=root
EOF

# 4. 创建 systemd timer
echo "[3/4] 正在创建 systemd timer (每小时执行) ..."
sudo tee /etc/systemd/system/nf-hk-check.timer >/dev/null << 'EOF'
[Unit]
Description=Run nf-hk-check hourly

[Timer]
OnBootSec=3min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 5. 重载配置并启动服务
echo "[4/4] 正在重载 systemd 并启动定时任务 ..."
sudo systemctl daemon-reload
sudo systemctl enable --now nf-hk-check.timer

echo ""
echo "=========================================="
echo "✅ 安装与配置完成！"
echo "=========================================="
echo "🔍 检查定时任务状态："
systemctl list-timers --all | grep nf-hk-check || echo "等待下一次触发..."
echo ""
echo "💡 手动触发测试命令（可随时运行测试逻辑）："
echo "sudo bash /usr/local/bin/nf_hk_check_notify.sh"
