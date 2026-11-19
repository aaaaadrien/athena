# Athena : Lightweight SSH Protection (nftables)

Athena is an ultra-lightweight security daemon designed to protect your server against SSH brute-force attacks. It reads the systemd journal, counts authentication failures per source address and blocks the offenders with **nftables**, over IPv4 and IPv6.

## Features
- **Ultra-lightweight**: about **7 MB of RAM**, and no CPU when nothing happens — the journal is followed in a stream, not rescanned on a timer.
- **Modern**: uses `nftables` (the replacement for iptables) in a single `inet` table, with one set per address family.
- **Persistent**: bans are stored with their absolute expiry, so a service restart or a reboot restores the exact remaining time.
- **Safe by default**: whitelist with CIDR support (IPv4 and IPv6), and a manual unban is honoured for a full finding window instead of being undone by the next scan.

## Requirements
- systemd with `journalctl` (Athena reads the journal directly; if journald is configured with `Storage=volatile`, bans cannot be rebuilt from the journal once — see *Upgrading* below).
- `nftables` >= 0.9 (`nft get element`, `timeout` sets).
- `bash` >= 4.3, `flock` (util-linux).

## Project Structure
- `athena-server`: The main daemon that monitors logs and manages the firewall.
- `athena`: The CLI tool to list bans and manually unban an IP.
- `athena.conf`: Centralized configuration file.
- `athena.service`: Systemd unit for service management.
- `VERSION`: single source of the version number, printed by both binaries.
- `Makefile`: installation, uninstallation, and test targets.
- `tests/`: unit tests and end-to-end tests (they run in a private network namespace).

### Installed files
| Path | Content |
|---|---|
| `/usr/bin/athena-server`, `/usr/bin/athena` | daemon and client |
| `/usr/share/athena/VERSION` | version string |
| `/etc/athena/athena.conf` | configuration (kept on upgrade) |
| `/etc/systemd/system/athena.service` | systemd unit |
| `/run/athena/unban_queue` | unban requests, runtime only |
| `/var/lib/athena/bans` | ban state: one `<address> <expiry epoch>` per line |

## Configuration (`/etc/athena/athena.conf`)
You can adjust Athena’s behavior:
- `THRESHOLD`: Number of allowed failures before a ban (default: 2).
- `BAN_TIME`: Ban duration in seconds (default: 3600s / 1h). Must stay >= `FIND_TIME`.
- `FIND_TIME`: Window for searching for failures in the logs (default: 600s / 10min).
- `CHECK_INTERVAL`: How often the daemon wakes up to process unban requests and prune its state (default: 5s).
- `WHITE_LIST`: IPv4/IPv6 addresses or CIDRs that should never be banned.
- `SSH_LOG_TAGS`: journald identifiers carrying sshd messages. `OpenSSH >= 9.8` logs through `sshd-session`, older releases through `sshd`; both are matched by default.
- `PORT_BLOCK`: Ports to block (“all” or a comma-separated list, e.g., “22,80,443”, applied to TCP and UDP).

The daemon validates its configuration at startup and refuses to run with a non-numeric value; a `BAN_TIME` smaller than `FIND_TIME` is reported as a warning in the journal.

## Installation & Uninstallation

### Installation
The project includes a Makefile to simplify deployment on Linux:
```bash
sudo make install
```
*This command installs the binaries in `/usr/bin`, the version file in `/usr/share/athena`, the configuration in `/etc/athena`, the state directory in `/var/lib/athena`, and enables and starts the systemd service. An existing `athena.conf` is never overwritten.*

For packaging, `make install DESTDIR=/some/stage` stages the files and skips `systemctl`.

### Uninstallation
To cleanly remove Athena and clear the firewall rules:
```bash
sudo make uninstall
```

### Upgrading from 1.0
Nothing to do: the first start of 1.1 finds no state file, rebuilds the active bans from the journal once (as 1.0 did on every start), and writes `/var/lib/athena/bans` from then on. Bans already in the kernel are kept.

## Using the `athena` client
Once installed, use the `athena` command:
- **List active bans**: `athena -l`
- **Unban an IP**: `athena -u 203.0.113.245`

```text
$ athena -l
--- Athena : adresses bannies ---
  198.51.100.7                            1m04s
  203.0.113.5                             59m58s
  2001:db8::66                            1h59m59s
Total : 3 adresse(s) bannie(s).
```

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
Jun 02 17:01:02 SSH222 athena[1161900]: [RESTORE] 198.51.100.237 (1790s remaining)
Jun 02 17:01:02 SSH222 athena[1161900]: [WARN] journal stream ended, reconnecting
```
Every event and warning is written to the journal with the `athena` tag, so `journalctl -t athena -f` is the single place to look; fatal startup errors are also printed to stderr, where `journalctl -u athena` picks them up.

## Measured footprint
```text
● athena.service - Athena Security Daemon (SSH brute-force blocker)
   Active: active (running) since Sat 2026-11-14 14:19:07 CET; 4 days ago
   Memory: 7.1M (peak: 14.9M)
```
CPU: version 1.0 rescanned the journal every `CHECK_INTERVAL`, which cost about 6 ms per cycle (opening a 212 MB journal dominates, `--since` or `--after-cursor` alike) and had accumulated 24 minutes of CPU in 4 days for zero bans. The daemon now follows the journal once: a 20-cycle benchmark goes from 34 to 4 jiffies, and an idle cycle does no `fork` at all.

## Tests
```bash
make check        # ShellCheck + unit tests (no root, no nftables)
make integration  # end-to-end tests: real nftables in a private network namespace
```
The integration suite drives the real daemon with a stub journal: banning, threshold, whitelist (IPv4 and IPv6), manual unban, state restore across a restart, expired-state pruning, and the CLI. It re-execs itself in `unshare --net`, so it never touches the host firewall. CI runs the three commands on every push and pull request.

## Troubleshooting
- **Nothing is ever banned**: check that the daemon sees failures:
  `journalctl -t sshd -n 5` and `journalctl -t sshd-session -n 5`. If your OpenSSH is older than 9.8, only `sshd` exists; if it is newer, only `sshd-session` is used. `SSH_LOG_TAGS` lists both by default.
- **`athena -u` says the address is not banned**: the ban may have expired on its own (`athena -l` shows the remaining time).
- **Bans disappear after a reboot**: check that the unit has write access to `/var/lib/athena` (`systemctl status athena`) — the state file is what restores them.
