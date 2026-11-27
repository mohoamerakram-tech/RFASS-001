# RFASS-001: Self-Hosted Red Team AI Operations Platform

A hardened, reproducible, **red team operator platform** built on Debian 13, Docker Compose, Tailscale, UFW, `iptables` (`DOCKER-USER`), and systemd.

RFASS-001 turns a low-power, non-GPU host (8 GB RAM, x86_64) into a 24/7 **uncensored-AI-backed chatbot** for red team operators. An agent runs inside a strictly isolated, unprivileged container, is driven remotely over Telegram by an allowlisted operator, and reasons against a refusal-tuned inference endpoint so that offensive-security questions get technical answers instead of policy boilerplate — while every capability stays contained inside the lab boundary.

> **Authorized use only.** This platform is for engagements performed under a signed Rules of Engagement, or for personal research on systems you own. It ships with containment controls (no inbound exposure, egress filtering against LAN/tailnet, no host filesystem reach) precisely so that its capability cannot wander. See [docs/ROE-TEMPLATE.md](docs/ROE-TEMPLATE.md) and [docs/SECURITY.md](docs/SECURITY.md).

---

## Why an uncensored model for red team

Offensive-security work sits in a permanent grey zone that frontier consumer models refuse by default. A legitimate request — "show me how an APC-based execution chain differs from direct syscalls", "enumerate this binary's import table for evasion-relevant APIs" — is phrased indistinguishably from a request to weaponize the same technique against someone else. Frontier safety tuning cannot resolve that ambiguity, so it collapses to refusal.

That refusal is operationally costly during a live engagement: the operator needs the technical answer *now*, from a tool that cannot be sent to a third-party SaaS with client data attached.

RFASS-001 resolves that tension by combining two properties that are normally traded against each other:

1. **Capability** — a model with refusal tuning stripped or relaxed, so dual-use offensive questions are answered at full technical depth instead of being deflected to a safer topic.
2. **Containment** — the agent cannot reach anything it was not pointed at. It has no host filesystem, no Docker socket, no LAN or tailnet route, and no inbound path. It is an advisor that can write code into a scratch workspace, not a worm with a pivot.

The result is a chatbot that behaves like a senior offensive consultant — precise about syscalls, process injection, credential access, and evasion tradecraft — while remaining structurally unable to become a lateral movement primitive on its own.

**Model routing.** The default profile targets a refusal-relaxed model (`glm-5-3-flash-uncensored`) behind an OpenAI-compatible, privacy-oriented inference endpoint. Swap it per-task with `hermes-ctl model`: a tuned frontier model for report writing and client-facing prose, an uncensored model for technique reasoning and PoC drafting.

---

## Key Capabilities

- **Red Team Operator Chatbot:** An uncensored-AI agent (Nous Research Hermes Agent) inside a hardened, unprivileged Docker container (`no-new-privileges`, `cap_drop: ALL` with minimal `s6-overlay` capabilities, no Docker socket mount, CPU/RAM limits), driven by a red team operator over Telegram.
- **Offline-First Advisor:** Containered shell execution, local reasoning, and artifact generation in `/workspace` — the operator's scratch space for payload drafts, enumeration scripts, and detection-gap analysis, without touching the host OS.
- **Remote Privacy-First Inference:** Connects to an OpenAI-compatible inference endpoint so the host requires no local GPU or heavy VRAM footprint, and client engagement data is never routed through a consumer SaaS product.
- **Outbound-Only Chat Gateway:** Controlled 24/7 from Telegram using long polling with strict numeric user ID allowlisting (`TELEGRAM_ALLOWED_USERS`), eliminating the need for reverse proxies, dynamic DNS, or open router ports.
- **Defense-in-Depth Network Isolation:** Combines host-level UFW inbound filtering with persistent `DOCKER-USER` egress rules that block the AI lab Docker subnet (`172.28.0.0/24`) from reaching private LAN subnets (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`) and Tailscale peers (`100.64.0.0/10`) while preserving full public internet egress. **The agent cannot pivot into the target network.**
- **Zero-Trust Remote Administration:** Encrypted remote SSH access from anywhere via Tailscale without exposing SSH to the public internet.
- **Self-Healing and Persistence:** Combines Docker `restart: unless-stopped`, internal `s6-overlay` supervision, a 5-minute systemd healthcheck timer (firewall verification + Telegram outage auto-recovery), hardware watchdog, Docker log rotation, and automated daily backups with 7-day retention.
- **Engagement Hygiene:** Per-engagement scoping documents, an evidence chain for operator actions, and daily encrypted-permission archives of the engagement workspace.

---

## Red Team Operator Workflow

RFASS-001 is designed around the way a red team operator actually works: a scoped engagement, a sequence of phases, and a report at the end.

```text
   1. SCOPE            2. RECON            3. ACCESS           4. POST-EXPLOIT      5. REPORT
   ┌──────────────┐    ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
   │ ROE template │───▶│ OSINT        │────▶│ Initial      │────▶│ Priv-esc     │────▶│ Finding      │
   │ + client     │    │ enumeration  │     │ access       │     │ / persistence │     │ write-up     │
   │ context      │    │ + attack sur.│     │ techniques   │     │ / evasion    │     │ + ATT&CK    │
   │ injected     │    │ mapping      │     │ reasoning    │     │ reasoning    │     │ mapping      │
   └──────────────┘    └──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
          │                   │                    │                    │                    │
          └───────────────────┴────────────────────┴────────────────────┴────────────────────┘
                                   ▼
                        Hermes Agent (unprivileged, isolated)
                        uncensored model  ·  /workspace scratch
                                   ▼
                      Telegram (outbound long polling, allowlist)
```

- **Scope first.** Drop the engagement's ROE and client context into the workspace. The operator prompt binds the agent to that scope — see [redteam/operator-system-prompt.md](redteam/operator-system-prompt.md).
- **Reason with the model.** Ask technique-level questions, have it draft the PoC, argue the detection surface.
- **Keep evidence.** The workspace is backed up daily and retained 7 days; engagement artifacts stay out of version control.

Phase-by-phase guidance lives in [docs/PLAYBOOK.md](docs/PLAYBOOK.md), the capability-to-tactic mapping in [docs/ATTACK-MAPPING.md](docs/ATTACK-MAPPING.md), and the operating model in [docs/REDTEAM.md](docs/REDTEAM.md).

---

## Architecture Overview

```text
                   [ Red Team Operator (Phone / Laptop) ]
                     |                                |
       Telegram App  | (HTTPS / Long Polling)         | WireGuard VPN
                     v                                v
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
|  |   - Engagement scratch: /workspace/engagements/<client>-<id>/         |  |
|  |   - API/health bound strictly to 127.0.0.1:8642                      |  |
|  |   - Limits: 4 GB RAM, 3.0 CPUs                                       |  |
|  +----------------------------------------------------------------------+  |
|         |                                            |                     |
|         | ALLOWED: Public Internet                   | BLOCKED (DROP):     |
|         | (Inference API, Telegram, GitHub, PyPI)    | - 192.168.0.0/16    |
|         v                                            | - 10.0.0.0/8        |
|  [ Remote OpenAI-Compatible Inference API ]          | - 172.16.0.0/12     |
|  (refusal-relaxed / uncensored model profile)         | - 100.64.0.0/10     |
+----------------------------------------------------------------------------+
```

---

## Repository Structure

```text
RFASS-001/
├── README.md
├── .gitignore
├── docs/
│   ├── REDTEAM.md                     # Red team operating model and operator workflow
│   ├── PLAYBOOK.md                    # Engagement playbook: phase-by-phase operator guidance
│   ├── ATTACK-MAPPING.md              # Platform capability -> MITRE ATT&CK tactic mapping
│   ├── ROE-TEMPLATE.md                # Rules of Engagement template and authorization gate
│   ├── ARCHITECTURE.md                # Detailed system and network design
│   └── SECURITY.md                    # Threat model and hardening controls
├── redteam/
│   └── operator-system-prompt.md      # Operator persona system prompt and scoping contract
├── docker/
│   ├── docker-compose.yml            # Hardened Hermes Agent container stack
│   ├── daemon.json                   # Docker global log rotation policy
│   ├── config.yaml.example           # Model, persona, and terminal configuration template
│   └── .env.example                  # Secrets, allowlist, and engagement scope template
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

### 6. Bind the Engagement
Copy the operator persona and load the engagement context into the scratch workspace:

```bash
cp redteam/operator-system-prompt.md /opt/ai-lab/hermes/workspace/
mkdir -p /opt/ai-lab/hermes/workspace/engagements/<client>-<id>
cp docs/ROE-TEMPLATE.md /opt/ai-lab/hermes/workspace/engagements/<client>-<id>/roe.md
```

Fill in the scope, then point the agent's persona at it (see [docs/REDTEAM.md](docs/REDTEAM.md) → *Binding the engagement*).

---

## Operational Commands

| Command | Description |
| :--- | :--- |
| `hermes-ctl up` | Start the Hermes gateway container in detached mode |
| `hermes-ctl down` | Stop and remove the container while keeping persistent data |
| `hermes-ctl restart` | Restart the container after modifying `.env` or `config.yaml` |
| `hermes-ctl status` | Show container status and port bindings |
| `hermes-ctl logs` | Follow container stdout/stderr |
| `hermes-ctl model` | Interactively switch inference models (tuned vs. uncensored profiles) |
| `hermes-ctl shell` | Open a bash shell inside the container as the unprivileged user |
| `hermes-ctl update` | Pull the latest image and recreate the container |

---

## Documentation

- [docs/REDTEAM.md](docs/REDTEAM.md) — Operating model: operator roles, engagement phases, uncensored model routing, evidence handling.
- [docs/PLAYBOOK.md](docs/PLAYBOOK.md) — Engagement playbook: phase-by-phase red team workflow with ATT&CK references.
- [docs/ATTACK-MAPPING.md](docs/ATTACK-MAPPING.md) — Which platform capability supports which ATT&CK tactic, and where the seams are.
- [docs/ROE-TEMPLATE.md](docs/ROE-TEMPLATE.md) — Rules of Engagement template and the authorization gate to run before an engagement.
- [redteam/operator-system-prompt.md](redteam/operator-system-prompt.md) — The operator persona system prompt and its scoping contract.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Hardware baseline, network design, service layout, and extension guidelines.
- [docs/SECURITY.md](docs/SECURITY.md) — Threat model, container hardening, egress filtering, and credential management.

---

## Author

**Akram Moho Amer** — Cybersecurity engineering student (ENSA El Jadida), offensive security and Windows internals.
Red team focused: EDR/AV detection-surface research, direct syscalls, APC execution chains, PE/COFF analysis, and detection engineering.

- GitHub — [github.com/mohoamerakram-tech](https://github.com/mohoamerakram-tech)
- LinkedIn — [linkedin.com/in/akram-moho-amer-a3975b2a6](https://www.linkedin.com/in/akram-moho-amer-a3975b2a6)
- TryHackMe — [tryhackme.com/p/DOCENDUS](https://tryhackme.com/p/DOCENDUS)
- Related project — [ECHOSEEK](https://github.com/mohoamerakram-tech/ECHOSEEK): public, non-operational showcase of authorized Windows endpoint security research.

## License

Released for authorized security research and educational use. See [docs/SECURITY.md](docs/SECURITY.md) for the operating constraints this platform enforces.
