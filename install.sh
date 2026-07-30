#!/bin/bash
# ==========================================
# Automated Server Setup Script (Public Version)
# X-UI Sanaei, AdGuard Home, IPSet, BBR, Rules Updater
# ==========================================

# توقف اسکریپت در صورت بروز خطای بحرانی
set -e

# این خط باعث می‌شود اسکریپت هنگام اجرا با curl، حتماً منتظر تایپ کیبورد بماند
exec < /dev/tty

echo -e "\e[1;36m====================================================\e[0m"
echo -e "\e[1;33m  INITIAL CONFIGURATION \e[0m"
echo -e "\e[1;36m====================================================\e[0m"

# دریافت مقادیر از کاربر
read -p "Enter GitHub Raw URL for your rules (Leave blank to skip): " GITHUB_URL

read -p "Enter AdGuard Home Web UI Port (Default 8090): " AGH_PORT
AGH_PORT=${AGH_PORT:-8090}

read -p "Enter AdGuard Home Username (Default plus98): " AGH_USER
AGH_USER=${AGH_USER:-plus98}

read -p "Enter AdGuard Home Password (Default plus98): " AGH_PASS
AGH_PASS=${AGH_PASS:-plus98}

echo -e "\e[1;36m[1/8] Updating system and installing dependencies...\e[0m"
apt-get update -y
apt-get install -y curl wget nano iptables vnstat ipset bc nethogs iftop jq figlet apache2-utils

# تلاش برای استخراج آی‌پی سرور از منابع مختلف
SERVER_IP=$(curl -s4 api.ipify.org || curl -s4 icanhazip.com || curl -s4 ifconfig.me)

# بررسی اینکه آیا مقدار دریافتی واقعاً یک آی‌پی معتبر است (نه صفحه HTML)
if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # تلاش برای دریافت آی‌پی محلی رابط شبکه
    SERVER_IP=$(hostname -I | awk '{print $1}')
fi

# اگر باز هم آی‌پی معتبر نبود، از کاربر بپرسد
if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "\e[1;31mCould not detect Server IP automatically!\e[0m"
    read -p "Please enter your Server IP manually: " SERVER_IP
fi

echo -e "\e[1;32mServer IP detected as: $SERVER_IP\e[0m"
echo ""

echo -e "\e[1;36m[2/8] Configuring BBR and sysctl...\e[0m"
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

echo -e "\e[1;36m[3/8] Checking X-UI Sanaei...\e[0m"
if ! command -v x-ui &> /dev/null; then
    echo "Installing X-UI..."
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
else
    echo -e "\e[1;32mX-UI is already installed. Skipping...\e[0m"
fi

echo -e "\e[1;36m[4/8] Checking & Configuring AdGuard Home...\e[0m"
if [ ! -d "/opt/AdGuardHome" ] && ! command -v AdGuardHome &> /dev/null; then
    echo "Installing AdGuard Home..."
    curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
else
    echo -e "\e[1;32mAdGuard Home is already installed.\e[0m"
fi

echo "Generating AdGuard Home password hash..."
AGH_HASH=$(htpasswd -B -n -b "$AGH_USER" "$AGH_PASS" | cut -d ":" -f 2)

echo "Applying custom AdGuard Home configuration..."
systemctl stop AdGuardHome || true

cat << 'EOF' > /opt/AdGuardHome/AdGuardHome.yaml
http:
  pprof:
    port: 6060
    enabled: false
  doh:
    routes:
      - GET /dns-query
      - POST /dns-query
      - GET /dns-query/{ClientID}
      - POST /dns-query/{ClientID}
    insecure_enabled: false
  address: 0.0.0.0:AGH_PORT_PLACEHOLDER
  session_ttl: 30d
users:
  - name: AGH_USER_PLACEHOLDER
    password: AGH_PASS_PLACEHOLDER
auth_attempts: 5
block_auth_min: 15
http_proxy: ""
language: ""
theme: auto
dns:
  bind_hosts:
    - 0.0.0.0
  port: 53
  anonymize_client_ip: false
  ratelimit: 20
  ratelimit_subnet_len_ipv4: 24
  ratelimit_subnet_len_ipv6: 56
  ratelimit_whitelist: []
  refuse_any: true
  upstream_dns:
    - '#127.0.0.1:5335'
    - 8.8.8.8
    - 1.1.1.1
  upstream_dns_file: ""
  bootstrap_dns:
    - 8.8.8.8
    - 9.9.9.10
    - 149.112.112.10
  fallback_dns: []
  upstream_mode: parallel
  fastest_timeout: 1s
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts:
    - version.bind
    - id.server
    - hostname.bind
  trusted_proxies:
    - 127.0.0.0/8
    - ::1/128
  cache_enabled: true
  cache_size: 4194304
  cache_ttl_min: 3600
  cache_ttl_max: 43200
  cache_optimistic: true
  cache_optimistic_answer_ttl: 30s
  cache_optimistic_max_age: 12h
  bogus_nxdomain: []
  aaaa_disabled: true
  enable_dnssec: false
  edns_client_subnet:
    custom_ip: ""
    enabled: false
    use_custom: false
  max_goroutines: 300
  handle_ddr: true
  ipset: []
  ipset_file: ""
  bootstrap_prefer_ipv6: false
  upstream_timeout: 2s
  private_networks: []
  use_private_ptr_resolvers: false
  local_ptr_upstreams: []
  use_dns64: false
  dns64_prefixes: []
  serve_http3: false
  use_http3_upstreams: false
  serve_plain_dns: true
  hostsfile_enabled: true
  pending_requests:
    enabled: true
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  port_dns_over_quic: 853
  port_dnscrypt: 0
  dnscrypt_config_file: ""
  certificate_chain: ""
  private_key: ""
  certificate_path: ""
  private_key_path: ""
  strict_sni_check: false
querylog:
  dir_path: ""
  ignored: []
  interval: 90d
  size_memory: 1000
  enabled: true
  ignored_enabled: false
  file_enabled: true
statistics:
  dir_path: ""
  ignored: []
  interval: 1d
  enabled: true
  ignored_enabled: false
filters:
  - enabled: true
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt
    name: AdGuard DNS filter
    id: 1
  - enabled: false
    url: https://adguardteam.github.io/HostlistsRegistry/assets/filter_2.txt
    name: AdAway Default Blocklist
    id: 2
  - enabled: true
    url: /opt/AdGuardHome/data/adguard-rewrite.txt
    name: My Rules
    id: 1785316064
whitelist_filters: []
user_rules:
  - ""
dhcp:
  enabled: false
  interface_name: ""
  local_domain_name: lan
  dhcpv4:
    gateway_ip: ""
    subnet_mask: ""
    range_start: ""
    range_end: ""
    lease_duration: 86400
    icmp_timeout_msec: 1000
    options: []
  dhcpv6:
    range_start: ""
    lease_duration: 86400
    ra_slaac_only: false
    ra_allow_slaac: false
filtering:
  blocking_ipv4: ""
  blocking_ipv6: ""
  blocked_services:
    schedule:
      time_zone: Local
    ids: []
  protection_disabled_until: null
  safe_search:
    enabled: false
    bing: true
    duckduckgo: true
    ecosia: true
    google: true
    pixabay: true
    yandex: true
    youtube: true
  blocking_mode: default
  parental_block_host: family-block.dns.adguard.com
  safebrowsing_block_host: standard-block.dns.adguard.com
  rewrites: []
  safe_fs_patterns:
    - /opt/AdGuardHome/data/adguard-rewrite.txt
    - /opt/AdGuardHome/userfilters/*
  max_http_size: 256MB
  safebrowsing_cache_size: 1048576
  safesearch_cache_size: 1048576
  parental_cache_size: 1048576
  cache_time: 30
  filters_update_interval: 24
  blocked_response_ttl: 10
  filtering_enabled: true
  rewrites_enabled: false
  parental_enabled: false
  safebrowsing_enabled: false
  protection_enabled: true
clients:
  runtime_sources:
    whois: true
    arp: true
    rdns: false
    dhcp: true
    hosts: true
  persistent: []
log:
  enabled: true
  file: ""
  max_backups: 0
  max_size: 100
  max_age: 3
  compress: false
  local_time: false
  verbose: true
os:
  group: ""
  user: ""
  rlimit_nofile: 0
schema_version: 34
EOF

sed -i "s/AGH_PORT_PLACEHOLDER/$AGH_PORT/g" /opt/AdGuardHome/AdGuardHome.yaml
sed -i "s/AGH_USER_PLACEHOLDER/$AGH_USER/g" /opt/AdGuardHome/AdGuardHome.yaml
sed -i "s|AGH_PASS_PLACEHOLDER|$AGH_HASH|g" /opt/AdGuardHome/AdGuardHome.yaml

systemctl start AdGuardHome

echo -e "\e[1;36m[5/8] Injecting Custom Scripts (Updating existing ones)...\e[0m"

# ---------------------------------------------------------
# 1. Restore Rules Script
# ---------------------------------------------------------
cat << EOF > /root/restore_rules.sh
#!/bin/bash
iptables -t nat -F PREROUTING
iptables -t nat -F POSTROUTING
iptables -t nat -X ts-postrouting 2>/dev/null
iptables -t mangle -F PREROUTING

ipset destroy allowed_users 2>/dev/null
ipset destroy blacklist 2>/dev/null

ipset create allowed_users hash:ip timeout 3600 counters
ipset create blacklist hash:ip hashsize 4096 maxelem 65536 counters

iptables -t nat -N ts-postrouting
iptables -t nat -I PREROUTING 1 -d $SERVER_IP -j RETURN
iptables -t nat -A PREROUTING -p tcp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:443
iptables -t nat -A PREROUTING -p tcp --dport 80 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:80
iptables -t nat -A PREROUTING -p udp --dport 443 -m set --match-set allowed_users src -j DNAT --to-destination 127.0.0.1:443
iptables -t nat -A POSTROUTING -j ts-postrouting

iptables -t mangle -A PREROUTING -p udp --dport 443
iptables -t mangle -A PREROUTING -p tcp --dport 443
iptables -t mangle -A PREROUTING -p tcp --dport 80
iptables -t mangle -A PREROUTING -m set --match-set allowed_users src
EOF
chmod +x /root/restore_rules.sh
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
SETTINGS_FILE="$HOME/.traffic_settings"
EXTRA_FILE="$HOME/.extra_traffic"
BASE_LIMIT=100
EXPIRY_DATE="2026-07-10"

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

TOTAL_LIMIT=$(echo "scale=2; $BASE_LIMIT + $EXTRA_GB + $OFFSET" | bc)

if [ "$(date +%Y-%m-%d)" == "$EXPIRY_DATE" ]; then
    vnstat --create -i eth0 --force > /dev/null 2>&1
    rm -f "$EXTRA_FILE"
fi

echo -e "\e[1;36m====================================================\e[0m"
echo -e "\e[1;33m   DATE         DOWNLOAD      UPLOAD       TOTAL\e[0m"
echo -e "\e[1;36m----------------------------------------------------\e[0m"
vnstat -d --short | grep -v "estimated" | grep -A 5 "day" | tail -n 5 | \
awk '{printf " %-12s %-12s %-12s %-12s\n", $1, $2$3, $5$6, $8$9}'
echo -e "\e[1;36m----------------------------------------------------\e[0m"

MONTH_DATA=$(vnstat -m | grep "$(date +%Y-%m)")
USED_RAW=$(echo "$MONTH_DATA" | awk '{print $2}')
UNIT=$(echo "$MONTH_DATA" | awk '{print $3}' | tr -d '[:space:]')

if [ "$UNIT" == "MiB" ]; then USED_GB=$(echo "scale=2; $USED_RAW / 1024" | bc)
elif [ "$UNIT" == "KiB" ]; then USED_GB=$(echo "scale=2; $USED_RAW / 1024 / 1024" | bc)
else USED_GB=$USED_RAW
fi
USED_GB=${USED_GB:-0}

REMAINING_GB=$(echo "scale=2; $TOTAL_LIMIT - $USED_GB" | bc)
DAYS_LEFT=$(( ($(date -d "$EXPIRY_DATE" +%s) - $(date +%s)) / 86400 ))

echo -e "\e[1;32m Monthly Download: $USED_GB GB\e[0m"
echo -e "\e[1;31m Traffic Left:     $REMAINING_GB GB of $TOTAL_LIMIT GB\e[0m"

if (( $(echo "$EXTRA_GB != 0" | bc -l) )); then
    echo -e "\e[1;33m (Included $EXTRA_GB GB extra package)\e[0m"
fi
if [ $DAYS_LEFT -gt 0 ]; then
    echo -e "\e[1;35m Days Remaining:   $DAYS_LEFT Days\e[0m"
else
    echo -e "\e[1;31m Status:           RESETTING FOR NEW MONTH...\e[0m"
fi
echo -e "\e[1;36m====================================================\e[0m"

echo -e "\e[1;33m[1] Add/Reduce GB  [2] Set Expiry Date  [3] Reset Extra
[4] Sync Offset  [Enter] Exit\e[0m"
read -p "Select option: " opt < /dev/tty
save_settings() {
    echo "EXTRA_GB=$EXTRA_GB" > "$SETTINGS_FILE"
    echo "EXPIRY_DATE=\"$EXPIRY_DATE\"" >> "$SETTINGS_FILE"
    echo "OFFSET=$OFFSET" >> "$SETTINGS_FILE"
}
case "$opt" in
    1) read -p "Enter GB to add/reduce: " new_gb < /dev/tty; EXTRA_GB=$new_gb; save_settings; exec bash ;;
    2) read -p "New Expiry Date (YYYY-MM-DD): " new_date < /dev/tty; EXPIRY_DATE="$new_date"; save_settings; exec bash ;;
    3) EXTRA_GB=0; OFFSET=0; save_settings; exec bash ;;
    4) read -p "Current Offset is $OFFSET. Enter adjustment: " adjust < /dev/tty; OFFSET=$(echo "scale=2; $OFFSET + $adjust" | bc); save_settings; exec bash ;;
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
echo -e "\e[1;32m  TRAFFIC LEFT:   \e[1;33m$REMAINING_GB GB \e[1;37mof $TOTAL_LIMIT GB\e[0m"
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
RED='\e[0;31m'
GREEN='\e[0;32m'
YELLOW='\e[1;33m'
BLUE='\e[0;34m'
PURPLE='\e[0;35m'
CYAN='\e[0;36m'
NC='\e[0m'
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
        1) echo -e "\n${CYAN}Generating Full Traffic Report...${NC}"
           read -p "Press Enter to return..." ;;
        2) echo -n "Enter IP: "; read new_ip; ipset add allowed_users $new_ip --exist; sleep 1 ;;
        3) echo -n "Enter IP to remove: "; read del_ip; ipset del allowed_users $del_ip; sleep 1 ;;
        4) iptables -t nat -L PREROUTING -n -v --line-numbers; read -p "Press Enter..." ;;
        5) iftop -nNP -i any ;;
        6) journalctl -u adguard-monitor.service -n 50 --no-pager; read -p "Press Enter..." ;;
        7) systemctl restart gost; echo -e "${GREEN}Restarted.${NC}"; sleep 1 ;;
        8) netfilter-persistent save; ipset save > /etc/ipset.conf; sleep 1 ;;
        9) read -p "Press enter..." ;;
        10) nethogs ;;
        11) exit 0 ;;
        *) echo "Invalid Option"; sleep 1 ;;
    esac
done
EOF
chmod +x /root/panel.sh

# ---------------------------------------------------------
# 6. AdGuard GitHub Rules Updater Script
# ---------------------------------------------------------
echo -e "\e[1;36m[6/8] Creating AdGuard Updater Script...\e[0m"
cat << EOF > /root/update-adguard.sh
#!/bin/bash
URL="$GITHUB_URL"
IP="$SERVER_IP"
OUT="/opt/AdGuardHome/data/adguard-rewrite.txt"

mkdir -p /opt/AdGuardHome/data/

if [ -z "\$URL" ]; then
    echo "" > "\$OUT"
    echo "GitHub URL was skipped. Created an empty rules file."
else
    curl -s "\$URL" | awk -v ip="\$IP" '
        !/^[[:space:]]*#/ {
            sub(/\r/,"");
            if (length(\$1) > 0) {
                print "||" \$1 "^\$dnsrewrite=" ip
            }
        }
    ' > "\$OUT"
    echo "AdGuard Rules successfully updated at \$(date)"
fi
EOF
chmod +x /root/update-adguard.sh

/root/update-adguard.sh

(crontab -l 2>/dev/null | grep -v "/root/update-adguard.sh"; echo "0 */12 * * * /root/update-adguard.sh") | crontab -

echo -e "\e[1;36m[7/8] Finalizing Setup...\e[0m"

systemctl daemon-reload
systemctl enable adguard-monitor.service
systemctl start adguard-monitor.service

if ! grep -q "alias menu='bash /root/panel.sh'" ~/.bashrc; then
    echo "alias menu='bash /root/panel.sh'" >> ~/.bashrc
fi
if ! grep -q "alias hajm='bash /root/traffic.sh'" ~/.bashrc; then
    echo "alias hajm='bash /root/traffic.sh'" >> ~/.bashrc
fi
if ! grep -q "/root/display.sh" ~/.bashrc; then
    echo "" >> ~/.bashrc
    echo "# Auto-display traffic on login" >> ~/.bashrc
    echo "/root/display.sh" >> ~/.bashrc
fi

echo -e "\e[1;36m[8/8] Executing Final Commands...\e[0m"
# اجرای قوانین بازیابی شده
echo "Running restore_rules.sh..."
bash /root/restore_rules.sh

# بارگذاری مجدد فایل .bashrc
echo "Reloading .bashrc..."
source ~/.bashrc || true

echo -e "\e[1;32m===================================================================\e[0m"
echo -e "\e[1;32m✅ Installation Completed Successfully!\e[0m"
echo -e "\e[1;32m===================================================================\e[0m"
