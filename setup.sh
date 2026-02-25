#!/bin/bash

# ==========================================
# ۱. دریافت اطلاعات اولیه
# ==========================================
clear
echo -e "\e[1;35m====================================================\e[0m"
echo -e "\e[1;33m       UNIVERSAL PRO SETUP BY SADEGH (2026)         \e[0m"
echo -e "\e[1;35m====================================================\e[0m"

read -p "🌍 نام کشور مقصد (مثلاً Germany یا Turkey): " DEST_COUNTRY
read -p "🎯 آی‌پی سرور مقصد: " DEST_IP
read -p "📅 تاریخ انقضا (YYYY-MM-DD): " EXP_DATE
read -p "💾 سقف ترافیک ماهانه (GB): " TRAFFIC_LIMIT

DEST_COUNTRY=${DEST_COUNTRY:-"Destination"}
DEST_IP=${DEST_IP:-"1.1.1.1"}
EXP_DATE=${EXP_DATE:-"2026-03-10"}
TRAFFIC_LIMIT=${TRAFFIC_LIMIT:-"100"}

# ==========================================
# ۲. نصب ابزارها و فعال‌سازی BBR
# ==========================================
apt update && apt install -y wget tar ipset iptables-persistent curl nethogs iftop bc vnstat certbot nano
systemctl enable --now vnstat

modprobe tcp_bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# ==========================================
# ۳. مدیریت SSL (Certbot)
# ==========================================
echo -ne "\n\e[1;33mآیا مایل به دریافت SSL هستید؟ (y/n): \e[0m"
read -r INSTALL_SSL
if [[ "$INSTALL_SSL" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    certbot certonly --standalone -d gost.plusne.ir --preferred-challenges http --agree-tos --register-unsafely-without-email
fi

# ==========================================
# ۴. نصب AdGuardHome و Gost و ttyd
# ==========================================
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

wget https://github.com/go-gost/gost/releases/download/v3.0.0-rc10/gost_3.0.0-rc10_linux_amd64.tar.gz
tar xvf gost_3.0.0-rc10_linux_amd64.tar.gz
mv gost /usr/local/bin/gost && chmod +x /usr/local/bin/gost

wget https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64
mv ttyd.x86_64 /usr/local/bin/ttyd && chmod +x /usr/local/bin/ttyd

# ==========================================
# ۵. ساخت پنل کاربری نهایی (panel.sh)
# ==========================================
cat <<'EOF' > /root/panel.sh
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

while true; do
    clear
    source ~/.bashrc
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "${CYAN}       🚀 GOST MANAGEMENT PANEL (2026) 🚀          ${NC}"
    echo -e "${PURPLE}====================================================${NC}"
    echo -e "  ${YELLOW}1)${NC} 📊 مشاهده مصرف ترافیک (vnStat)"
    echo -e "  ${YELLOW}2)${NC} ➕ اضافه کردن حجم اضافه (AddGig)"
    echo -e "  ${YELLOW}3)${NC} 🚫 لیست سیاه (Blacklist)"
    echo -e "  ${YELLOW}4)${NC} 🔄 ریستارت سرویس‌ها"
    echo -e "  ${YELLOW}5)${NC} 📝 مشاهده لاگ‌های Gost"
    echo -e "  ${YELLOW}6)${NC} 🛠️  ویرایش کانفیگ Gost"
    echo -e "  ${YELLOW}0)${NC} ❌ خروج"
    echo -e "${PURPLE}====================================================${NC}"
    read -p "گزینه مورد نظر: " choice
    case $choice in
        1) clear; vnstat -d; echo "Enter برای بازگشت..."; read ;;
        2) read -p "چند گیگ اضافه شود؟: " gb; addgig $gb; sleep 2 ;;
        3) clear; ipset list blacklist; echo "Enter برای بازگشت..."; read ;;
        4) systemctl restart gost gost-ui adguard-monitor; echo "انجام شد!"; sleep 2 ;;
        5) clear; journalctl -u gost -n 50 --no-pager; echo "Enter برای بازگشت..."; read ;;
        6) nano /usr/local/etc/gost.yaml; systemctl restart gost ;;
        0) exit 0 ;;
    esac
done
EOF
chmod +x /root/panel.sh

# ==========================================
# ۶. تنظیمات Gost و IPSet و Monitor
# ==========================================
mkdir -p /usr/local/etc/
cat <<EOF > /usr/local/etc/gost.yaml
services:
  - name: service-443
    addr: "127.0.0.1:443"
    handler: { type: tcp }
    listener: { type: tcp }
    forwarder:
      nodes: &dest_node
        - name: ${DEST_COUNTRY,,}
          addr: "$DEST_IP:8443"
          connector: { type: relay }
          transporter: { type: tcp }
  - name: service-80
    addr: "127.0.0.1:80"
    handler: { type: tcp }
    listener: { type: tcp }
    forwarder: { nodes: *dest_node }
  - name: service-udp
    addr: "127.0.0.1:10000"
    handler: { type: udp }
    listener: { type: udp }
    forwarder: { nodes: *dest_node }
log:
  level: info
EOF

# اسکریپت مانیتورینگ AdGuard برای IPSet
cat <<'EOF' > /usr/local/bin/adguard-monitor.sh
#!/bin/bash
SET_NAME="allowed_users"
ipset create $SET_NAME hash:ip timeout 3600 --exist
journalctl -u AdGuardHome -f -n 0 | while read -r LINE; do
    if [[ "$LINE" == *"client ip for stats"* ]]; then
        CLIENT_IP=$(echo "$LINE" | grep -oP 'ip=\K[0-9.]+')
        if [ ! -z "$CLIENT_IP" ] && [ "$CLIENT_IP" != "127.0.0.1" ]; then
            ipset add $SET_NAME "$CLIENT_IP" -exist
        fi
    fi
done
EOF
chmod +x /usr/local/bin/adguard-monitor.sh

# تنظیمات Iptables
ipset create allowed_users hash:ip timeout 3600 counters 2>/dev/null
ipset create blacklist hash:ip 2>/dev/null
iptables -F && iptables -t nat -F
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp -m multiport --dports 80,443,2053 -j ACCEPT
iptables -t nat -A PREROUTING -p tcp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:443
iptables -t nat -A POSTROUTING -j MASQUERADE
netfilter-persistent save

# ==========================================
# ۷. ساخت وب‌پنل PWA (فایل index.html)
# ==========================================
mkdir -p /root/web_panel
cat <<EOF > /root/web_panel/index.html
<!DOCTYPE html>
<html lang="fa">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=0.1, maximum-scale=5.0">
    <link rel="manifest" href="manifest.json">
    <title>GOST PRO - $DEST_COUNTRY</title>
    <style>
        * { box-sizing: border-box; background-color: #000000 !important; }
        body, html { margin: 0; padding: 0; height: 100%; overflow: hidden; background: #000 !important; color: #00ff41; }
        header { height: 50px; background: #000 !important; display: flex; align-items: center; justify-content: space-between; padding: 0 15px; border-bottom: 1px solid #1a1a1a; }
        .brand { color: #00ff41; font-weight: bold; font-family: sans-serif; display: flex; align-items: center; gap: 8px; }
        .dot { width: 8px; height: 8px; background: #00ff41; border-radius: 50%; box-shadow: 0 0 8px #00ff41; }
        .exit-btn { background: #300 !important; color: #f44 !important; border: 1px solid #f44; padding: 4px 12px; border-radius: 6px; font-size: 12px; cursor: pointer; font-weight: bold; }
        .terminal-wrapper { height: calc(100% - 50px); width: 100%; overflow: auto; -webkit-overflow-scrolling: touch; }
        iframe { border: none; display: block; height: 100%; width: 100%; }
        #login-screen { position: fixed; inset: 0; background: #000; z-index: 999; display: flex; flex-direction: column; align-items: center; justify-content: center; }
    </style>
</head>
<body>
    <div id="login-screen">
        <h3 style="color:#00ff41; font-family:sans-serif; letter-spacing:2px;">GOST SECURITY</h3>
        <input type="password" id="pass-input" style="background:#111 !important; border:1px solid #00ff41; color:#00ff41; padding:12px; border-radius:8px; text-align:center; width:220px;" placeholder="PASSWORD">
        <button style="margin-top:20px; background:#00ff41 !important; color:#000 !important; padding:12px 40px; border:none; border-radius:8px; font-weight:bold; cursor:pointer;" onclick="checkPass()">LOGIN</button>
    </div>
    <div id="app" style="display:none; height:100%; flex-direction:column;">
        <header>
            <div class="brand"><div class="dot"></div> GOST ULTIMATE ($DEST_COUNTRY)</div>
            <button class="exit-btn" onclick="logout()">EXIT</button>
        </header>
        <div class="terminal-wrapper">
            <iframe src="https://gost.plusne.ir:2053"></iframe>
        </div>
    </div>
<script>
    const app = document.getElementById('app');
    const login = document.getElementById('login-screen');
    if (localStorage.getItem('isLogged') === 'true') {
        login.style.display = 'none';
        app.style.display = 'flex';
    }
    function checkPass() {
        if (document.getElementById('pass-input').value === "1234") {
            localStorage.setItem('isLogged', 'true');
            location.reload();
        } else { alert("رمز اشتباه!"); }
    }
    function logout() { localStorage.removeItem('isLogged'); location.reload(); }
</script>
</body>
</html>
EOF

# فایل‌های کمکی PWA
cat <<EOF > /root/web_panel/manifest.json
{
  "short_name": "GOST-$DEST_COUNTRY",
  "name": "GOST PRO - $DEST_COUNTRY",
  "start_url": "https://gost.plusne.ir:2053/",
  "display": "standalone",
  "background_color": "#000000",
  "theme_color": "#000000"
}
EOF
touch /root/web_panel/sw.js

# ==========================================
# ۸. سیستم مدیریت حجم و .bashrc
# ==========================================
cat <<EOF > /usr/local/bin/addgig
#!/bin/bash
EXTRA_FILE="\$HOME/.extra_traffic"
CURRENT_EXTRA=\$( [ -f "\$EXTRA_FILE" ] && cat "\$EXTRA_FILE" || echo 0 )
NEW_EXTRA=\$(echo "\$CURRENT_EXTRA + \$1" | bc)
echo "\$NEW_EXTRA" > "\$EXTRA_FILE"
echo "✅ ترافیک با موفقیت اضافه شد."
EOF
chmod +x /usr/local/bin/addgig

cat <<EOF >> ~/.bashrc
BASE_LIMIT=$TRAFFIC_LIMIT
EXPIRY_DATE="$EXP_DATE"
EXTRA_FILE="\$HOME/.extra_traffic"
EXTRA=\$( [ -f "\$EXTRA_FILE" ] && cat "\$EXTRA_FILE" || echo 0 )
TOTAL_LIMIT=\$(echo "\$BASE_LIMIT + \$EXTRA" | bc)
if [ "\$(date +%Y-%m-%d)" == "\$EXPIRY_DATE" ]; then
    vnstat --create -i \$(ip -o -4 route show to default | awk '{print \$5}') --force > /dev/null 2>&1
    rm -f "\$EXTRA_FILE"
fi
USED_RAW=\$(vnstat -m | grep \$(date +%Y-%m) | awk '{print \$8}')
UNIT=\$(vnstat -m | grep \$(date +%Y-%m) | awk '{print \$9}')
if [ "\$UNIT" == "MiB" ]; then USED_GB=\$(echo "scale=2; \$USED_RAW / 1024" | bc); else USED_GB=\$USED_RAW; fi
REMAINING_GB=\$(echo "scale=2; \$TOTAL_LIMIT - \$USED_GB" | bc)
echo -e "\033[1;36m🌍 $DEST_COUNTRY | 🔋 Remaining: \$REMAINING_GB GB / \$TOTAL_LIMIT GB\033[0m"
alias addgig='/usr/local/bin/addgig'
alias hajm='source ~/.bashrc'
alias menu='bash /root/panel.sh'
EOF

# ==========================================
# ۹. ساخت سرویس‌های سیستمی
# ==========================================
cat <<EOF > /etc/systemd/system/gost.service
[Unit]
Description=Gost Proxy
[Service]
ExecStart=/usr/local/bin/gost -C /usr/local/etc/gost.yaml
Restart=always
RuntimeMaxSec=3600
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/gost-ui.service
[Unit]
Description=GOST Panel SSL
[Service]
ExecStart=/usr/local/bin/ttyd -p 2053 -c plus98:09132700649Aa@@ -W --ssl --ssl-cert /etc/letsencrypt/live/gost.plusne.ir/fullchain.pem --ssl-key /etc/letsencrypt/live/gost.plusne.ir/privkey.pem -t theme='{"background": "#000000"}' bash /root/panel.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/adguard-monitor.service
[Unit]
Description=AdGuard Monitor
[Service]
ExecStart=/usr/local/bin/adguard-monitor.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# بهینه‌سازی لاگ‌ها
sed -i 's/#SystemMaxUse=/SystemMaxUse=800M/g' /etc/systemd/journald.conf
systemctl restart systemd-journald

# اجرای نهایی
systemctl daemon-reload
systemctl enable --now gost gost-ui adguard-monitor
clear
echo -e "\e[1;32m✅ تبریک! سیستم با موفقیت نصب شد.\e[0m"
echo -e "\e[1;33m🔗 آدرس پنل: https://gost.plusne.ir:2053\e[0m"
