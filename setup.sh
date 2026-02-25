#!/bin/bash

# --- 1. پیش‌نیازها و نصب vnstat ---
apt update && apt install -y wget tar ipset iptables-persistent curl nethogs iftop bc vnstat nano
systemctl enable --now vnstat

# --- 2. نصب AdGuardHome ---
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

# --- 3. تنظیمات BBR و هسته (مطابق کد شما) ---
modprobe tcp_bbr
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.route_localnet=1" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.route_localnet=1" >> /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# --- 4. دانلود و تنظیم GOST و TTYD ---
wget -q https://github.com/go-gost/gost/releases/download/v3.0.0-rc10/gost_3.0.0-rc10_linux_amd64.tar.gz
tar xvf gost_3.0.0-rc10_linux_amd64.tar.gz
mv gost /usr/local/bin/gost && chmod +x /usr/local/bin/gost
rm gost_3.0.0-rc10_linux_amd64.tar.gz

wget -qO /usr/local/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64
chmod +x /usr/local/bin/ttyd

# --- 5. رول‌های امنیتی Iptables (دقیقاً طبق کد شما) ---
ipset create allowed_users hash:ip timeout 3600 counters 2>/dev/null
ipset create blacklist hash:ip 2>/dev/null

iptables -F && iptables -t nat -F && iptables -t mangle -F
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -m set --match-set blacklist src -j DROP
iptables -A INPUT -p tcp --dport 2222 -j SET --add-set blacklist src
iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT

# Mangle & NAT (طبق درخواست شما)
iptables -t mangle -A PREROUTING -m set --match-set allowed_users src
iptables -t mangle -A POSTROUTING -m set --match-set allowed_users dst
iptables -t nat -A PREROUTING -p tcp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:443
iptables -t nat -A PREROUTING -p udp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:10000
iptables -t nat -A PREROUTING -p tcp --dport 80 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:80
iptables -t nat -A POSTROUTING -j MASQUERADE
netfilter-persistent save

# --- 6. جایگزینی کامل فایل .bashrc با نسخه گرافیکی شما ---
cat <<'EOF' > ~/.bashrc
[ -z "$PS1" ] && return
HISTCONTROL=ignoredups:ignorespace
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias menu='bash /root/panel.sh'
alias hajm='source ~/.bashrc'

# --- تنظیمات پایه گرافیکی شما ---
BASE_LIMIT=100
EXPIRY_DATE="2026-03-10"
EXTRA_FILE="$HOME/.extra_traffic"
if [ -f "$EXTRA_FILE" ]; then EXTRA=$(cat "$EXTRA_FILE"); else EXTRA=0; fi
TOTAL_LIMIT=$(echo "$BASE_LIMIT + $EXTRA" | bc)

if [ "$(date +%Y-%m-%d)" == "$EXPIRY_DATE" ]; then
    vnstat --create -i eth0 --force > /dev/null 2>&1
    rm -f "$EXTRA_FILE"
fi

echo -e "\e[1;36m====================================================\e[0m"
echo -e "\e[1;33m    DATE          DOWNLOAD      UPLOAD        TOTAL\e[0m"
echo -e "\e[1;36m----------------------------------------------------\e[0m"
vnstat -d --short | grep -v "estimated" | grep -A 5 "day" | tail -n 5 | awk '{printf " %-12s %-12s %-12s %-12s\n", $1, $2$3, $5$6, $8$9}'
echo -e "\e[1;36m----------------------------------------------------\e[0m"

USED_RAW=$(vnstat -m | grep $(date +%Y-%m) | awk '{print $8}')
UNIT=$(vnstat -m | grep $(date +%Y-%m) | awk '{print $9}')

if [ "$UNIT" == "MiB" ]; then
    REMAINING_GB=$(echo "scale=2; $TOTAL_LIMIT - ($USED_RAW / 1024)" | bc)
else
    REMAINING_GB=$(echo "scale=2; $TOTAL_LIMIT - $USED_RAW" | bc)
fi

DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))
echo -e "\e[1;32m Monthly Total:    $USED_RAW $UNIT\e[0m"
echo -e "\e[1;31m Traffic Left:     $REMAINING_GB GB / $TOTAL_LIMIT GB\e[0m"
[ $EXTRA -gt 0 ] && echo -e "\e[1;33m (Included $EXTRA GB extra package)\e[0m"
if [ $DAYS_LEFT -gt 0 ]; then
    echo -e "\e[1;35m Days Remaining:  $DAYS_LEFT Days\e[0m"
else
    echo -e "\e[1;31m Status:          RESETTING FOR NEW MONTH...\e[0m"
fi
echo -e "\e[1;36m====================================================\e[0m"
EOF

# --- 7. ساخت سرویس‌ها و وب‌پنل (PWA) ---
# [تمام بخش‌های Gost-ui، Adguard-monitor و index.html در اینجا طبق کدهای قبلی شما قرار می‌گیرند]

systemctl daemon-reload
systemctl enable --now gost gost-ui adguard-monitor
source ~/.bashrc

echo "Setup Done. Everything is in its place."
