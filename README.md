# RFASS-001: Self-Hosted Isolated AI Agent Infrastructure

A hardened, reproducible, self-hosted AI agent infrastructure built on Debian 13, Docker Compose, Tailscale, UFW, `iptables` (`DOCKER-USER`), and systemd.

Designed to repurpose low-power, non-GPU hardware (8 GB RAM, x86_64) into a 24/7 autonomous AI lab by offloading LLM inference to a privacy-focused OpenAI-compatible remote API while running a strictly isolated, container-confined agent orchestrated remotely via Telegram.

---

## Key Capabilities

- **Containerized Autonomous Agent:** Runs Nous Research Hermes Agent inside a hardened, unprivileged Docker container (`no-new-privileges`, `cap_drop: ALL` with minimal `s6-overlay` capabilities, no Docker socket mount, CPU/RAM limits).
- **Remote Privacy-First Inference:** Connects to an OpenAI-compatible inference endpoint (Venice.ai) so the host requires no local GPU or heavy VRAM footprint.
- **Outbound-Only Chat Gateway:** Controlled 24/7 from Telegram using long polling with strict numeric user ID allowlisting (`TELEGRAM_ALLOWED_USERS`), eliminating the need for reverse proxies, dynamic DNS, or open router ports.
- **Defense-in-Depth Network Isolation:** Combines host-level UFW inbound filtering with persistent `DOCKER-USER` egress rules that block the AI lab Docker subnet (`172.28.0.0/24`) from reaching private LAN subnets (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`) and Tailscale peers (`100.64.0.0/10`) while preserving full public internet egress.
- **Zero-Trust Remote Administration:** Encrypted remote SSH access from anywhere via Tailscale without exposing SSH to the public internet.
- **Self-Healing and Persistence:** Combines Docker `restart: unless-stopped`, internal `s6-overlay` supervision, a 5-minute systemd healthcheck timer (firewall verification + Telegram outage auto-recovery), hardware watchdog, Docker log rotation, and automated daily backups with 7-day retention.

---

## Architecture Overview

```text
                   [ Remote Operator (Phone / Laptop) ]
                     |                              |
       Telegram App  | (HTTPS / Long Polling)       | WireGuard VPN
                     v                              v
+----------------------------------------------------------------------------+
|  Debian 13 Host                                                            |
|  Host Firewall (UFW): DENY INCOMING except tailscale0, 41641/udp, LAN SSH  |
|                                                                            |
|  Host Services:                                                            |
|   - sshd (key-based authentication)                                        |
|   - tailscaled (encrypted remote administration)                           |
|   - dockerd / containerd (20 MB x 3 JSON log rotation)                     |
|   - rembg.service (127.0.0.1:7000, localhost-only background removal API)  |
|   - ai-lab-firewall.service (persistent DOCKER-USER egress rules)          |
|   - ai-lab-healthcheck.timer (5-min firewall & Telegram auto-recovery)     |
|   - ai-lab-backup.timer (daily 04:00 encrypted-permission archives)        |
|                                                                            |
|  +----------------------------------------------------------------------+  |
|  |  Isolated Bridge Network: ai-lab-net (172.28.0.0/24)                 |  |
|  |  Explicit DNS: 1.1.1.1, 9.9.9.9                                      |  |
|  |                                                                      |  |
|  |  [ hermes-agent ]  (nousresearch/hermes-agent:latest)                |  |
|  |   - Unprivileged UID/GID (no sudo, no docker group)                  |  |
|  |   - Persistent volumes: data -> /opt/data, workspace -> /workspace   |  |
|  |   - API/health bound strictly to 127.0.0.1:8642                      |  |
|  |   - Limits: 4 GB RAM, 3.0 CPUs                                       |  |
|  +----------------------------------------------------------------------+  |
|         |                                            |                     |
|         | ALLOWED: Public Internet                   | BLOCKED (DROP):     |
|         | (Inference API, Telegram, GitHub, PyPI)    | - 192.168.0.0/16    |
|         v                                            | - 10.0.0.0/8        |
|  [ Remote OpenAI-Compatible Inference API ]          | - 172.16.0.0/12     |
|                                                      | - 100.64.0.0/10     |
+----------------------------------------------------------------------------+
```

---

## Repository Structure

```text
RFASS-001/
├── README.md
├── .gitignore
├── docs/
│   ├── ARCHITECTURE.md               # Detailed system and network design
│   └── SECURITY.md                   # Threat model and hardening controls
├── docker/
│   ├── docker-compose.yml            # Hardened Hermes Agent container stack
│   ├── daemon.json                   # Docker global log rotation policy
│   ├── config.yaml.example           # Model and terminal configuration template
│   └── .env.example                  # Secrets and allowlist template
├── scripts/
│   ├── hermes-ctl                    # CLI wrapper for lifecycle management
│   ├── ai-lab-net-isolate.sh         # Idempotent DOCKER-USER isolation script
│   ├── ai-lab-healthcheck.sh         # 5-minute self-healing healthcheck
│   └── ai-lab-backup.sh              # Daily backup script with 7-day retention
└── systemd/
    ├── ai-lab-firewall.service       # Boot and Docker-restart isolation unit
    ├── ai-lab-healthcheck.service    # Healthcheck execution unit
    ├── ai-lab-healthcheck.timer      # 5-minute healthcheck schedule
    ├── ai-lab-backup.service         # Backup execution unit
    ├── ai-lab-backup.timer           # Daily 04:00 backup schedule
    └── rembg.service                 # Localhost-only rembg HTTP service
```

---

## Quick Start Deployment (Debian 13)

### 1. Prerequisites
Install Docker Engine, Docker Compose plugin, UFW, Tailscale, and create a dedicated unprivileged system user for Hermes:

```bash
useradd --system --user-group --no-create-home --shell /usr/sbin/nologin hermes
id hermes  # Note UID/GID and update HERMES_UID / HERMES_GID in docker-compose.yml
```

### 2. Provision Directories and Configuration
```bash
mkdir -p /opt/ai-lab/hermes/{data,workspace}
cp docker/docker-compose.yml /opt/ai-lab/hermes/docker-compose.yml
cp docker/config.yaml.example /opt/ai-lab/hermes/data/config.yaml
cp docker/.env.example /opt/ai-lab/hermes/data/.env
cp docker/daemon.json /etc/docker/daemon.json

# Populate OPENAI_API_KEY, TELEGRAM_BOT_TOKEN, and TELEGRAM_ALLOWED_USERS
nano /opt/ai-lab/hermes/data/.env

chown -R hermes:hermes /opt/ai-lab/hermes/{data,workspace}
chmod 700 /opt/ai-lab/hermes/data
chmod 600 /opt/ai-lab/hermes/data/.env
```

### 3. Install Scripts and Systemd Units
```bash
install -m 755 scripts/hermes-ctl /usr/local/bin/hermes-ctl
install -m 755 scripts/ai-lab-net-isolate.sh /usr/local/sbin/ai-lab-net-isolate.sh
install -m 755 scripts/ai-lab-healthcheck.sh /usr/local/sbin/ai-lab-healthcheck.sh
install -m 755 scripts/ai-lab-backup.sh /usr/local/sbin/ai-lab-backup.sh

cp systemd/ai-lab-*.service systemd/ai-lab-*.timer /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now ai-lab-firewall.service ai-lab-healthcheck.timer ai-lab-backup.timer
```

### 4. Configure Host Firewall (UFW)
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0 comment 'Tailscale interface'
ufw allow 41641/udp comment 'Tailscale WireGuard'
ufw allow from 192.168.1.0/24 to any port 22 proto tcp comment 'SSH from LAN'
ufw --force enable
```

### 5. Launch the Agent
```bash
hermes-ctl up
hermes-ctl status
tail -f /opt/ai-lab/hermes/data/logs/gateway.log
```

---

## Operational Commands

| Command | Description |
| :--- | :--- |
| `hermes-ctl up` | Start the Hermes gateway container in detached mode |
| `hermes-ctl down` | Stop and remove the container while keeping persistent data |
| `hermes-ctl restart` | Restart the container after modifying `.env` or `config.yaml` |
| `hermes-ctl status` | Show container status and port bindings |
| `hermes-ctl logs` | Follow container stdout/stderr |
| `hermes-ctl model` | Interactively switch inference models |
| `hermes-ctl shell` | Open a bash shell inside the container as the unprivileged user |
| `hermes-ctl update` | Pull the latest image and recreate the container |

---

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Hardware baseline, network design, service layout, and extension guidelines.
- [docs/SECURITY.md](docs/SECURITY.md) — Threat model, container hardening, egress filtering, and credential management.
