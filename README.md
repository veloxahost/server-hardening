# server-hardening

Opinionated, idempotent hardening for a fresh **Ubuntu 24.04** server (works on 22.04 and Debian 12). One script, readable configs, nothing hidden.

Companion to the guide: [The Complete Linux Server Hardening Checklist (2026)](https://veloxahost.com/blog/posts/linux-server-hardening-checklist.html?utm_source=github&utm_medium=referral&utm_campaign=server-hardening).

## What it does

- Creates a sudo user and installs your SSH key
- SSH: keys only, no root login, no passwords (drop-in config, validated with `sshd -t`)
- UFW: deny inbound, rate-limit SSH, allow 80/443
- fail2ban with the systemd backend
- Unattended security upgrades + `needrestart`
- auditd rules for identity files, sudoers, sshd config and root commands
- Kernel sysctl hardening (Docker-safe)
- Optional Lynis audit at the end

## Usage

Run as root on a **fresh** server, keeping your current SSH session open:

```bash
git clone https://github.com/veloxahost/server-hardening.git
cd server-hardening
sudo NEW_USER=deploy SSH_KEY="ssh-ed25519 AAAA... you@example.com" ./harden.sh
```

Options (environment variables):

| Var | Default | Meaning |
|---|---|---|
| `NEW_USER` | `deploy` | sudo user to create |
| `SSH_KEY` | *(required)* | public key for that user |
| `SSH_PORT` | `22` | SSH port to allow in UFW |
| `ALLOW_PORTS` | `80,443` | extra TCP ports to open |
| `ENABLE_IP_FORWARD` | `0` | set `1` on Docker hosts |
| `RUN_LYNIS` | `1` | run a Lynis audit at the end |

Before logging out, open a **new** terminal and confirm `ssh NEW_USER@server` works.

> On VeloxaHost shared IPv4, keep `SSH_PORT=22` — the first port of your block forwards to 22. Locked out? Use the browser terminal in the console.

## Files

- `harden.sh` — the script
- `configs/sshd-hardening.conf` → `/etc/ssh/sshd_config.d/99-hardening.conf`
- `configs/jail.local` → `/etc/fail2ban/jail.local`
- `configs/99-hardening.conf` → `/etc/sysctl.d/99-hardening.conf`
- `configs/hardening.rules` → `/etc/audit/rules.d/hardening.rules`

## License

MIT
