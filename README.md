# fritz_TR-064

A collection of scripts for controlling and querying AVM FRITZ!Box routers via the TR-064 protocol. Supports port mapping, external IP retrieval, call deflection, config/phonebook export, WLAN control, device presence detection, and smart home (AHA) operations.

## Prerequisites

- **Python 3** with the `requests` library (`pip install requests`) — for `tr-064.py`
- **curl** — for `fritzbox-tr064.sh`
- **PowerShell 3.0+** — for `fb-power.ps1`
- A FRITZ!Box with **TR-064 enabled** (see below)
- A FritzBox user account with the appropriate permissions

## Enabling TR-064 on the FRITZ!Box

1. Open the FritzBox web UI (usually http://fritz.box or http://192.168.178.1)
2. Navigate to **Heimnetz → Netzwerk → Netzwerkeinstellungen**
3. Check **"Zugriff für Anwendungen zulassen"**
4. Apply the settings

TR-064 uses **HTTP Digest Authentication** and listens on:
- **Port 49000** (HTTP)
- **Port 49443** (HTTPS)

The service description is available at `http://fritz.box:49000/tr64desc.xml`.

## Scripts

| Script | Language | Description |
|--------|----------|-------------|
| `tr-064.py` | Python | TR-064 client for common operations: port mapping, external IP, call deflection, config export, phone book export |
| `FB-main.sh` | Shell | HomeMatic/CUxD integration — WLAN control, device presence, network queries |
| `FB-AHA.sh` | Shell | HomeMatic/CUxD integration — AVM Home Automation (AHA) smart home control |
| `FB.common` | Shell | Shared functions used by `FB-main.sh` and `FB-AHA.sh` |
| `FB.cfg` | Config | Configuration file for the shell scripts (IP, credentials, paths) |
| `fritzbox-tr064.sh` | Bash/curl | Minimal curl-based SOAP example for TR-064 calls |
| `fb-power.ps1` | PowerShell | TR-064 client using .NET WebRequest — reboot, info queries, WLAN, WAN stats |

## Quick Start

```bash
# Edit credentials in tr-064.py (user/password in the 'para' dict)
# or adapt the script to use environment variables, then:

python3 tr-064.py external-ip
python3 tr-064.py port-count
```

For the shell scripts (HomeMatic integration), edit `FB.cfg` with your FritzBox IP and credentials:

```bash
# FB.cfg
IP="192.168.178.1"
USER="your_username"
PASS="your_password"
```

For the curl example:

```bash
# Edit FRITZUSER / FRITZPW in fritzbox-tr064.sh, then:
bash fritzbox-tr064.sh
```

## TR-064 Resources

**AVM Documentation**
- [AVM Schnittstellen & Protokolle](https://avm.de/service/schnittstellen/) — official interface documentation

**Specifications**
- [TR-064 Corrigendum 1](https://www.broadband-forum.org/wp-content/uploads/2018/11/TR-064_Corrigendum-1.pdf) — Broadband Forum LAN-Side DSL CPE Configuration spec
- [UPnP WANPPPConnection Service Template](http://upnp.org/specs/gw/UPnP-gw-WANPPPConnection-v1-Service.pdf)

**Community & Discussions**
- [c't: AddPortMapping mit Python](https://www.heise.de/forum/c-t/Kommentare-zu-c-t-Artikeln/Fritzbox-per-Skript-fernsteuern/AddPortMapping-mit-Python-funktioniert-nicht/posting-29394473/show/#posting_29394473)
- [administrator.de: PowerShell + FritzBox TR-064](https://administrator.de/wissen/powershell-fritzbox-tr-064-netzwerk-konfigurieren-auslesen-303474.html)
- [HomeMatic Forum: FritzBox TR-064 Skripte](https://homematic-forum.de/forum/viewtopic.php?f=37&t=27994&sid=42f13af71db968632f43b95cab361a89)
- [cron_fritzbox-reboot (GitHub)](https://github.com/nicoh88/cron_fritzbox-reboot)
- [c't Softlinks 2019/5](https://www.heise.de/select/ct/2019/5/softlinks/ysvw)
- [IP-Phone-Forum: AddPortMapping](https://www.ip-phone-forum.de/threads/tr-064-addportmapping-fritz-box-7490-113-07-01.302869/#post-2321834)
- [fbtr64toolbox](https://www.pack-eis.de/index.php?p=fbtr64toolbox)
