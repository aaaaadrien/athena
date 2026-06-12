# Athena : Lightweight SSH Protection (nftables)

Athena is an ultra-lightweight security daemon designed to protect your server against SSH brute-force attacks. It monitors system logs in real time and automatically blocks suspicious IP addresses via **nftables**.

## Features
- **Ultra-lightweight**: Uses less than **8 MB of RAM** and virtually **0% CPU**.
- **Modern**: Uses `nftables` (the replacement for iptables) for optimal performance.
- **Persistent**: Restores active bans even after the service is restarted.

## Project Structure
- `athena-server`: The main daemon that monitors logs and manages the firewall.
- `athena`: The CLI tool to list bans and manually unban an IP.
- `athena.conf`: Centralized configuration file.
- `athena.service`: Systemd unit for service management.
- `Makefile`: Automated installation and uninstallation script.

## Configuration (`/etc/athena/athena.conf`)
You can adjust Athena’s behavior:
- `THRESHOLD`: Number of allowed failures before a ban (default: 2).
- `BAN_TIME`: Ban duration in seconds (default: 3600s / 1h).
- `FIND_TIME`: Window for searching for failures in the logs (default: 600s / 10min).
- `CHECK_INTERVAL`: Server check frequency (default: 5s).
- `WHITE_LIST`: List of IPs or CIDRs that should never be banned.
- `PORT_BLOCK`: Ports to block (“all” or a comma-separated list, e.g., “22,80,443”).


## Installation & Uninstallation

### Installation
The project includes a Makefile to simplify deployment on Linux:
```bash
sudo make install
```
*This command installs the binaries in `/usr/bin`, the configuration in `/etc/athena`, and starts the systemd service.*

### Uninstallation
To cleanly remove Athena and clear the firewall rules:
```bash
sudo make uninstall
```

## Using the `athena` client
Once installed, use the `athena` command:
- **List active bans**: `athena -l`
- **Unban an IP**: `athena -u 203.0.113.245`


## Activity Monitoring
To monitor Athena's activity in real time (bans, restores, unbans):
```bash
journalctl -t athena -f
```

```text
-- Logs begin at Fri 2026-05-22 19:58:09 CEST. --
Jun 02 15:39:21 SSH222 athena[1154894]: [BAN] 203.0.113.149 (for 3600s)
Jun 02 15:59:59 SSH222 athena[1157363]: [BAN] 198.51.100.237 (for 3600s)
Jun 02 16:00:59 SSH222 athena[1157511]: [BAN] 192.0.2.49 (for 3600s)
Jun 02 16:33:17 SSH222 athena[1161509]: [BAN] 203.0.113.107 (for 3600s)
Jun 02 16:33:32 SSH222 athena[1161553]: [BAN] 198.51.100.179 (for 3600s)
Jun 02 16:33:35 SSH222 athena[1161574]: [UNBAN] 203.0.113.245 (Manual)
```


## Usage statistics for May 2026
```bash
ls -lh --color=no /usr/bin/athena*
```
```text
-rwxr-xr-x 1 root root 2.1K May 27 18:36 /usr/bin/athena
-rwxr-xr-x 1 root root 6.5K May 27 18:36 /usr/bin/athena-server
```
```bash
systemctl status athena.service | grep --color=no -E ‘Athena|Active|Memory’ 
```
```text
● athena.service - Athena Security Daemon
   Active: active (running) since Wed 2026-05-27 18:36:08 CEST; 5 days ago
   Memory: 7.5M
```

