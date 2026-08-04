# 🌍 Personal DNS Server Setup & Routing Script

---

**🇺🇸 English** | [🇮🇷 فارسی](README-Fa.md)

---
 <p align="center">
  <a href="https://Plus98ir.github.io">
    <img src="https://img.shields.io/badge/Website-Plus98ir.github.io-blue?style=for-the-badge&logo=google-chrome" alt="Web Page">
  </a>
</p>

---

## 🇺🇸 English Documentation

### 📌 Overview

**Important Note:** Please be very careful when entering your password. If you enter the incorrect password twice, the system will automatically block your device's IP (the computer or phone you are using).

This script is an **All-in-One Automated Setup** for creating a secure, high-performance routing server. It automatically installs and configures essential tools for traffic routing, DNS management, and access control.

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
---
7. **Traffic Quota Management & CLI Tools:**
   * **`traffic.sh` (`hajm`)**: Calculates precise bandwidth usage, remaining quotas, and handles monthly resets.



   <img width="413" height="257" alt="image" src="https://github.com/user-attachments/assets/32999464-9c7f-4e91-b959-f9786b319766" />

---

   * **`display.sh`**: Shows a beautiful ASCII banner with remaining traffic automatically upon SSH login.


   <img width="402" height="226" alt="image" src="https://github.com/user-attachments/assets/d4aedb0e-7836-4e8a-a135-7abc95b9259f" />

---

   * **`panel.sh` (`menu`)**: An interactive CLI menu to view active users, monitor bandwidth, manage blocklists, and restart services.


  
   <img width="360" height="282" alt="image" src="https://github.com/user-attachments/assets/9bc20405-27d6-458b-9e78-bf7fa0f1d710" />

---
**Note:** Before proceeding with the installation, ensure that port 53 on the server is not occupied by another service. Open the relevant configuration file, uncomment the line `DNSStubListener=yes`, and change it to `DNSStubListener=no`.

```bash
nano /etc/systemd/resolved.conf
```

Then, restart systemd-resolved.service and proceed with the installation.

```bash
systemctl restart systemd-resolved.service
```

### 🛠 Installation & Usage

You can install and run the setup script using `curl`:

```bash
bash <(curl -fsSL https://github.com/Plus98ir/DNS-Server-Config/releases/latest/download/install.sh)
```

During installation, you will be asked to provide the following details for AdGuard Home:

**URL (for the rules)**

```
https://github.com/Plus98ir/AdGuard_Rules/blob/main/unsanction-rules.txt
```

**Port**

**Username and Password**

**Note:** I recommend using my link for the rules. It is a complete anti-sanction list that is constantly updated.

After the installation is complete, your AdGuard address is:
```
http://your-ip:port
```

**Note:** Since this is a custom configuration, further changes and configurations can be done directly in the `/opt/AdGuardHome/AdGuardHome.yaml` file

---

### 📜 Default Routing Rules

During installation, the script will ask for a GitHub URL. If you don't have your own rules yet, you can use my default optimized list by pasting the link when prompted.

If you are using custom routing rules, you must execute the following command in your terminal after providing the rules URL:

```bash
/root/update-adguard.sh
```

Navigate to **Filters > DNS blocklists**, and click the blue **Check for updates** button.

---

### Available Commands After Install (Aliases)

Type **`menu`** anywhere in the terminal to open the interactive management panel. Here you can choose what you want to do.

---

Type **`hajm`** to view detailed bandwidth usage and manage traffic quotas. You can adjust and set it by your server's default time and GB.

---

### ⚙️ Important Post-Installation Steps (X-UI Configuration)

The only thing you need to do after the installation is to configure the X-UI Sanaei panel as follows:

1. Create two new Inbounds of type **Tunnel**.
2. Set the listening address (Listen IP) for both to `127.0.0.1`. Configure the first one on port 443 and the second one on port 80.
3. For both Inbounds, ensure that Sniffing is enabled, and explicitly check the quic, http, and tls options.
4. Finally, go to the Routing Rules section in the Sanaei panel. Route these two inbounds to an Outbound (preferably, a REALITY config connected to your foreign server under current network conditions).

### 🔒 How to Authorize Users (Wildcard Setup & Clients)

To prevent your server from being used as an Open Resolver and to give each user private access, you must configure Client IDs using a Wildcard domain.

#### Get a Wildcard Domain

In your domain's DNS manager (e.g., Cloudflare), create an A record with the name `*` (Wildcard) pointing to your Server IP. Ensure you have a Wildcard SSL certificate (e.g., `*.yourdomain.com`).

You can use Certbot. First, you need to install **certbot**:

```bash
apt install certbot
```

Then run the command to get the certificate:

```bash
certbot certonly \
--manual \
--preferred-challenges dns \
-d "*.yourdomain.com" \
-d "yourdomain.com"
```

You need to add 2 records as text in your Cloudflare; follow the steps provided by Certbot.

Then you will get your certificate paths like this:

```
/etc/letsencrypt/live/yourdomain.com/fullchain.pem
```

```
/etc/letsencrypt/live/yourdomain.com/privkey.pem
```

Then go to **Settings > Encryption** like the picture.

<img width="1085" height="1321" alt="image" src="https://github.com/user-attachments/assets/6abdb7b6-a8f7-467c-8806-04ac50f5a890" />


**Note:** If you have another service on port 443, be careful and don't use port 443 for DoH. Use another port. If you use a different port, your DoH address will look like this:
```
https://yourdomain.com:8443/dns-query/yourclientname
```

---

#### Add Clients in AdGuard Home

1. Go to the AdGuard Home Web Panel.
2. Navigate to **Settings > Client Settings** and click **Add Client**.
3. Enter a Name for the user (e.g., Sadeq-Pc).
4. In the Identifiers field, type a unique Client ID (e.g., sadeqpc1).
5. Save the client.

#### Connecting the User

The user can now connect securely using DoT or DoH. AdGuard will recognize them via the identifier:

**DoT:** `tls://yourclientname.yourdomain.com`

**DoH:** `https://yourdomain.com/dns-query/yourclientname`

**Recommend using a special id like `67ca2c09` for any client**

Now your client should use it like this:

**DoT:** `tls://67ca2c09.yourdomain.com`

**DoH:** `https://yourdomain.com/dns-query/yourclientname`

The User ID is important, but by name, you can recognize who connected to your server in the AdGuard Home log manager.

---

If you run into any issues, feel free to contact me on Telegram. I will get back to you as soon as possible.

```
@PlusNE
```
