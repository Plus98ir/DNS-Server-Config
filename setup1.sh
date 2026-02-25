#!/bin/bash

# ==========================================
# دریافت اطلاعات متغیر از کاربر
# ==========================================
clear
echo -e "\e[1;35m====================================================\e[0m"
echo -e "\e[1;33m          SMART SERVER SETUP BY SADEGH             \e[0m"
echo -e "\e[1;35m====================================================\e[0m"

read -p "🎯 Enter Turkey Server IP: " TURKEY_IP
read -p "📅 Enter Expiry Date (YYYY-MM-DD) [e.g. 2026-03-20]: " EXP_DATE
read -p "💾 Enter Monthly Traffic Limit (GB) [e.g. 100]: " TRAFFIC_LIMIT

# مقادیر پیش‌فرض اگر خالی گذاشتی
TURKEY_IP=${TURKEY_IP:-"185.103.202.35"}
EXP_DATE=${EXP_DATE:-"2026-03-10"}
TRAFFIC_LIMIT=${TRAFFIC_LIMIT:-"100"}

echo -e "\n\e[1;32m✅ Starting Installation with IP: $TURKEY_IP, Limit: $TRAFFIC_LIMIT GB...\e[0m\n"
sleep 2

# ==========================================
# ۱. نصب ابزارها و بهینه‌سازی سیستم
# ==========================================
apt update && apt install -y wget tar ipset iptables-persistent curl nethogs iftop bc vnstat
systemctl enable --now vnstat

modprobe tcp_bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -w net.ipv4.conf.all.route_localnet=1
sysctl -p

# مدیریت لاگ‌ها
sed -i 's/#SystemMaxUse=/SystemMaxUse=800M/g' /etc/systemd/journald.conf
systemctl restart systemd-journald

# ==========================================
# ۲. نصب AdGuardHome و Gost و GoTTY
# ==========================================
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
wget https://github.com/yudai/gotty/releases/download/v1.0.1/gotty_linux_amd64.tar.gz
tar -xvzf gotty_linux_amd64.tar.gz -C /usr/local/bin/ && chmod +x /usr/local/bin/gotty

wget https://github.com/go-gost/gost/releases/download/v3.0.0-rc10/gost_3.0.0-rc10_linux_amd64.tar.gz
tar -xvzf gost_3.0.0-rc10_linux_amd64.tar.gz
mv gost /usr/local/bin/ && chmod +x /usr/local/bin/gost

# ==========================================
# ۳. ساخت فایل‌های کانفیگ با آی‌پی وارد شده
# ==========================================
mkdir -p /usr/local/etc/
cat <<EOF > /usr/local/etc/gost.yaml
services:
  - name: service-443
    addr: "127.0.0.1:443"
    handler: { type: tcp }
    listener: { type: tcp }
    forwarder:
      nodes: &turkey_node
        - name: turkey
          addr: "$TURKEY_IP:8443"
          connector: { type: relay }
          transporter: { type: tcp }
  - name: service-80
    addr: "127.0.0.1:80"
    handler: { type: tcp }
    listener: { type: tcp }
    forwarder: { nodes: *turkey_node }
  - name: service-udp
    addr: "127.0.0.1:10000"
    handler: { type: udp }
    listener: { type: udp }
    forwarder: { nodes: *turkey_node }
log:
  level: info
EOF

# اسکریپت مانیتورینگ AdGuard
cat <<'EOF' > /usr/local/bin/adguard-monitor.sh
#!/bin/bash
SET_NAME="allowed_users"
ipset create $SET_NAME hash:ip timeout 3600 --exist
journalctl -u AdGuardHome -f -n 0 | while read -r LINE; do
    if [[ "$LINE" == *"client ip for stats"* ]]; then
        CLIENT_IP=$(echo "$LINE" | grep -oP 'ip=\K[0-9.]+')
        if [ ! -z "$CLIENT_IP" ] && [ "$CLIENT_IP" != "127.0.0.1" ]; then
            ipset add $SET_NAME "$CLIENT_IP" --exist
        fi
    fi
done
EOF
chmod +x /usr/local/bin/adguard-monitor.sh

# ==========================================
# ۴. تنظیمات IPSet و Iptables
# ==========================================
ipset create allowed_users hash:ip timeout 3600 counters 2>/dev/null
ipset create blacklist hash:ip 2>/dev/null

iptables -F && iptables -t nat -F && iptables -t mangle -F
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -m set --match-set blacklist src -j DROP
iptables -A INPUT -p tcp --dport 2222 -j SET --add-set blacklist src
iptables -A INPUT -p tcp -m multiport --dports 80,443,8090,3000 -j ACCEPT
iptables -I INPUT -m set --match-set allowed_users src -j ACCEPT

# Mangle Counters
iptables -t mangle -A PREROUTING -m set --match-set allowed_users src
iptables -t mangle -A POSTROUTING -m set --match-set allowed_users dst
iptables -t mangle -A PREROUTING -p tcp -m multiport --dports 80,443
iptables -t mangle -A POSTROUTING -p tcp -m multiport --sports 80,443

# NAT Tunnel
iptables -t nat -A PREROUTING -p tcp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:443
iptables -t nat -A PREROUTING -p udp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:10000
iptables -t nat -A PREROUTING -p tcp --dport 80 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:80
iptables -t nat -A POSTROUTING -j MASQUERADE
netfilter-persistent save

# ==========================================
# ۵. ساخت سرویس‌ها و تنظیم .bashrc
# ==========================================
cat <<EOF > /etc/systemd/system/gost.service
[Unit]
Description=Gost Proxy
After=network.target
[Service]
ExecStart=/usr/local/bin/gost -C /usr/local/etc/gost.yaml
Restart=always
RuntimeMaxSec=3600
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/gost-ui.service
[Unit]
Description=GOST Web UI
[Service]
ExecStart=/usr/local/bin/gotty -w -p 8090 -c plus98:09132700649Aa@@ /bin/bash /root/panel.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/adguard-monitor.service
[Unit]
Description=AdGuard IPset Monitor
[Service]
ExecStart=/usr/local/bin/adguard-monitor.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now gost.service gost-ui.service adguard-monitor.service

# تنظیمات داشبورد در .bashrc با مقادیر کاربر
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

echo -e "\e[1;36m====================================================\e[0m"
echo -e "\e[1;33m    DATE           DOWNLOAD     UPLOAD        TOTAL\e[0m"
echo -e "\e[1;36m----------------------------------------------------\e[0m"
vnstat -d --short | grep -v "estimated" | grep -A 5 "day" | tail -n 5 | awk '{printf " %-12s %-12s %-12s %-12s\n", \$1, \$2\$3, \$5\$6, \$8\$9}'
echo -e "\e[1;36m----------------------------------------------------\e[0m"

USED_RAW=\$(vnstat -m | grep \$(date +%Y-%m) | awk '{print \$8}')
UNIT=\$(vnstat -m | grep \$(date +%Y-%m) | awk '{print \$9}')

if [ "\$UNIT" == "MiB" ]; then
    REMAINING_GB=\$(echo "scale=2; \$TOTAL_LIMIT - (\$USED_RAW / 1024)" | bc)
else
    REMAINING_GB=\$(echo "scale=2; \$TOTAL_LIMIT - \$USED_RAW" | bc)
fi

DAYS_LEFT=\$(( (\$(date -d "\$EXPIRY_DATE" +%s) - \$(date +%s)) / 86400 ))
echo -e "\e[1;32m Monthly Total:    \$USED_RAW \$UNIT\e[0m"
echo -e "\e[1;31m Traffic Left:     \$REMAINING_GB GB / \$TOTAL_LIMIT GB\e[0m"
[ \$DAYS_LEFT -gt 0 ] && echo -e "\e[1;35m Days Remaining:   \$DAYS_LEFT Days\e[0m"
echo -e "\e[1;36m====================================================\e[0m"

alias menu='bash /root/panel.sh'
alias hajm='source ~/.bashrc'
EOF

clear
echo -e "\e[1;32m✅ ALL DONE! Server is Ready.\
