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
curl -L -o install.sh (https://github.com/Plus98ir/DNS-Server-Config/releases/download/v1.0.0/install.sh)
```
📜 Default Routing Rules
During installation, the script will ask for a GitHub URL. If you don't have your own rules yet, you can use my default optimized list by pasting this link when prompted:

```bash
(https://github.com/Plus98ir/AdGuard_Rules/blob/main/unsanction-rules.txt)

```
* **Available Commands After Install** (Aliases):
---
Type **menu** anywhere in the terminal to open the interactive management panel.

<img width="379" height="255" alt="image" src="https://github.com/user-attachments/assets/65b35cf0-c95e-4f04-a5cb-d20e0ae752bf" />

here you can choise what you want to do

---
Type **hajm** to view detailed bandwidth usage and manage traffic quotas.

<img width="412" height="272" alt="image" src="https://github.com/user-attachments/assets/fa59b82b-9789-4f11-ae99-4ebec481be3c" />
 
 you can adjust and set by your server defualt time and GB 
 
---

⚙️ **Important Post-Installation Steps** (X-UI Configuration)
The only thing you need to do after the installation is to configure the X-UI Sanaei panel as follows:

Create two new Inbounds of type **Tunnel**.

Set the listening address (Listen IP) for both to 127.0.0.1. Configure the first one on port 443 and the second one on port 80.

For both Inbounds, ensure that Sniffing is enabled, and explicitly check the quic, http, and tls options.

Finally, go to the Routing Rules section in the Sanaei panel. Route these two inbounds to an Outbound (preferably, under current network conditions, a REALITY config connected to your foreign server, or any other outbound that bypasses sanctions).

🔒 **How to Authorize Users** (Wildcard Setup & Clients)
To prevent your server from being used as an Open Resolver and to give each user private access, you must configure Client IDs using a Wildcard domain:

Get a Wildcard Domain:
In your domain's DNS manager (e.g., Cloudflare), create an A record with the name * (Wildcard) pointing to your Server IP. Ensure you have a Wildcard SSL certificate (e.g., *.yourdomain.com).
you can use Certbot First need istall **certbot**
```txt
apt install certbot
```
then run command for get cert :
```txt
certbot certonly \
--manual \
--preferred-challenges dns \
-d "*.yourdomain.com" \
-d "yourdomain.com"
```
you need add 2 record as text in your cloudflare step by step follow certbot 
then you get your cert like this
```txt
/etc/letsencrypt/live/yourdomain.com/fullchain.pem
```
```txt
/etc/letsencrypt/live/yourdomain.com/privkey.pem
```
Then go to setting - encrypted like picture

(except the red line on this pics its example for you if you give valid addres you will see green line)

**(if you have another service in 443 becarefull dont use port 443 for DoH use another port but 443 is safebut
if you will use difrent port you your DoH address is like this https://yourdomain.com:8443/dns-query/yourclientname )**

---

<img width="625" height="856" alt="image" src="https://github.com/user-attachments/assets/a826e104-25a9-47b0-a31e-bd9dc8941ea2" />

---

so now you can go in setup guid and you will see your doh and dot and quic also ip address but in this education IP not work becuse its privet mode

---

<img width="819" height="787" alt="image" src="https://github.com/user-attachments/assets/5057a5a0-2bdb-48f0-b627-546a2323adb5" />

---

Add Clients in AdGuard Home:

Go to the AdGuard Home Web Panel.

Navigate to Settings > Client Settings and click Add Client.

Enter a Name for the user (e.g., Sadeq-Pc).

In the Identifiers field, type a unique Client ID (e.g., sadeqpc1).

Save the client.

---

Connecting the User:
The user can now connect securely using DoT or DoH. AdGuard will recognize them via the identifier:

**DoT**: (tls://yourclientname.yourdomain.com)

**DoH**: (https://yourdomain.com/dns-query/yourclientname)

**Recomend use spacial id like 67ca2c09 for any client**
now your client shoud use like this

**DoT**: (tls://67ca2c09.yourdomain.com)

**DoH**: (https://yourdomain.com/dns-query/yourclientname)

User id is serius but by name you can recognize who connected to your server in AdguardHome log manager
