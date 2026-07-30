<div align="center">

# 🌍 Ultimate Server Setup & Routing Script
### [🇺🇸 English Documentation](./README.md) | [🇮🇷 توضیحات مستندات فارسی](./README-fa.md)

</div>

---

<a id="english"></a>
## 🇺🇸 English Documentation

### 📌 Overview

* **Important Note: Please be very careful when entering your password. If you enter the incorrect password twice, the system will automatically block your device's IP (the computer or phone you are connecting from) — meaning it is not the server's IP. If this happens, you will need to change your local internet IP to reconnect.** *
  
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
bash <(curl -fsSL https://raw.githubusercontent.com/Plus98ir/DNS-Server-Config/refs/heads/main/install.sh)
```
"During installation, you will be asked to provide the following details for AdGuard Home:

URL (for the rules)

```txt
https://github.com/Plus98ir/AdGuard_Rules/blob/main/unsanction-rules.txt

```
Port

Username and Password

Note: I recommend using my link for the rules. It is a complete anti-sanction list that is constantly updated.


<img width="960" height="161" alt="image" src="https://github.com/user-attachments/assets/de6a8be4-1acb-446e-a9fa-7e722a9415e2" />

After the installation is complete, your AdGuard address is:
http://your-ip:port

**Note:** Since this is a custom configuration
further changes and configurations can be done directly in the /opt/AdGuardHome/AdGuardHome.yaml file

---

📜 Default Routing Rules
During installation, the script will ask for a GitHub URL. If you don't have your own rules yet, you can use my default optimized list by pasting this link when prompted:

If you are using custom routing rules, you must execute the following command in your terminal after providing the rules URL

```txt
/root/update-adguard.sh
```

Navigate to Filters > DNS blocklists, and click the blue Check for updates button

<img width="1363" height="799" alt="image" src="https://github.com/user-attachments/assets/d18b0f53-2f42-4494-af68-3f94069dd718" />

---

* **Available Commands After Install** (Aliases):
  
Type * **menu** * anywhere in the terminal to open the interactive management panel.

<img width="379" height="255" alt="image" src="https://github.com/user-attachments/assets/65b35cf0-c95e-4f04-a5cb-d20e0ae752bf" />

**Here you can choose what you want to do.**

---
Type * **hajm** * to view detailed bandwidth usage and manage traffic quotas.

<img width="412" height="272" alt="image" src="https://github.com/user-attachments/assets/fa59b82b-9789-4f11-ae99-4ebec481be3c" />
 
 **You can adjust and set it by your server's default time and GB.**
 
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
You can use Certbot. First, you need to install **certbot**:
```txt
apt install certbot
```
Then run the command to get the certificate:

```txt
certbot certonly \
--manual \
--preferred-challenges dns \
-d "*.yourdomain.com" \
-d "yourdomain.com"
```
You need to add 2 records as text in your Cloudflare; step-by-step, follow Certbot.
Then you will get your certificate paths like this:

```txt
/etc/letsencrypt/live/yourdomain.com/fullchain.pem
```
```txt
/etc/letsencrypt/live/yourdomain.com/privkey.pem
```
Then go to Settings > Encryption like the picture:

(Except the red line on this picture is an example for you; if you provide a valid address, you will see a green line.)

**(If you have another service on port 443, be careful and don't use port 443 for DoH.
Use another port. 443 is safe, but if you use a different port, your DoH address will look like this: 
https://yourdomain.com:8443/dns-query/yourclientname)**

---

<img width="625" height="856" alt="image" src="https://github.com/user-attachments/assets/a826e104-25a9-47b0-a31e-bd9dc8941ea2" />

---

So now you can go to the setup guide and you will see your DoH, DoT, and QUIC, as well as your IP address. But in this tutorial, the IP will not work because it's in private mode.

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

The User ID is important, but by name, you can recognize who connected to your server in the AdGuard Home log manager.

---
If you run into any issues, feel free to contact me on Telegram. I will get back to you as soon as possible.

```txt
@PlusNE
```

