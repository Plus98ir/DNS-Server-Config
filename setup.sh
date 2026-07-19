#!/bin/bash
# ==========================================
# Automated Server Setup Script
# X-UI Sanaei, AdGuard Home, IPSet, BBR
# ==========================================

# توقف اسکریپت در صورت بروز خطای بحرانی
set -e

echo -e "\e[1;36m[1/6] Updating system and installing dependencies...\e[0m"
# apt-get به صورت هوشمند اگر برنامه‌ای نصب باشد آن را نادیده می‌گیرد
apt-get update -y
apt-get install -y curl wget nano iptables vnstat ipset bc nethogs iftop jq figlet

echo -e "\e[1;36m[2/6] Configuring BBR and sysctl...\e[0m"
if ! grep -q "net.ipv4.tcp_congestion_control = bbr" /etc/sysctl.d/99-custom-bbr.conf 2>/dev/null; then
    cat << 'EOF' > /etc/sysctl.d/99-custom-bbr.conf
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.eth0.route_localnet = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p /etc/sysctl.d/99-custom-bbr.conf
    echo -e "\e[1;32mBBR applied.\e[0m"
else
    echo -e "\e[1;32mBBR is already configured. Skipping...\e[0m"
fi

echo -e "\e[1;36m[3/6] Checking X-UI Sanaei...\e[0m"
if ! command -v x-ui &> /dev/null; then
    echo "Installing X-UI..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
else
    echo -e "\e[1;32mX-UI is already installed. Skipping...\e[0m"
fi

echo -e "\e[1;36m[4/6] Checking AdGuard Home...\e[0m"
if [ ! -d "/opt/AdGuardHome" ] && ! command -v AdGuardHome &> /dev/null; then
    echo "Installing AdGuard Home..."
    curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
else
    echo -e "\e[1;32mAdGuard Home is already installed. Skipping...\e[0m"
fi

echo -e "\e[1;36m[5/6] Injecting Custom Scripts (Updating existing ones)...\e[0m"

# ---------------------------------------------------------
# 1. Restore Rules Script
# ---------------------------------------------------------
cat << 'EOF' > /root/restore_rules.sh
#!/bin/bash

# ۱. پاکسازی کامل قوانین برای آزاد کردن IPSetها
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING
iptables -t nat -X ts-postrouting 2>/dev/null

# پاکسازی جدول mangle برای جلوگیری از تکرار رول‌های شمارش ترافیک
iptables -t mangle -F PREROUTING

# ۲. حذف IPSetها (تا بتوانیم با تنظیمات جدید counters بسازیم)
ipset destroy allowed_users 2>/dev/null
ipset destroy blacklist 2>/dev/null

# ۳. ساخت مجدد با قابلیت شمارش (counters)
ipset create allowed_users hash:ip timeout 3600 counters
ipset create blacklist hash:ip hashsize 4096 maxelem 65536 counters

# ۴. اعمال مجدد قوانین NAT
iptables -t nat -N ts-postrouting
iptables -t nat -I PREROUTING 1 -d 109.70.76.135 -j RETURN
iptables -t nat -A PREROUTING -p tcp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:443
iptables -t nat -A PREROUTING -p tcp --dport 80 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:80
iptables -t nat -A PREROUTING -p udp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:443
iptables -t nat -A POSTROUTING -j ts-postrouting

# ۵. اعمال قوانین Mangle برای شمارش دقیق ترافیک در پنل
iptables -t mangle -A PREROUTING -p udp --dport 443
iptables -t mangle -A PREROUTING -p tcp --dport 443
iptables -t mangle -A PREROUTING -p tcp --dport 80
iptables -t mangle -A PREROUTING -m set --match-set allowed_users src
EOF
chmod +x /root/restore_rules.sh

# افزودن به crontab
(crontab -l 2>/dev/null | grep -v "/root/restore_rules.sh"; echo "@reboot /root/restore_rules.sh") | crontab -

# ---------------------------------------------------------
# 2. AdGuard Monitor Service & Script
# ---------------------------------------------------------
cat << 'EOF' > /etc/systemd/system/adguard-monitor.service
[Unit]
Description=AdGuard IPset Monitor
After=AdGuardHome.service

[Service]
Type=simple
ExecStart=/usr/local/bin/adguard-monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /usr/local/bin/adguard-monitor.sh
#!/bin/bash
SET_NAME="allowed_users"
ipset create $SET_NAME hash:ip timeout 3600 -exist

LAST_IP=""
LAST_REFRESH=0
THRESHOLD=300

journalctl -u AdGuardHome -f -n 0 | while read -r LINE
do
    if [[ "$LINE" == *"client ip for stats"* ]]; then
        CLIENT_IP=$(echo "$LINE" | grep -oP 'ip=\K[0-9.]+')
        CURRENT_TIME=$(date +%s)

        if [ ! -z "$CLIENT_IP" ] && [ "$CLIENT_IP" != "127.0.0.1" ]; then
            if [ "$CLIENT_IP" != "$LAST_IP" ] || [ $((CURRENT_TIME - LAST_REFRESH)) -gt $THRESHOLD ]; then
                ipset add $SET_NAME "$CLIENT_IP" timeout 3600 -exist
                echo "$(date): [UPDATE] Processed IP: $CLIENT_IP"
                LAST_IP="$CLIENT_IP"
                LAST_REFRESH=$CURRENT_TIME
            fi
        fi
    fi
done
EOF
chmod +x /usr/local/bin/adguard-monitor.sh

# ---------------------------------------------------------
# 3. Traffic Monitor Script
# ---------------------------------------------------------
cat << 'EOF' > /root/traffic.sh
#!/bin/bash
# --- فایل تنظیمات ---
SETTINGS_FILE="$HOME/.traffic_settings"
EXTRA_FILE="$HOME/.extra_traffic"
# --- تنظیمات پایه ---
BASE_LIMIT=100   # سقف پایه به GB
EXPIRY_DATE="2026-07-10"

# بارگذاری تنظیمات
if [ -f "$SETTINGS_FILE" ]; then
    source "$SETTINGS_FILE"
else
    EXTRA_GB=0
    OFFSET=0
fi
if [ -f "$EXTRA_FILE" ]; then
    EXTRA=$(cat "$EXTRA_FILE")
else
    EXTRA=0
fi

EXTRA_GB=${EXTRA_GB:-0}
OFFSET=${OFFSET:-0}
BASE_LIMIT=${BASE_LIMIT:-200}
EXTRA=${EXTRA:-0}

# محاسبه سقف نهایی
TOTAL_LIMIT=$(echo "scale=2; $BASE_LIMIT + $EXTRA_GB + $OFFSET" | bc)

# --- بخش ریست ---
if [ "$(date +%Y-%m-%d)" == "$EXPIRY_DATE" ]; then
    vnstat --create -i eth0 --force > /dev/null 2>&1
    rm -f "$EXTRA_FILE"
fi

# --- نمایش جدول مصرف روزانه ---
echo -e "\e[1;36m====================================================\e[0m"
echo -e "\e[1;33m   DATE         DOWNLOAD     UPLOAD       TOTAL\e[0m"
echo -e "\e[1;36m----------------------------------------------------\e[0m"
vnstat -d --short | grep -v "estimated" | grep -A 5 "day" | tail -n 5 | \
awk '{printf " %-12s %-12s %-12s %-12s\n", $1, $2$3, $5$6, $8$9}'
echo -e "\e[1;36m----------------------------------------------------\e[0m"

# --- استخراج مصرف دانلود (RX) ماه جاری ---
MONTH_DATA=$(vnstat -m | grep "$(date +%Y-%m)")
USED_RAW=$(echo "$MONTH_DATA" | awk '{print $2}')
UNIT=$(echo "$MONTH_DATA" | awk '{print $3}' | tr -d '[:space:]')

# تبدیل به گیگابایت برای محاسبه دقیق
if [ "$UNIT" == "MiB" ]; then
    USED_GB=$(echo "scale=2; $USED_RAW / 1024" | bc)
elif [ "$UNIT" == "KiB" ]; then
    USED_GB=$(echo "scale=2; $USED_RAW / 1024 / 1024" | bc)
else
    USED_GB=$USED_RAW
fi
USED_GB=${USED_GB:-0}

# محاسبه باقی‌مانده (فقط بر اساس دانلود)
REMAINING_GB=$(echo "scale=2; $TOTAL_LIMIT - $USED_GB" | bc)

# --- محاسبه روزهای باقی‌مانده ---
DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))

# --- نمایش اطلاعات ---
echo -e "\e[1;32m Monthly Download: $USED_GB GB\e[0m"
echo -e "\e[1;31m Traffic Left:     $REMAINING_GB GB / $TOTAL_LIMIT GB\e[0m"

if (( $(echo "$EXTRA_GB != 0" | bc -l) )); then
    echo -e "\e[1;33m (Included $EXTRA_GB GB extra package)\e[0m"
fi
if [ $DAYS_LEFT -gt 0 ]; then
    echo -e "\e[1;35m Days Remaining:   $DAYS_LEFT Days\e[0m"
else
    echo -e "\e[1;31m Status:           RESETTING FOR NEW MONTH...\e[0m"
fi
echo -e "\e[1;36m====================================================\e[0m"

# --- منوی تعاملی ---
echo -e "\e[1;33m[1] Add/Reduce GB  [2] Set Expiry Date  [3] Reset Extra
[4] Sync Offset  [Enter] Exit\e[0m"
read -p "Select option: " opt
save_settings() {
    echo "EXTRA_GB=$EXTRA_GB" > "$SETTINGS_FILE"
    echo "EXPIRY_DATE=\"$EXPIRY_DATE\"" >> "$SETTINGS_FILE"
    echo "OFFSET=$OFFSET" >> "$SETTINGS_FILE"
}
case "$opt" in
    1) read -p "Enter GB to add/reduce: " new_gb
       EXTRA_GB=$new_gb
       save_settings
       exec bash ;;
    2) read -p "New Expiry Date (YYYY-MM-DD): " new_date
       EXPIRY_DATE="$new_date"
       save_settings
       exec bash ;;
    3) EXTRA_GB=0
       OFFSET=0
       save_settings
       exec bash ;;
    4) read -p "Current Offset is $OFFSET. Enter adjustment: " adjust
       OFFSET=$(echo "scale=2; $OFFSET + $adjust" | bc)
       save_settings
       exec bash ;;
esac
EOF
chmod +x /root/traffic.sh

# ---------------------------------------------------------
# 4. Display Script
# ---------------------------------------------------------
cat << 'EOF' > /root/display.sh
#!/bin/bash
[ -f "$HOME/.traffic_settings" ] && source "$HOME/.traffic_settings"
[ -f "$HOME/.extra_traffic" ] && EXTRA=$(cat "$HOME/.extra_traffic")

MONTH_DATA=$(vnstat -m | grep "$(date +%Y-%m)")
USED_RAW=$(echo "$MONTH_DATA" | awk '{print $2}')
UNIT=$(echo "$MONTH_DATA" | awk '{print $3}' | tr -d '[:space:]')

if [ "$UNIT" == "MiB" ]; then USED_GB=$(echo "scale=2; $USED_RAW / 1024" | bc)
elif [ "$UNIT" == "KiB" ]; then USED_GB=$(echo "scale=2; $USED_RAW / 1024 / 1024" | bc)
else USED_GB=$USED_RAW
fi

BASE_LIMIT=100
EXTRA_GB=${EXTRA_GB:-0}
OFFSET=${OFFSET:-0}
TOTAL_LIMIT=$(echo "scale=2; $BASE_LIMIT + $EXTRA_GB + $OFFSET" | bc)
REMAINING_GB=$(echo "scale=2; $TOTAL_LIMIT - $USED_GB" | bc)
EXPIRY_DATE=${EXPIRY_DATE:-"2026-07-10"}
DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))

clear
echo -e "\e[1;36m"
figlet -f slant "TRAFFIC"
echo -e "\e[0m"

echo -e "\e[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e "\e[1;32m  TRAFFIC LEFT:   \e[1;33m$REMAINING_GB GB \e[1;37m/ $TOTAL_LIMIT GB\e[0m"
echo -e "\e[1;37m----------------------------------------------------\e[0m"
echo -e "\e[1;32m  DAYS LEFT:      \e[1;36m$DAYS_LEFT Days\e[0m"
echo -e "\e[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
EOF
chmod +x /root/display.sh

# ---------------------------------------------------------
# 5. Panel Menu Script
# ---------------------------------------------------------
cat << 'EOF' > /root/panel.sh
#!/bin/bash
export TERM=xterm-256color
RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
BLUE='[0;34m'
PURPLE='[0;35m'
CYAN='[0;36m'
NC='[0m'
show_menu() {
    clear
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${CYAN}        SERVER USAGE PANEL - IRAN          ${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo -e "1) ${GREEN}Active Users Report${NC} (Traffic + ISP + Timeout)"
    echo -e "2) ${GREEN}Add New IP${NC} manually"
    echo -e "3) ${RED}Remove IP${NC} manually"
    echo -e "4) ${YELLOW}Live Packet Monitor${NC}"
    echo -e "5) ${YELLOW}Real-time Bandwidth${NC} (iftop)"
    echo -e "6) ${PURPLE}View IP's Log${NC}"
    echo -e "7) ${BLUE}Restart Services${NC}"
    echo -e "8) ${BLUE}Save & Persist All Rules${NC}"
    echo -e "9) ${RED}Manage Blacklist${NC}"
    echo -e "10) ${CYAN}Process Traffic Monitor${NC} (nethogs)"
    echo -e "11) Exit"
    echo -e "${BLUE}----------------------------------------------${NC}"
    echo -n "Select an option [1-11]: "
}
while true; do
    show_menu
    read opt
    case $opt in
        1)
            echo -e "
${CYAN}Generating Full Traffic Report...${NC}"
            echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
            printf "%-18s | %-12s | %-10s | %-20s
" "Source/Service" "Traffic" "Status" "Description"
            echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
            for item in "80:tcp" "443:tcp" "443:udp"; do
                port=$(echo $item | cut -d: -f1)
                proto=$(echo $item | cut -d: -f2)
                raw_p=$(iptables -t mangle -L -n -v -x | grep -i "$proto" | grep -E "dpt:$port|spt:$port" | awk '{sum+=$2} END {print sum}')
                [ -z "$raw_p" ] || [ "$raw_p" == "0" ] && raw_p=0
                if [ "$raw_p" -lt 1048576 ]; then
                    p_traffic="$(($raw_p / 1024)) KB"
                elif [ "$raw_p" -lt 1073741824 ]; then
                    p_traffic="$(($raw_p / 1048576)) MB"
                else
                    p_traffic="$(awk "BEGIN {printf "%.2f", $raw_p/1073741824}") GB"
                fi
                if [ "$port" == "80" ]; then
                    p_name="PORT:80"
                else
                    p_name="PORT:443 ($(echo $proto | tr '[:lower:]' '[:upper:]'))"
                fi
                printf "${YELLOW}%-18s${NC} | ${GREEN}%-12s${NC} | ${CYAN}%-10s${NC} | ${PURPLE}%-20s${NC}
" "$p_name" "$p_traffic" "GLOBAL" "Total Usage"
            done
            echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
            ipset_data=$(ipset list allowed_users 2>/dev/null | sed -n '/Members:/,$p' | tail -n +2)
            if [ -n "$ipset_data" ]; then
                while read -r line; do
                    [ -z "$line" ] && continue
                    ip=$(echo $line | awk '{print $1}')
                    timeout=$(echo $line | awk '{print $3}')
                    bytes=$(echo $line | grep -oP 'bytes \K[0-9]+')
                    [ -z "$bytes" ] && bytes=0
                    if [ "$bytes" -lt 1048576 ]; then u_traffic="$(($bytes / 1024)) KB";
                    elif [ "$bytes" -lt 1073741824 ]; then u_traffic="$(($bytes / 1048576)) MB";
                    else u_traffic="$(awk "BEGIN {printf "%.2f", $bytes/1073741824}") GB"; fi
                    isp=$(curl -s --connect-timeout 2 "http://ip-api.com/line/$ip?fields=isp" | head -n 1)
                    [[ -z "$isp" || "$isp" == *"{"* ]] && isp="Unknown" || isp=$(echo "$isp" | cut -c1-20)
                    printf "${GREEN}%-18s${NC} | ${BLUE}%-12s${NC} | ${YELLOW}%-10s${NC} | ${PURPLE}%-20s${NC}
" "$ip" "$u_traffic" "${timeout}s" "$isp"
                done <<< "$ipset_data"
            else
                echo -e "${RED}             No active users in ipset list.                     ${NC}"
            fi
            echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
            read -p "Press Enter to return..."
            ;;
        2)
            echo -n "Enter IP: "
            read new_ip
            ipset add allowed_users $new_ip --exist
            echo -e "${GREEN}IP $new_ip added.${NC}"
            sleep 1
            ;;
        3)
            echo -n "Enter IP to remove: "
            read del_ip
            ipset del allowed_users $del_ip
            echo -e "${RED}IP $del_ip removed.${NC}"
            sleep 1
            ;;
        4)
            iptables -t nat -L PREROUTING -n -v --line-numbers
            read -p "Press Enter..."
            ;;
        5)
            iftop -nNP -i any
            ;;
        6)
            journalctl -u adguard-monitor.service -n 50 --no-pager
            read -p "Press Enter..."
            ;;
        7)
            systemctl restart gost
            echo -e "${GREEN}Restarted.${NC}"
            sleep 1
            ;;
        8)
            netfilter-persistent save
            ipset save > /etc/ipset.conf
            echo -e "${GREEN}All rules and IPSets saved permanently.${NC}"
            sleep 1
            ;;
        9)
            echo -e "${RED}=== BLACKLISTED ATTACKERS ===${NC}"
            count=$(ipset list blacklist 2>/dev/null | grep "Number of entries" | cut -d: -f2 | xargs)
            if [ -z "$count" ] || [ "$count" == "0" ]; then
                echo -e "${YELLOW}Blacklist is currently empty.${NC}"
            else
                echo -e "${YELLOW}Total Blocked IPs: $count${NC}"
                echo -e "${BLUE}----------------------------------------------------------------------${NC}"
                printf "%-18s | %-30s
" "Blocked IP" "ISP/Organization"
                echo -e "${BLUE}----------------------------------------------------------------------${NC}"
                ips=$(ipset list blacklist | sed -n '/Members:/,$p' | tail -n +2)
                while read -r bl_ip; do
                    [ -z "$bl_ip" ] && continue
                    bl_isp=$(curl -s --connect-timeout 2 "http://ip-api.com/line/$bl_ip?fields=isp" | head -n 1)
                    [[ -z "$bl_isp" || "$bl_isp" == *"{"* ]] && bl_isp="Unknown" || bl_isp=$(echo "$bl_isp" | cut -c1-30)
                    printf "${RED}%-18s${NC} | ${PURPLE}%-30s${NC}
" "$bl_ip" "$bl_isp"
                done <<< "$ips"
                echo -e "${BLUE}----------------------------------------------------------------------${NC}"
            fi
            echo "1) Clear Blacklist"
            echo "2) Back to Menu"
            read -p "Select: " bl_opt
            if [ "$bl_opt" == "1" ]; then
                ipset flush blacklist
                echo -e "${GREEN}Blacklist cleared!${NC}"
                sleep 1
            fi
            ;;
        10)
            nethogs
            ;;
        11)
            exit 0
            ;;
        *)
            echo "Invalid Option"
            sleep 1
            ;;
    esac
done
EOF
chmod +x /root/panel.sh

echo -e "\e[1;36m[6/6] Finalizing Setup...\e[0m"

# فعال‌سازی سرویس مانیتور ادگارد
systemctl daemon-reload
systemctl enable adguard-monitor.service
systemctl start adguard-monitor.service

# تنظیم Alias ها و اجرای خودکار در bashrc
if ! grep -q "alias menu='bash /root/panel.sh'" ~/.bashrc; then
    echo "alias menu='bash /root/panel.sh'" >> ~/.bashrc
fi
if ! grep -q "alias hajm='bash /root/traffic.sh'" ~/.bashrc; then
    echo "alias hajm='bash /root/traffic.sh'" >> ~/.bashrc
fi

# اجرای خودکار display.sh هنگام ورود به سرور
if ! grep -q "/root/display.sh" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Auto-display traffic on login" >> ~/.bashrc
    echo "/root/display.sh" >> ~/.bashrc
fi

echo -e "\e[1;32m===================================================================\e[0m"
echo -e "\e[1;32m✅ Installation Completed Successfully!\e[0m"
echo -e "\e[1;32m===================================================================\e[0m"
echo -e "1. Checked X-UI Sanaei and AdGuard Home (Skipped if already installed)."
echo -e "2. Checked and activated BBR."
echo -e "3. All custom scripts (panel, traffic, monitor) are updated and ready."
echo -e "4. Aliases 'menu' and 'hajm' are configured."
echo -e "5. Auto-display on login is enabled."
