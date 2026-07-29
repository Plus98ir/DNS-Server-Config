<div align="center">

# 🌍 Ultimate Server Setup & Routing Script
### [🇺🇸 English Documentation](./README.md) | [🇮🇷 توضیحات مستندات فارسی](./README-fa.md)

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
   * Installs AdGuard Home with a customized public configuration (Bind IP: `0.0.0.0`).
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

### 🛠 Installation & Usage
You can install and run the setup script using `curl`:

```bash
curl -L -o install.sh [https://github.com/Plus98ir/DNS-Server-Config/releases/download/v1.0.0/install.sh](https://github.com/Plus98ir/DNS-Server-Config/releases/download/v1.0.0/install.sh)
chmod +x install.sh
./install.sh
