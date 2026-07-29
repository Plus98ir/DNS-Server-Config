<div align="center">

# 🌍 Ultimate Server Setup & Routing Script
### [🇺🇸 English Documentation](#english) | [🇮🇷 توضیحات مستندات فارسی](#persian)

</div>

---

<a id="english"></a>
## 🇺🇸 English Documentation

### 📌 Overview
This script is an **All-in-One Automated Setup** for creating a secure, high-performance routing server. It automatically installs and configures essential tools for traffic routing, DNS management, bandwidth monitoring, and user access control. It is designed to be public and deployable on any server.

### 🚀 Features & What It Does
When you run this script, it automatically performs the following tasks:

1. **System Update & Dependencies:** Updates the OS and installs required packages (`curl`, `wget`, `iptables`, `vnstat`, `ipset`, `iftop`, `nethogs`, `jq`, etc.).
2. **Network Optimization (BBR):** Enables and configures TCP BBR and `fq` qdisc for optimal network congestion control and speed.
3. **X-UI (Sanaei) Installation:** Automatically detects and installs the 3X-UI panel for proxy management if it's not already present.
4. **AdGuard Home Configuration:**
   * Installs AdGuard Home with a customized public configuration (Bind IP: `0.0.0.0`, Upstream: Local Unbound on `5335`).
   * Optimizes cache sizes, disables unnecessary logging, and secures the DNS from public abuse.
5. **Dynamic Access Control (IPSet & IPTables):**
   * **`restore_rules.sh`**: Rebuilds NAT and Mangle rules on boot to forward authorized traffic directly to local X-UI ports.
   * **`adguard-monitor.sh`**: Scans AdGuard Home logs for new client IPs and dynamically adds them to an `allowed_users` IPSet with a 1-hour timeout.
6. **GitHub Rules Auto-Updater:**
   * Automatically fetches your clean domain list from GitHub, ignores `#` comments, and appends `$dnsrewrite=[YOUR_SERVER_IP]`.
   * Sets up a cronjob to update this list automatically every 12 hours.
7. **Traffic Quota Management & CLI Tools:**
   * **`traffic.sh` (`hajm`)**: Calculates precise bandwidth usage, remaining quotas, and handles monthly resets.
   * **`display.sh`**: Shows a beautiful ASCII banner with remaining traffic automatically upon SSH login.
   * **`panel.sh` (`menu`)**: An interactive CLI menu to view active users, monitor bandwidth, manage blocklists, and restart services.

### 🔒 How to Authorize Users (Wildcard Setup & Clients)
To prevent your server from being used as an Open Resolver and to give each user private access, you must configure **Client IDs** using a Wildcard domain:

1. **Get a Wildcard Domain:** 
   In your domain's DNS manager (e.g., Cloudflare), create an `A` record with the name `*` (Wildcard) pointing to your Server IP. Ensure you have a Wildcard SSL certificate (e.g., `*.yourdomain.com`).
2. **Add Clients in AdGuard Home:**
   * Go to the AdGuard Home Web Panel.
   * Navigate to **Settings** > **Client Settings** and click **Add Client**.
   * Enter a Name for the user (e.g., `Mohsen`).
   * In the **Identifiers** field, type a unique Client ID (e.g., `mohsen`).
   * Save the client.
3. **Connecting the User:**
   The user can now connect securely using DoT or DoH. AdGuard will recognize them via the identifier:
   * **DoT:** `tls://mohsen.yourdomain.com`
   * **DoH:** `https://yourdomain.com/dns-query/mohsen`

### 📜 Default Routing Rules
During installation, the script will ask for a GitHub URL. If you don't have your own rules yet, you can use our default optimized list by pasting this link when prompted:
```text
(https://github.com/Plus98ir/AdGuard_Rules/blob/main/unsanction-rules.txt)
