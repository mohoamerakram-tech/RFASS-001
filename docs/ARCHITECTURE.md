# System Architecture

This document details the technical architecture, network topology, persistence mechanisms, and extension rules for the **RFASS-001** self-hosted AI lab.

---

## 1. Design Objectives

1. **Low-Power Hardware Efficiency:** Repurpose an existing x86_64 machine (4 CPU threads, 8 GB RAM, no CUDA GPU) for 24/7 AI orchestration by delegating large language model inference to a remote OpenAI-compatible API.
2. **Zero Inbound Exposure:** Eliminate public ingress (no port forwarding, no reverse proxy, no dynamic DNS) by using Telegram long polling for chat interactions and Tailscale WireGuard for administrative SSH.
3. **Strict Execution Containment:** Confine autonomous agent code execution inside an unprivileged Docker container with explicit network egress restrictions against private LAN and Tailscale ranges.
4. **Unattended Reliability:** Ensure automatic recovery from crashes, network drops, reboots, and kernel freezes without manual intervention.

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
  - `/opt/ai-lab/hermes/workspace` -> `/workspace` (agent working directory for code and experiments)
- **Local API Endpoint:** `127.0.0.1:8642:8642` (loopback-only health and OpenAI-compatible gateway endpoint).
- **Resource Caps:** 4 GB memory limit, 3.0 CPU limit, JSON log rotation (`20m` x 3 files).

### 3.2 Remote Inference Layer
- **Protocol:** OpenAI-compatible HTTP API (`https://api.venice.ai/api/v1`).
- **Configuration:** Defined in `config.yaml` (`provider: "custom"`) with credentials loaded from `.env` (`OPENAI_API_KEY`, `OPENAI_BASE_URL`).
- **Billing Protection:** Inference-only API key with a prepaid credit balance and monthly spend limit.

### 3.3 Messaging Gateway
- **Transport:** Telegram Bot API via outbound long polling.
- **Access Control:** Strict default-deny caller allowlist (`TELEGRAM_ALLOWED_USERS`). Messages from unauthorized user IDs are dropped prior to LLM invocation.

### 3.4 Supporting Host Services
- **`tailscaled.service`:** Encrypted remote SSH access from authorized devices across arbitrary external networks.
- **`rembg.service`:** Local Python background-removal HTTP service bound strictly to `127.0.0.1:7000`.

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

---

## 5. Extending the Lab

When adding new AI services (e.g., SearXNG for private web search, Qdrant for vector memory, or workflow dashboards):
1. Deploy each service under `/opt/ai-lab/<service>/` via Docker Compose.
2. Attach containers to the external bridge network `ai-lab-net` (`172.28.0.0/24`) so they inherit LAN/Tailnet egress isolation automatically.
3. Never publish container ports on `0.0.0.0` (Docker bypasses UFW); bind strictly to `127.0.0.1` or the host's Tailscale interface IP.
4. Never mount `/var/run/docker.sock` into agent containers or switch agent containers to `network_mode: host`.
