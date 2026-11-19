# Changelog

All notable changes to Athena are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/), and the
project adheres to [Semantic Versioning](https://semver.org/).

## [1.1.0] - unreleased

### Added
- IPv6 support: offenders are banned in a dedicated `athena_blacklist6` set,
  with the same port policy as IPv4 (`PORT_BLOCK`).
- IPv6 addresses and prefixes in `WHITE_LIST`.
- `SSH_LOG_TAGS` configuration key: journald identifiers carrying sshd
  messages (`sshd sshd-session` by default).
- Ban state persisted in `/var/lib/athena/bans` with an absolute expiry, so a
  restart or a reboot restores the exact remaining time.
- Unit tests, end-to-end tests (real nftables in a private network namespace)
  and a CI workflow.
- `VERSION` file as the single source of the version string.
- `make check`, `make unit`, `make integration`, `DESTDIR` support.

### Changed
- The daemon follows the journal in a stream instead of rescanning the last
  `FIND_TIME` seconds on every cycle: no `journalctl` call, hence no fork, on
  an idle cycle.
- `athena -l` prints a readable remaining time and covers both address
  families; `athena -u` validates the address and reports an address that is
  not banned.
- The systemd unit gains `RuntimeDirectory`/`StateDirectory` and a set of
  sandboxing options (`ProtectSystem`, `ProtectHome`, `PrivateTmp`,
  `NoNewPrivileges`).
- The shipped configuration whitelists loopback, RFC1918 and link-local IPv6
  instead of a single /24 that does not match the host network.

### Fixed
- No ban at all on hosts where sshd logs through `sshd` (OpenSSH < 9.8,
  i.e. Debian <= 12, Ubuntu <= 24.04, AlmaLinux): only `sshd-session` was
  queried.
- A source address was read as its port number when the journal line carried
  a method suffix (`ssh2: RSA SHA256:...`).
- An offender could escape banning when another address shared its prefix:
  the "already banned" test was a substring match, so `10.0.0.1` was seen as
  banned as soon as `10.0.0.10` was in the set.
- A manual unban was reverted by the next scan, about five seconds later,
  because the failures that caused the ban were still inside `FIND_TIME`.
- Restored bans were given a full `BAN_TIME` again instead of their remaining
  time, extending them by up to twice the configured duration.
- `[BAN]` lines were logged before `nft` had accepted the element.
- An unban request could be lost when it was appended between the queue read
  and its truncation.
- `nft add table`/`add set` errors on restart were printed to the journal on
  every start; they are now silent no-ops.
- `port` blocking rules were built by word-splitting an unquoted variable.

## [1.0] - 2026-06-23
- Initial release.
