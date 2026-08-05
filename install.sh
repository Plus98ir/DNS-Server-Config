#!/bin/bash
# ==========================================
# Automated Server Setup Script (Public Version)
# X-UI Sanaei, AdGuard Home, IPSet, BBR, Rules Updater
# ==========================================

# توقف اسکریپت در صورت بروز خطای بحرانی
set -e

echo -e "\e[1;36m====================================================\e[0m"
echo -e "\e[1;33m  INITIAL CONFIGURATION \e[0m"
echo -e "\e[1;36m====================================================\e[0m"

# استفاده از /dev/tty برای اطمینان از اینکه حتی با دستور curl هم کیبورد خوانده شود
read -p "Enter GitHub Raw URL for your rules (Leave blank to skip): " GITHUB_URL </dev/tty

read -p "Enter AdGuard Home Web UI Port (Default 8090): " AGH_PORT </dev/tty
AGH_PORT=${AGH_PORT:-8090}

read -p "Enter AdGuard Home Username (Default plus98): " AGH_USER </dev/tty
AGH_USER=${AGH_USER:-plus98}

read -p "Enter AdGuard Home Password (Default plus98): " AGH_PASS </dev/tty
AGH_PASS=${AGH_PASS:-plus98}

echo -e "\e[1;36m[1/8] Updating system and installing dependencies...\e[0m"
apt-get update -y
apt-get install -y curl wget nano iptables vnstat ipset bc nethogs iftop jq figlet apache2-utils

# پیدا کردن دومین آی‌پی سرور (اگر نبود، استفاده از آی‌پی اول)
SERVER_IP=$(ip -4 addr show scope global | awk '$1 == "inet" {print $2}' | cut -d/ -f1 | sed -n '2p')
if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SERVER_IP=$(ip -4 addr show scope global | awk '$1 == "inet" {print $2}' | cut -d/ -f1 | sed -n '1p')
fi

# اگر باز هم پیدا نشد، از سرویس‌های آنلاین یا پرسش از کاربر استفاده کند
if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    SERVER_IP=$(curl -s4 api.ipify.org || curl -s4 icanhazip.com || curl -s4 ifconfig.me)
fi

if [[ ! "$SERVER_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "\e[1;31mCould not detect Server IP automatically!\e[0m"
    read -p "Please enter your Server IP manually: " SERVER_IP </dev/tty
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

# حل مشکل crontab با اضافه کردن || true
(crontab -l 2>/dev/null | grep -v "/root/restore_rules.sh" || true; echo "@reboot /root/restore_rules.sh") | crontab -

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

# بارگذاری تنظیمات
if [ -f "$SETTINGS_FILE" ]; then
    source "$SETTINGS_FILE"
fi

if [ -f "$EXTRA_FILE" ]; then
    EXTRA=$(cat "$EXTRA_FILE")
else
    EXTRA=0
fi

# --- مقادیر پیش‌فرض ---
BASE_LIMIT=${BASE_LIMIT:-100}
EXPIRY_DATE=${EXPIRY_DATE:-""}
EXTRA_GB=${EXTRA_GB:-0}
OFFSET=${OFFSET:-0}
CARRY_OVER=${CARRY_OVER:-"yes"}
INCLUDE_UPLOAD=${INCLUDE_UPLOAD:-"no"}
LANGUAGE=${LANGUAGE:-"en"}
EXTRA=${EXTRA:-0}

# --- تابع ذخیره تنظیمات ---
save_settings() {
    echo "BASE_LIMIT=$BASE_LIMIT" > "$SETTINGS_FILE"
    echo "EXTRA_GB=$EXTRA_GB" >> "$SETTINGS_FILE"
    echo "EXPIRY_DATE=\"$EXPIRY_DATE\"" >> "$SETTINGS_FILE"
    echo "OFFSET=$OFFSET" >> "$SETTINGS_FILE"
    echo "CARRY_OVER=\"$CARRY_OVER\"" >> "$SETTINGS_FILE"
    echo "INCLUDE_UPLOAD=\"$INCLUDE_UPLOAD\"" >> "$SETTINGS_FILE"
    echo "LANGUAGE=\"$LANGUAGE\"" >> "$SETTINGS_FILE"
}

# --- بخش ترجمه (چندزبانه) ---
if [ "$LANGUAGE" == "fa" ]; then
    L_TBL_HDR="    تاریخ        دانلود        آپلود          مجموع"
    L_RX="دانلود (RX):            "
    L_TX="آپلود (TX):             "
    L_OFFSET="ترافیک از دست رفته (Offset):"
    L_CAPACITY="ظرفیت کل ترافیک:        "
    L_BASE_LEFT="باقی‌مانده پایه"
    L_EXTRA_LEFT="باقی‌مانده اضافه"
    L_DAYS="روزهای باقی‌مانده:      "
    L_REMAINING="ترافیک باقی‌مانده:       "
    L_STATUS="وضعیت:                  "
    L_RESETTING="در حال ریست برای ماه جدید..."
    L_OPT1="[1] حجم اضافه (افزودن/کسر)"
    L_OPT2="[2] تنظیم حجم پایه"
    L_OPT3="[3] تغییر تاریخ انقضا"
    L_OPT4="[4] صفر کردن حجم اضافه"
    L_OPT5="[5] ریست مصرف ماهانه"
    L_OPT6="[6] همگام‌سازی ترافیک (Offset)"
    L_OPT7="[7] انتقال به ماه بعد: [$CARRY_OVER]"
    L_OPT8="[8] محاسبه آپلود: [$INCLUDE_UPLOAD]"
    L_OPT9="[9] تغییر زبان: [فارسی]"
    L_EXIT="[Enter] خروج"
    L_SELECT="انتخاب گزینه: "
    L_PR_EXT="حجم مورد نظر برای افزودن/کسر را وارد کنید: "
    L_PR_BAS="حجم پایه جدید را وارد کنید (فعلی $BASE_LIMIT گیگ): "
    L_PR_EXP="تاریخ انقضای جدید را وارد کنید (سال-ماه-روز): "
    L_PR_OFF="آفست فعلی $OFFSET گیگابایت است. حجم دانلود از دست رفته را برای افزودن وارد کنید: "
    L_MSG_RES="مصرف ماهانه با موفقیت صفر شد!"
else
    L_TBL_HDR="    DATE         DOWNLOAD    UPLOAD      TOTAL"
    L_RX="Download (RX):          "
    L_TX="Upload (TX):            "
    L_OFFSET="Synced Lost Traffic:    "
    L_CAPACITY="Total Traffic Capacity: "
    L_BASE_LEFT="Base Left"
    L_EXTRA_LEFT="Extra Left"
    L_DAYS="Days Remaining:         "
    L_REMAINING="Traffic Remaining:      "
    L_STATUS="Status:                 "
    L_RESETTING="RESETTING FOR NEW MONTH..."
    L_OPT1="[1] Add/Reduce Extra"
    L_OPT2="[2] Set Base GB"
    L_OPT3="[3] Set Expiry Date"
    L_OPT4="[4] Reset Extra"
    L_OPT5="[5] Reset Monthly"
    L_OPT6="[6] Sync Offset"
    L_OPT7="[7] Carry-Over: [$CARRY_OVER]"
    L_OPT8="[8] Calc Upload: [$INCLUDE_UPLOAD]"
    L_OPT9="[9] Language: [English]"
    L_EXIT="[Enter] Exit"
    L_SELECT="Select option: "
    L_PR_EXT="Enter GB to add/reduce extra: "
    L_PR_BAS="Enter new Base Monthly GB (current is $BASE_LIMIT): "
    L_PR_EXP="New Expiry Date (YYYY-MM-DD): "
    L_PR_OFF="Current lost traffic offset is $OFFSET GB. Enter new offset to ADD to usage: "
    L_MSG_RES="Monthly usage reset successfully!"
fi

# --- استخراج مصرف دانلود و آپلود ---
RX_GB=$(vnstat -m | awk '
    /^[[:space:]]*[0-9]{4}-[0-9]{2}/ || /^[[:space:]]*[A-Za-z]{3} \x27[0-9]{2}/ {
        val=$2; unit=$3
        if(unit == "MiB") val = val / 1024
        else if(unit == "KiB") val = val / (1024 * 1024)
        else if(unit == "TiB") val = val * 1024
        total += val
    }
    END {
        if(total == "") total = 0
        printf "%.2f\n", total
    }
')
RX_GB=${RX_GB:-0}

TX_GB=$(vnstat -m | awk '
    /^[[:space:]]*[0-9]{4}-[0-9]{2}/ || /^[[:space:]]*[A-Za-z]{3} \x27[0-9]{2}/ {
        val=$5; unit=$6
        if(unit == "MiB") val = val / 1024
        else if(unit == "KiB") val = val / (1024 * 1024)
        else if(unit == "TiB") val = val * 1024
        total += val
    }
    END {
        if(total == "") total = 0
        printf "%.2f\n", total
    }
')
TX_GB=${TX_GB:-0}

if [ "$INCLUDE_UPLOAD" == "yes" ]; then
    USED_GB=$(echo "scale=2; $RX_GB + $TX_GB" | bc)
else
    USED_GB=$RX_GB
fi

ACTUAL_USED=$(echo "scale=2; $USED_GB + $OFFSET" | bc)

# --- بخش ریست خودکار ---
if [ -n "$EXPIRY_DATE" ]; then
    TODAY_TS=$(date +%s -d "$(date +%Y-%m-%d)")
    EXPIRY_TS=$(date +%s -d "$EXPIRY_DATE")

    if [ "$TODAY_TS" -ge "$EXPIRY_TS" ]; then
        if [ "$CARRY_OVER" == "yes" ]; then
            if (( $(echo "$ACTUAL_USED <= $EXTRA_GB" | bc -l) )); then
                EXTRA_GB=$(echo "scale=2; $EXTRA_GB - $ACTUAL_USED" | bc)
            else
                EXTRA_GB=0
            fi
        else
            EXTRA_GB=0
        fi

        vnstat --create -i eth0 --force > /dev/null 2>&1
        EXPIRY_DATE=$(date +%Y-%m-%d -d "$EXPIRY_DATE + 1 month")
        OFFSET=0
        save_settings

        USED_GB=0
        ACTUAL_USED=0
        RX_GB=0
        TX_GB=0
    fi
fi

TOTAL_LIMIT=$(echo "scale=2; $BASE_LIMIT + $EXTRA_GB" | bc)

# --- نمایش خروجی ---
echo -e "\e[1;36m====================================================\e[0m"
echo -e "\e[1;33m$L_TBL_HDR\e[0m"
echo -e "\e[1;36m----------------------------------------------------\e[0m"
vnstat -d --short | grep -v "estimated" | grep -A 5 "day" | tail -n 5 | \
awk '{printf " %-12s %-12s %-12s %-12s\n", $1, $2$3, $5$6, $8$9}'
echo -e "\e[1;36m----------------------------------------------------\e[0m"

REMAINING_GB=$(echo "scale=2; $TOTAL_LIMIT - $ACTUAL_USED" | bc)

if (( $(echo "$ACTUAL_USED <= $EXTRA_GB" | bc -l) )); then
    EXTRA_LEFT=$(echo "scale=2; $EXTRA_GB - $ACTUAL_USED" | bc | awk '{printf "%.2f", $0}')
    BASE_LEFT=$(echo "scale=2; $BASE_LIMIT" | bc | awk '{printf "%.2f", $0}')
else
    EXTRA_LEFT="0.00"
    BASE_LEFT=$(echo "scale=2; $BASE_LIMIT - ($ACTUAL_USED - $EXTRA_GB)" | bc | awk '{printf "%.2f", $0}')
fi

# محاسبه ایمن روزها
if [ -z "$EXPIRY_DATE" ]; then
    DAYS_LEFT="-"
else
    CURRENT_TIME=$(date +%s)
    TARGET_TIME=$(date -d "$EXPIRY_DATE" +%s)
    SECONDS_LEFT=$(( TARGET_TIME - CURRENT_TIME ))
    DAYS_LEFT=$(( SECONDS_LEFT / 86400 ))
    if [ "$DAYS_LEFT" -le 0 ]; then DAYS_LEFT=0; fi
fi

echo -e "\e[1;32m $L_RX $RX_GB GB\e[0m"
echo -e "\e[1;32m $L_TX $TX_GB GB\e[0m"

if (( $(echo "$OFFSET > 0" | bc -l) )); then
    echo -e "\e[1;35m $L_OFFSET $OFFSET GB\e[0m"
fi
echo -e "\e[1;31m $L_CAPACITY $TOTAL_LIMIT GB\e[0m"

echo -e "\e[1;33m ($L_BASE_LEFT: $BASE_LEFT GB | $L_EXTRA_LEFT: $EXTRA_LEFT GB)\e[0m"

if [[ "$DAYS_LEFT" == "-" ]] || [ "$DAYS_LEFT" -gt 0 ]; then
    echo -e "\e[1;35m $L_DAYS $DAYS_LEFT\e[0m"
    echo -e "\e[1;34m $L_REMAINING $REMAINING_GB GB\e[0m"
else
    echo -e "\e[1;31m $L_STATUS $L_RESETTING\e[0m"
fi
echo -e "\e[1;36m====================================================\e[0m"

if [ "$1" == "auto" ]; then
    exit 0
fi

echo -e "\e[1;33m$L_OPT1   $L_OPT2   $L_OPT3\n$L_OPT4   $L_OPT5   $L_OPT6\n$L_OPT7   $L_OPT8\n$L_OPT9                 $L_EXIT\e[0m"
read -p "$L_SELECT" opt

case "$opt" in
    1) read -p "$L_PR_EXT" new_gb
       EXTRA_GB=$(echo "scale=2; $EXTRA_GB + $new_gb" | bc)
       save_settings
       exec bash "$0" ;;
    2) read -p "$L_PR_BAS" new_base
       BASE_LIMIT=$new_base
       save_settings
       exec bash "$0" ;;
    3) read -p "$L_PR_EXP" new_date
       EXPIRY_DATE="$new_date"
       save_settings
       exec bash "$0" ;;
    4) EXTRA_GB=0
       save_settings
       exec bash "$0" ;;
    5)
       if [ "$CARRY_OVER" == "yes" ]; then
           if (( $(echo "$ACTUAL_USED <= $EXTRA_GB" | bc -l) )); then
               EXTRA_GB=$(echo "scale=2; $EXTRA_GB - $ACTUAL_USED" | bc)
           else
               EXTRA_GB=0
           fi
       else
           EXTRA_GB=0
       fi
       OFFSET=0
       save_settings
       vnstat --create -i eth0 --force > /dev/null 2>&1
       echo -e "\e[1;32m $L_MSG_RES\e[0m"
       sleep 1
       exec bash "$0" ;;
    6) read -p "$L_PR_OFF" new_offset
       OFFSET=$(echo "scale=2; $OFFSET + $new_offset" | bc)
       save_settings
       exec bash "$0" ;;
    7)
       if [ "$CARRY_OVER" == "yes" ]; then CARRY_OVER="no"; else CARRY_OVER="yes"; fi
       save_settings
       exec bash "$0" ;;
    8)
       if [ "$INCLUDE_UPLOAD" == "yes" ]; then INCLUDE_UPLOAD="no"; else INCLUDE_UPLOAD="yes"; fi
       save_settings
       exec bash "$0" ;;
    9)
       if [ "$LANGUAGE" == "en" ]; then LANGUAGE="fa"; else LANGUAGE="en"; fi
       save_settings
       exec bash "$0" ;;
esac
EOF
chmod +x /root/traffic.sh

# ---------------------------------------------------------
# 4. Display Script
# ---------------------------------------------------------
cat << 'EOF' > /root/display.sh
#!/bin/bash

# --- بارگذاری تنظیمات ---
[ -f "$HOME/.traffic_settings" ] && source "$HOME/.traffic_settings"

# --- مقادیر پیش‌فرض ---
BASE_LIMIT=${BASE_LIMIT:-100}
EXTRA_GB=${EXTRA_GB:-0}
OFFSET=${OFFSET:-0}
INCLUDE_UPLOAD=${INCLUDE_UPLOAD:-"no"}
EXPIRY_DATE=${EXPIRY_DATE:-""}

# --- استخراج مصرف دانلود (RX) ---
RX_GB=$(vnstat -m | awk '
    /^[[:space:]]*[0-9]{4}-[0-9]{2}/ || /^[[:space:]]*[A-Za-z]{3} \x27[0-9]{2}/ {
        val=$2; unit=$3
        if(unit == "MiB") val = val / 1024
        else if(unit == "KiB") val = val / (1024 * 1024)
        else if(unit == "TiB") val = val * 1024
        total += val
    }
    END {
        if(total == "") total = 0
        printf "%.2f\n", total
    }
')
RX_GB=${RX_GB:-0}

# --- استخراج مصرف آپلود (TX) ---
TX_GB=$(vnstat -m | awk '
    /^[[:space:]]*[0-9]{4}-[0-9]{2}/ || /^[[:space:]]*[A-Za-z]{3} \x27[0-9]{2}/ {
        val=$5; unit=$6
        if(unit == "MiB") val = val / 1024
        else if(unit == "KiB") val = val / (1024 * 1024)
        else if(unit == "TiB") val = val * 1024
        total += val
    }
    END {
        if(total == "") total = 0
        printf "%.2f\n", total
    }
')
TX_GB=${TX_GB:-0}

# --- محاسبه بر اساس تنظیمات آپلود/دانلود ---
if [ "$INCLUDE_UPLOAD" == "yes" ]; then
    USED_GB=$(echo "scale=2; $RX_GB + $TX_GB" | bc)
else
    USED_GB=$RX_GB
fi

# --- محاسبات نهایی هماهنگ با اسکریپت اصلی ---
ACTUAL_USED=$(echo "scale=2; $USED_GB + $OFFSET" | bc)
TOTAL_LIMIT=$(echo "scale=2; $BASE_LIMIT + $EXTRA_GB" | bc)
REMAINING_GB=$(echo "scale=2; $TOTAL_LIMIT - $ACTUAL_USED" | bc)

# --- محاسبه روزهای باقیمانده (ضد کرش) ---
if [ -z "$EXPIRY_DATE" ]; then
    DAYS_LEFT="-"
else
    CURRENT_TIME=$(date +%s)
    TARGET_TIME=$(date -d "$EXPIRY_DATE" +%s)
    SECONDS_LEFT=$(( TARGET_TIME - CURRENT_TIME ))
    DAYS_LEFT=$(( SECONDS_LEFT / 86400 ))
    if [ "$DAYS_LEFT" -le 0 ]; then
        DAYS_LEFT=0
    fi
fi

# --- نمایش در ترمینال ---
clear
echo -e "\e[1;36m"
figlet -f slant "TRAFFIC"
echo -e "\e[0m"

echo -e "\e[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
echo -e "\e[1;32m  TOTAL TRAFFIC:  \e[1;37m$TOTAL_LIMIT GB\e[0m"
echo -e "\e[1;32m  TRAFFIC LEFT:   \e[1;33m$REMAINING_GB GB\e[0m"
echo -e "\e[1;37m----------------------------------------------------\e[0m"
echo -e "\e[1;32m  REMAINING DAYS: \e[1;36m$DAYS_LEFT Days\e[0m"
echo -e "\e[1;37m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\e[0m"
EOF
chmod +x /root/display.sh

# ---------------------------------------------------------
# 5. Panel Menu Script
# ---------------------------------------------------------
cat << 'EOF' > /root/panel.sh
#!/bin/bash
# Fix for GoTTY/Web Terminal
export TERM=xterm-256color
# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'
show_menu() {
    clear
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${CYAN}     SERVER USAGE PANEL - Press Q (Back)          ${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo -e "1) ${GREEN}Active Users Report${NC} (Traffic + ISP + Timeout)"
    echo -e "2) ${GREEN}Add New IP${NC} manually"
    echo -e "3) ${RED}Remove IP${NC} manually"
    echo -e "4) ${YELLOW}Live Packet Monitor${NC}"
    echo -e "5) ${YELLOW}Real-time Bandwidth${NC} (iftop)"
    echo -e "6) ${PURPLE}Connected IP Logs${NC}"
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
            echo -e "\n${CYAN}Generating Full Traffic Report...${NC}"
            echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
            printf "%-18s | %-12s | %-10s | %-20s\n" "Source/Service" "Traffic" "Status" "Description"
            echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
            
            # --- بخش اصلاح شده: ترتیب پورت‌ها ۸۰، ۴۴۳ TCP و ۴۴۳ UDP ---
            # ابتدا پورت ۸۰، سپس ۴۴۳ تی‌سی‌پی و در نهایت ۴۴۳ یودی‌پی
            for item in "80:tcp" "443:tcp" "443:udp"; do
                port=$(echo $item | cut -d: -f1)
                proto=$(echo $item | cut -d: -f2)
                
                # فیلتر کردن ترافیک بر اساس پورت و پروتکل در iptables
                raw_p=$(iptables -t mangle -L -n -v -x | grep -i "$proto" | grep -E "dpt:$port|spt:$port" | awk '{sum+=$2} END {print sum}')
                
                [ -z "$raw_p" ] || [ "$raw_p" == "0" ] && raw_p=0
                if [ "$raw_p" -lt 1048576 ]; then
                    p_traffic="$(($raw_p / 1024)) KB"
                elif [ "$raw_p" -lt 1073741824 ]; then
                    p_traffic="$(($raw_p / 1048576)) MB"
                else
                    p_traffic="$(awk "BEGIN {printf \"%.2f\", $raw_p/1073741824}") GB"
                fi
                
                # تعیین نام نمایشی بر اساس پروتکل
                if [ "$port" == "80" ]; then
                    p_name="PORT:80"
                else
                    p_name="PORT:443 ($(echo $proto | tr '[:lower:]' '[:upper:]'))"
                fi
                
                printf "${YELLOW}%-18s${NC} | ${GREEN}%-12s${NC} | ${CYAN}%-10s${NC} | ${PURPLE}%-20s${NC}\n" "$p_name" "$p_traffic" "GLOBAL" "Total Usage"
            done
            echo -e "${BLUE}--------------------------------------------------------------------------------${NC}"
            # --- ادامه بخش ترافیک یوزرها ---
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
                    else u_traffic="$(awk "BEGIN {printf \"%.2f\", $bytes/1073741824}") GB"; fi
                    isp=$(curl -s --connect-timeout 2 "http://ip-api.com/line/$ip?fields=isp" | head -n 1)
                    [[ -z "$isp" || "$isp" == *"{"* ]] && isp="Unknown" || isp=$(echo "$isp" | cut -c1-20)
                    printf "${GREEN}%-18s${NC} | ${BLUE}%-12s${NC} | ${YELLOW}%-10s${NC} | ${PURPLE}%-20s${NC}\n" "$ip" "$u_traffic" "${timeout}s" "$isp"
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
                printf "%-18s | %-30s\n" "Blocked IP" "ISP/Organization"
                echo -e "${BLUE}----------------------------------------------------------------------${NC}"
                ips=$(ipset list blacklist | sed -n '/Members:/,$p' | tail -n +2)
                while read -r bl_ip; do
                    [ -z "$bl_ip" ] && continue
                    bl_isp=$(curl -s --connect-timeout 2 "http://ip-api.com/line/$bl_ip?fields=isp" | head -n 1)
                    [[ -z "$bl_isp" || "$bl_isp" == *"{"* ]] && bl_isp="Unknown" || bl_isp=$(echo "$bl_isp" | cut -c1-30)
                    printf "${RED}%-18s${NC} | ${PURPLE}%-30s${NC}\n" "$bl_ip" "$bl_isp"
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

# ---------------------------------------------------------
# 6. AdGuard GitHub Rules Updater Script
# ---------------------------------------------------------
echo -e "\e[1;36m[6/8] Creating AdGuard Updater Script...\e[0m"
cat << EOF > /root/update-adguard.sh
#!/bin/bash

# پیدا کردن هوشمند آی‌پی سرور در زمان اجرای آپدیت
SERVER_IP=\$(ip -4 addr show scope global | awk '\$1 == "inet" {print \$2}' | cut -d/ -f1 | sed -n '2p')
if [[ ! "\$SERVER_IP" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
    SERVER_IP=\$(ip -4 addr show scope global | awk '\$1 == "inet" {print \$2}' | cut -d/ -f1 | sed -n '1p')
fi
if [[ ! "\$SERVER_IP" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
    SERVER_IP=\$(curl -s4 api.ipify.org || curl -s4 icanhazip.com || curl -s4 ifconfig.me)
fi
if [[ ! "\$SERVER_IP" =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
    exit 1
fi

URL="$GITHUB_URL"
[ -z "\$URL" ] && URL="https://ghproxy.net/https://raw.githubusercontent.com/Plus98ir/AdGuard_Rules/main/unsanction-rules.txt"
TEMP_FILE="/tmp/unsanction-rules.txt"

HTTP_STATUS=\$(curl -s -w "%{http_code}" -o "\$TEMP_FILE" "\$URL")

if [ "\$HTTP_STATUS" -ne 200 ] || [ ! -s "\$TEMP_FILE" ]; then
    rm -f "\$TEMP_FILE"
    exit 1
fi

awk -v ip="\$SERVER_IP" '
{
    sub(/\\r/,"");
    if (length(\$1) > 0 && \$1 !~ /^#/) {
        print "||"\$1"^\\\$dnsrewrite="ip
    }
}' "\$TEMP_FILE" > /opt/AdGuardHome/data/adguard-rewrite.txt

rm -f "\$TEMP_FILE"
echo "AdGuard Rules successfully updated at \$(date)"
EOF
chmod +x /root/update-adguard.sh

/root/update-adguard.sh

# حل مشکل crontab با اضافه کردن || true
# تنظیم کرون‌جاب آپدیت رول‌های ادگارد
(crontab -l 2>/dev/null | grep -v "/root/update-adguard.sh" || true; echo "0 */12 * * * /root/update-adguard.sh") | crontab -

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
