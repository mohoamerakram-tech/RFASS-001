# Security Model

Autonomous AI agents with shell execution capabilities introduce distinct operational risks, including accidental destructive commands, prompt injection from untrusted web content, and lateral movement across home or corporate networks. **RFASS-001** addresses these risks through layered defense-in-depth controls.

---

## 1. Threat Model

| Threat | Mitigation Implemented |
| :--- | :--- |
| Unauthorized user commanding the Telegram bot | Strict `TELEGRAM_ALLOWED_USERS` numeric allowlist; requests from non-allowlisted IDs are dropped before reaching the LLM. |
| Agent modifying host OS or escalating privileges | Dedicated non-root `hermes` user (`nologin`, no `sudo`, no `docker` group); container runs with `no-new-privileges:true`, `cap_drop: ALL`, and no Docker socket mount. |
| Lateral movement into home LAN or Tailscale devices | Persistent `DOCKER-USER` `iptables` rules drop all new outbound connections from `172.28.0.0/24` to `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`, and `100.64.0.0/10`. |
| Docker bypassing host UFW rules | No container ports bound to `0.0.0.0`; internal gateway API bound strictly to `127.0.0.1:8642`. Host `rembg` service bound strictly to `127.0.0.1:7000`. |
| Inbound network attacks | UFW set to `default deny incoming`; only Tailscale (`tailscale0`, `41641/udp`) and local LAN SSH (`22/tcp`) are permitted. Zero router port forwarding. |
| Runaway API spend | Inference-only remote API key with prepaid credits, monthly USD spend cap, and auto top-up disabled. |
| Disk exhaustion from logs | Docker JSON log rotation capped at 20 MB per file, maximum 3 files (`60 MB` total per container). |
| Secret exposure | Live credentials stored only in `/opt/ai-lab/hermes/data/.env` (`chmod 600`, directory `chmod 700`), excluded from version control via `.gitignore`. |

---

## 2. Container Capability Policy

Inside `docker/docker-compose.yml`, all Linux capabilities are dropped (`cap_drop: [ALL]`) and only the minimal subset required by `s6-overlay` for startup UID remapping, privilege dropping, and clean signal teardown is retained:

- `CHOWN`, `DAC_OVERRIDE`, `FOWNER` — data volume ownership alignment at container init.
- `SETUID`, `SETGID` — privilege drop from init PID 1 to the unprivileged `hermes` user via `s6-setuidgid`.
- `KILL` — clean signal propagation from `s6` to child processes during shutdown.

All elevated capabilities (`NET_RAW`, `SYS_ADMIN`, `SYS_PTRACE`, `NET_ADMIN`, etc.) remain dropped, and `no-new-privileges:true` prevents privilege escalation via setuid binaries.

---

## 3. Egress Firewall Verification

Container egress isolation is enforced by `scripts/ai-lab-net-isolate.sh` in the `DOCKER-USER` chain:

1. `ACCEPT` `ESTABLISHED,RELATED` traffic (permits return packets for localhost-bound health/API calls).
2. `ACCEPT` traffic where both source and destination belong to `172.28.0.0/24` (intra-lab container communication).
3. `DROP` traffic from `172.28.0.0/24` destined for RFC 1918 private ranges (`192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`) and CGNAT/Tailscale (`100.64.0.0/10`).
4. Permit remaining public internet destinations (using explicit container DNS `1.1.1.1` and `9.9.9.9`).

To verify isolation from inside the running container:

```bash
# Public APIs must succeed
curl -s -o /dev/null -w "%{http_code}\n" https://api.venice.ai/api/v1/models
curl -s -o /dev/null -w "%{http_code}\n" https://api.telegram.org

# Private LAN and Tailscale endpoints must time out (000)
curl -s -o /dev/null -w "%{http_code}\n" --max-time 3 http://192.168.1.1
```
