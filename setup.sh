#!/bin/bash

# ==========================================
# ۱. دریافت اطلاعات اولیه
# ==========================================
clear
echo -e "\033[1;35m====================================================\033[0m"
echo -e "\033[1;33m       UNIVERSAL PRO SETUP BY SADEGH (2026)         \033[0m"
echo -e "\033[1;35m====================================================\033[0m"

read -p "🌍 نام کشور مقصد: " DEST_COUNTRY
read -p "🎯 آی‌پی سرور مقصد: " DEST_IP
read -p "📅 تاریخ انقضا (YYYY-MM-DD): " EXP_DATE
read -p "💾 سقف ترافیک ماهانه (GB): " TRAFFIC_LIMIT

DEST_COUNTRY=${DEST_COUNTRY:-"Destination"}
DEST_IP=${DEST_IP:-"1.1.1.1"}
EXP_DATE=${EXP_DATE:-"2026-03-10"}
TRAFFIC_LIMIT=${TRAFFIC_LIMIT:-"100"}

# ==========================================
# ۲. نصب ابزارها و تنظیمات هسته (BBR & Forwarding)
# ==========================================
apt update && apt install -y wget tar ipset iptables-persistent curl nethogs iftop bc vnstat certbot nano
systemctl enable --now vnstat

modprobe tcp_bbr
cat <<EOF > /etc/sysctl.d/99-gost.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.ip_forward=1
net.ipv4.conf.all.route_localnet=1
net.ipv4.conf.default.route_localnet=1
EOF
sysctl -p /etc/sysctl.d/99-gost.conf

# ==========================================
# ۳. تنظیمات SSL (Certbot)
# ==========================================
echo -ne "\n\033[1;33mآیا مایل به دریافت SSL برای gost.plusne.ir هستید؟ (y/n): \033[0m"
read -r INSTALL_SSL
if [[ "$INSTALL_SSL" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    systemctl stop gost-ui gost 2>/dev/null
    certbot certonly --standalone -d gost.plusne.ir --preferred-challenges http --agree-tos --register-unsafely-without-email
fi

# ==========================================
# ۴. امنیت و رول‌های Iptables (Mangle & Honeypot)
# ==========================================
ipset create allowed_users hash:ip timeout 3600 counters 2>/dev/null
ipset create blacklist hash:ip 2>/dev/null

iptables -F && iptables -t nat -F && iptables -t mangle -F
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -m set --match-set blacklist src -j DROP
iptables -A INPUT -p tcp --dport 2222 -j SET --add-set blacklist src
iptables -A INPUT -p tcp -m multiport --dports 80,443,2053 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT

# رول‌های Mangle برای شمارش دقیق
iptables -t mangle -A PREROUTING -m set --match-set allowed_users src
iptables -t mangle -A POSTROUTING -m set --match-set allowed_users dst
iptables -t mangle -A PREROUTING -p tcp -m multiport --dports 80,443
iptables -t mangle -A PREROUTING -p udp --dport 10000

# انتقال ترافیک به GOST (NAT)
iptables -t nat -A PREROUTING -p tcp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:443
iptables -t nat -A PREROUTING -p udp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:10000
iptables -t nat -A PREROUTING -p tcp --dport 80 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:80
iptables -t nat -A POSTROUTING -j MASQUERADE

netfilter-persistent save
ipset save > /etc/ipset.conf

# ==========================================
# ۵. نصب Gost و ttyd و AdGuard
# ==========================================
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
wget -q https://github.com/go-gost/gost/releases/download/v3.0.0-rc10/gost_3.0.0-rc10_linux_amd64.tar.gz && tar xvf gost_3.0.0-rc10_linux_amd64.tar.gz && mv gost /usr/local/bin/gost && rm gost_3.0.0-rc10_linux_amd64.tar.gz
wget -q https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64 && mv ttyd.x86_64 /usr/local/bin/ttyd && chmod +x /usr/local/bin/ttyd

# ==========================================
# ۶. ساخت وب‌پنل PWA (index.html)
# ==========================================
mkdir -p /root/web_panel
cat <<EOF > /root/web_panel/index.html
<!DOCTYPE html>
<html lang="fa">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="manifest" href="manifest.json">
    <title>GOST PRO - $DEST_COUNTRY</title>
    <style>
        body { background: #000; color: #00ff41; font-family: sans-serif; margin: 0; }
        header { height: 50px; border-bottom: 1px solid #1a1a1a; display: flex; align-items: center; justify-content: space-between; padding: 0 15px; }
        #login-screen { position: fixed; inset: 0; background: #000; display: flex; flex-direction: column; align-items: center; justify-content: center; z-index: 100; }
        iframe { width: 100%; height: calc(100vh - 50px); border: none; }
        input { background: #111; border: 1px solid #00ff41; color: #00ff41; padding: 10px; border-radius: 5px; text-align: center; }
        button { background: #00ff41; color: #000; border: none; padding: 10px 20px; border-radius: 5px; margin-top: 10px; cursor: pointer; }
    </style>
</head>
<body>
    <div id="login-screen">
        <h3>GOST SECURITY</h3>
        <input type="password" id="pass-input" placeholder="PASSWORD">
        <button onclick="checkPass()">LOGIN</button>
    </div>
    <div id="app" style="display:none;">
        <header><div>● GOST PRO ($DEST_COUNTRY)</div><button onclick="logout()" style="margin:0; padding:5px 10px;">EXIT</button></header>
        <iframe src="https://gost.plusne.ir:2053"></iframe>
    </div>
    <script>
        if(localStorage.getItem('isLogged')==='true'){ document.getElementById('login-screen').style.display='none'; document.getElementById('app').style.display='block'; }
        function checkPass(){ if(document.getElementById('pass-input').value==='1234'){ localStorage.setItem('isLogged','true'); location.reload(); } else { alert('Wrong!'); } }
        function logout(){ localStorage.removeItem('isLogged'); location.reload(); }
    </script>
</body>
</html>
EOF

cat <<EOF > /root/web_panel/manifest.json
{ "short_name": "GOST PRO", "name": "GOST PRO $DEST_COUNTRY", "display": "standalone", "start_url": "/", "theme_color": "#000000", "background_color": "#000000" }
EOF

# ==========================================
# ۷. سیستم مدیریت ترافیک و فایل panel.sh
# ==========================================
cat <<'EOF' > /root/panel.sh
#!/bin/bash
while true; do
    clear
    source ~/.bashrc
    echo -e "\033[1;35m====================================================\033[0m"
    echo -e "\033[1;33m       🚀 GOST MANAGEMENT PANEL (2026) 🚀          \033[0m"
    echo -e "\033[1;35m====================================================\033[0m"
    echo -e "1) 📊 Traffic Status  2) ➕ Add Extra GB  3) 🚫 Blacklist"
    echo -e "4) 🔄 Restart All     5) 📝 Gost Logs     6) 🛠️ Edit YAML  0) Exit"
    read -p "Option: " choice
    case $choice in
        1) clear; vnstat -d; read -p "Press Enter...";;
        2) read -p "Enter GB: " gb; addgig $gb; sleep 1;;
        3) clear; ipset list blacklist; read -p "Press Enter...";;
        4) systemctl restart gost gost-ui adguard-monitor; echo "Done"; sleep 1;;
        5) clear; journalctl -u gost -n 50 --no-pager; read -p "Press Enter...";;
        6) nano /usr/local/etc/gost.yaml; systemctl restart gost;;
        0) exit 0;;
    esac
done
EOF
chmod +x /root/panel.sh

cat <<EOF > /usr/local/bin/addgig
#!/bin/bash
EXTRA_FILE="\$HOME/.extra_traffic"
CURRENT_EXTRA=\$( [ -f "\$EXTRA_FILE" ] && cat "\$EXTRA_FILE" || echo 0 )
NEW_EXTRA=\$(echo "\$CURRENT_EXTRA + \$1" | bc)
echo "\$NEW_EXTRA" > "\$EXTRA_FILE"
echo "✅ Added \$1 GB."
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
USED_RAW=\$(vnstat -m | grep \$(date +%Y-%m) | awk '{print \$8}' | head -n 1)
REMAINING_GB=\$(echo "scale=2; \$TOTAL_LIMIT - \$USED_RAW" | bc)
echo -e "\033[1;36m🌍 $DEST_COUNTRY | 🔋 Left: \$REMAINING_GB / \$TOTAL_LIMIT GB\033[0m"
alias addgig='/usr/local/bin/addgig'
alias menu='bash /root/panel.sh'
alias hajm='source ~/.bashrc'
EOF

# ==========================================
# ۸. تنظیمات Gost YAML و سرویس‌ها
# ==========================================
mkdir -p /usr/local/etc/
cat <<EOF > /usr/local/etc/gost.yaml
services:
  - { name: s443, addr: "127.0.0.1:443", handler: {type: tcp}, listener: {type: tcp}, forwarder: {nodes: [{name: dest, addr: "$DEST_IP:8443", connector: {type: relay}, transporter: {type: tcp}}]}}
  - { name: s80, addr: "127.0.0.1:80", handler: {type: tcp}, listener: {type: tcp}, forwarder: {nodes: [{name: dest, addr: "$DEST_IP:8443", connector: {type: relay}, transporter: {type: tcp}}]}}
  - { name: sudp, addr: "127.0.0.1:10000", handler: {type: udp}, listener: {type: udp}, forwarder: {nodes: [{name: dest, addr: "$DEST_IP:8443", connector: {type: relay}, transporter: {type: tcp}}]}}
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

cat <<'EOF' > /usr/local/bin/adguard-monitor.sh
#!/bin/bash
ipset create allowed_users hash:ip timeout 3600 --exist
journalctl -u AdGuardHome -f -n 0 | while read -r LINE; do
    if [[ "$LINE" == *"client ip for stats"* ]]; then
        CLIENT_IP=$(echo "$LINE" | grep -oP 'ip=\K[0-9.]+')
        [ ! -z "$CLIENT_IP" ] && ipset add allowed_users "$CLIENT_IP" -exist
    fi
done
EOF
chmod +x /usr/local/bin/adguard-monitor.sh

cat <<EOF > /etc/systemd/system/adguard-monitor.service
[Unit]
Description=AdGuard Monitor
[Service]
ExecStart=/usr/local/bin/adguard-monitor.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now gost gost-ui adguard-monitor
clear
echo -e "\033[1;32m✅ نصب کامل شد! آدرس پنل PWA شما: https://gost.plusne.ir:2053\033[0m"
