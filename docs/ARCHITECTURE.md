# System Architecture

This document details the technical architecture, network topology, persistence mechanisms, and extension rules for the **RFASS-001** red team AI operations platform.

---

## 1. Design Objectives

1. **Low-Power Hardware Efficiency:** Repurpose an existing x86_64 machine (4 CPU threads, 8 GB RAM, no CUDA GPU) for 24/7 AI orchestration by delegating large language model inference to a remote OpenAI-compatible API.
2. **Zero Inbound Exposure:** Eliminate public ingress (no port forwarding, no reverse proxy, no dynamic DNS) by using Telegram long polling for chat interactions and Tailscale WireGuard for administrative SSH.
3. **Strict Execution Containment:** Confine autonomous agent code execution inside an unprivileged Docker container with explicit network egress restrictions against private LAN and Tailscale ranges.
4. **Unattended Reliability:** Ensure automatic recovery from crashes, network drops, reboots, and kernel freezes without manual intervention.
5. **Bounded Offensive Capability:** Make uncensored-model reasoning available to red team operators while structurally preventing the platform from becoming a lateral movement primitive — the agent has no route into the client network by construction, not by policy.

---

## 2. Target Host Baseline

| Component | Specification |
| :--- | :--- |
| Operating System | Debian GNU/Linux 13 (`trixie`, x86_64) |
| CPU | Intel Core i5-5300U (4 threads) |
| Memory / Swap | 7.6 GiB RAM / 7.9 GiB swap |
| Storage | 900 GB root filesystem |
| Container Runtime | Docker Engine 29.x + Docker Compose v5.x |
| Power Policy | `sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target` masked; `HandleLidSwitch=ignore` |
| Hardware Watchdog | `/dev/watchdog` enabled with 60-second timeout |

---

## 3. Component Breakdown

### 3.1 Hermes Agent Container (`hermes-agent`)
- **Image:** `nousresearch/hermes-agent:latest`
- **Supervision:** `s6-overlay` runs as PID 1 inside the container, remaps the internal `hermes` account to match the host's unprivileged `HERMES_UID`/`HERMES_GID`, and drops privileges via `s6-setuidgid` before launching `hermes gateway run`.
- **Storage Mounts:**
  - `/opt/ai-lab/hermes/data` -> `/opt/data` (configuration, `.env`, sessions, memories, skills, logs)
  - `/opt/ai-lab/hermes/workspace` -> `/workspace` (agent working directory for engagement artifacts)
- **Local API Endpoint:** `127.0.0.1:8642:8642` (loopback-only health and OpenAI-compatible gateway endpoint).
- **Resource Caps:** 4 GB memory limit, 3.0 CPU limit, JSON log rotation (`20m` x 3 files).

### 3.2 Remote Inference Layer
- **Protocol:** OpenAI-compatible HTTP API (`https://api.venice.ai/api/v1` by default).
- **Configuration:** Defined in `config.yaml` (`provider: "custom"`) with credentials loaded from `.env` (`OPENAI_API_KEY`, `OPENAI_BASE_URL`).
- **Model Profile:** Default profile targets a refusal-relaxed (`uncensored`) model so dual-use offensive-security questions receive technical answers. `OPENAI_BASE_URL` is operator-configurable and may point at a local model host when engagement material must not leave the machine.
- **Billing Protection:** Inference-only API key with a prepaid credit balance and monthly spend limit.

### 3.3 Messaging Gateway
- **Transport:** Telegram Bot API via outbound long polling.
- **Access Control:** Strict default-deny caller allowlist (`TELEGRAM_ALLOWED_USERS`). Messages from unauthorized user IDs are dropped prior to LLM invocation.
- **Role:** Operator chat channel for the red team session. Deliberately **not** usable as a C2 channel: allowlisted, outbound-only, and bound to loopback.

### 3.4 Supporting Host Services
- **`tailscaled.service`:** Encrypted remote SSH access from authorized devices across arbitrary external networks.
- **`rembg.service`:** Local Python background-removal HTTP service bound strictly to `127.0.0.1:7000` (image manipulation for lure and awareness-testing artifacts).

---

## 4. Persistence and Self-Healing

1. **Boot Ordering:** `docker.service` depends on `network-online.target`; `ai-lab-firewall.service` is bound to both `multi-user.target` and `docker.service` (`PartOf=docker.service`).
2. **Container & Process Recovery:** Docker `restart: unless-stopped` paired with internal `s6-overlay` process supervision.
3. **5-Minute Healthcheck (`ai-lab-healthcheck.timer`):**
   - Verifies that `DOCKER-USER` egress drop rules remain active and reapplies them if Docker restarted.
   - Restarts `hermes-agent` if it stopped unexpectedly.
   - Detects if Telegram was parked in a degraded state due to a temporary Wi-Fi outage at boot and automatically restarts the container once Telegram API connectivity is restored.
4. **Automated Daily Backups (`ai-lab-backup.timer`):**
   - Runs daily at 04:00, archiving `docker-compose.yml` and `data/` (excluding volatile caches and logs) into `/opt/ai-lab/backups/` with `0600` permissions and 7-day rolling retention.
   - `workspace/` is **not** in the daily archive by design: engagement artifacts follow the client's own retention rules and are archived deliberately (see [PLAYBOOK.md](PLAYBOOK.md) → *Teardown*).

---

## 5. Red Team Deployment Model

### 5.1 Workspace layout

The `/workspace` volume is the engagement evidence store, organized per engagement so that concurrent or sequential engagements stay separable.

```text
/workspace/
├── operator-system-prompt.md                 # Operator persona (see ../redteam/)
└── engagements/
    └── <client>-<id>/
        ├── roe.md                             # Scope, loaded before every operational question
        ├── 01-recon/                          # Collection artifacts, attack surface map
        ├── 03-access/                         # Access PoC, lure artifacts, detection notes
        ├── 04-post-ex/                        # Chain-of-attack notes, per-step telemetry
        └── 05-report/                         # Finding write-ups
```

### 5.2 Session composition

A red team session binds three things together:

| Element | Source | Role |
| :--- | :--- | :--- |
| Operator persona | `redteam/operator-system-prompt.md` | Defines the assistant's role, answer style, and scope contract |
| Engagement scope | `workspace/engagements/<id>/roe.md` | Defines what is in scope, what is refused, and stop conditions |
| Model profile | `config.yaml` / `hermes-ctl model` | Determines whether technique questions are answered at full depth |

The persona without a scope document has no boundary to enforce. The scope document without the persona has no enforcement mechanism. Both are required.

### 5.3 Model routing

Model profile is switched at runtime with `hermes-ctl model`. The pattern in practice: refusal-relaxed profile for technique reasoning and PoC drafting, tuned model for client-facing report prose. The container configuration does not change between profiles — only the selected model.

### 5.4 Containment as architecture

The container's isolation is the platform's primary security control, not an afterthought. See [SECURITY.md](SECURITY.md) → *Instructional vs. structural containment* for the full argument. In architectural terms:

- The agent has no route to the client network (`DOCKER-USER` DROP rules).
- The agent has no host filesystem reach beyond the two mounted volumes.
- The agent has no Docker socket, so it cannot start sibling containers.
- The agent has no inbound path, so it cannot be reached from the target side.

A full jailbreak of the model therefore yields an attacker a shell inside a scratch container with public-internet egress. That is the intended worst case, and it is the reason this platform can carry a refusal-relaxed model at all.

---

## 6. Extending the Lab

When adding new AI services (e.g., SearXNG for private web search, Qdrant for vector memory, or workflow dashboards):

1. Deploy each service under `/opt/ai-lab/<service>/` via Docker Compose.
2. Attach containers to the external bridge network `ai-lab-net` (`172.28.0.0/24`) so they inherit LAN/Tailnet egress isolation automatically.
3. Never publish container ports on `0.0.0.0` (Docker bypasses UFW); bind strictly to `127.0.0.1` or the host's Tailscale interface IP.
4. Never mount `/var/run/docker.sock` into agent containers or switch agent containers to `network_mode: host`.
5. Any service added to the lab inherits the LAN/tailnet egress restrictions — verify that a new service genuinely needs egress that the `DOCKER-USER` rules block before relaxing them.

### 6.1 Red team extension points

| Extension | Where | Constraint |
| :--- | :--- | :--- |
| Additional inference backend (local model host) | `OPENAI_BASE_URL` in `.env` | Must be reachable from the container; keep the client network blocked |
| Additional model profile | `hermes-ctl model` | Switching only; do not bake credentials into `config.yaml` |
| Persona variant | `redteam/operator-system-prompt.md` | Keep the scope block intact in every variant |
| Engagement tooling | `/workspace/engagements/<id>/` | Inert artifacts only; no live targeting from the lab |
| Detection pipeline integration | `workspace/engagements/<id>/` | Client-provided logs; store under the engagement's retention rules |

---

## 7. Related Documents

- [REDTEAM.md](REDTEAM.md) — operating model, roles, model routing, evidence handling.
- [PLAYBOOK.md](PLAYBOOK.md) — phase-by-phase engagement guidance.
- [ATTACK-MAPPING.md](ATTACK-MAPPING.md) — capability-to-ATT&CK mapping.
- [ROE-TEMPLATE.md](ROE-TEMPLATE.md) — scope template and authorization gate.
- [SECURITY.md](SECURITY.md) — threat model and containment controls.
