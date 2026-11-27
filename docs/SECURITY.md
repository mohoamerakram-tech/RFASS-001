# Security Model

Autonomous AI agents with shell execution capabilities introduce distinct operational risks, including accidental destructive commands, prompt injection from untrusted web content, and lateral movement across home or corporate networks. **RFASS-001** addresses these risks through layered defense-in-depth controls.

RFASS-001 adds a second risk class on top of the standard autonomous-agent profile: it deliberately runs a **refusal-relaxed model**, so it will answer offensive-security questions that a guarded model would deflect. That capability is the product; it also means the containment controls below are load-bearing rather than decorative.

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
| **Prompt jailbreak of the refusal-relaxed model** | Structural containment is the primary control (below): a full jailbreak yields a shell in a scratch container with no host, LAN, tailnet, or inbound reach. Instructional scope enforcement in the operator persona is the secondary layer. |
| **Agent used as a pivot into the client network** | `DOCKER-USER` DROP rules for RFC 1918 and CGNAT ranges are enforced by `ai-lab-net-isolate.sh` and re-verified every 5 minutes by `ai-lab-healthcheck.timer`. Reapplied automatically after a Docker restart. |
| **Engagement scope exceeded via the model** | ROE document loaded into the session, referenced by the operator persona's scope block, with a stop-conditions section that the operator enforces. |
| **Client data leaking to a third-party endpoint** | Inference endpoint is operator-configurable via `OPENAI_BASE_URL`; point it at a local model host when engagement material must not leave the machine. Per-engagement data-handling rules live in [ROE-TEMPLATE.md](ROE-TEMPLATE.md) → *Data handling*. |
| **Engagement artifacts leaking into version control** | `.gitignore` excludes `workspace/`, `data/`, `backups/`, `*.log`; backups written `0600` into a `0700` directory with 7-day retention. |
| **AI lab platform repurposed as C2** | The Telegram gateway is allowlisted, outbound-only long polling with no listener on the target side; the agent API binds to `127.0.0.1:8642`. There is no inbound channel for a target to connect to. |

---

## 2. Instructional vs. Structural Containment

The platform's core security claim needs to be stated precisely, because it is easy to overstate.

| Layer | Mechanism | Strength |
| :--- | :--- | :--- |
| **Structural (primary)** | Container isolation: no host filesystem reach, no Docker socket, no LAN/tailnet route, no inbound path | Holds regardless of what the model says or is persuaded to do |
| **Instructional (secondary)** | Operator persona scope block + loaded ROE document | Holds against normal misuse; not a security boundary against a determined adversary |

The platform is designed so that a full jailbreak is survivable. If the model is completely persuaded to behave as an unrestricted offensive agent, the result is an agent with a shell in `/workspace` and public-internet egress — a scratch container, with no path to any client system and no path for any client system to reach it.

This ordering matters. **Instruction alone is not a security control**, so the containment is structural and the prompt is a usability and governance layer on top of it.

---

## 3. Container Capability Policy

Inside `docker/docker-compose.yml`, all Linux capabilities are dropped (`cap_drop: [ALL]`) and only the minimal subset required by `s6-overlay` for startup UID remapping, privilege dropping, and clean signal teardown is retained:

- `CHOWN`, `DAC_OVERRIDE`, `FOWNER` — data volume ownership alignment at container init.
- `SETUID`, `SETGID` — privilege drop from init PID 1 to the unprivileged `hermes` user via `s6-setuidgid`.
- `KILL` — clean signal propagation from `s6` to child processes during shutdown.

All elevated capabilities (`NET_RAW`, `SYS_ADMIN`, `SYS_PTRACE`, `NET_ADMIN`, etc.) remain dropped, and `no-new-privileges:true` prevents privilege escalation via setuid binaries.

---

## 4. Egress Firewall Verification

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

> **Red team note.** These DROP rules are the reason the agent cannot pivot into a client network. They are a containment decision, not an infrastructure gap — see [ATTACK-MAPPING.md](ATTACK-MAPPING.md) → *Lateral Movement*. Do not relax them to add reach; add a deliberately scoped path through a separate, authorized position instead.

---

## 5. Red Team Operational Controls

| Control | Implementation |
| :--- | :--- |
| Operator authorization | `TELEGRAM_ALLOWED_USERS` numeric allowlist, default-deny, enforced before LLM invocation |
| Engagement scoping | `roe.md` per engagement, loaded into the session, referenced by the operator persona's scope block |
| Stop conditions | Defined in the ROE template; enforced by the operator, restated by the model at engagement start |
| Evidence retention | Daily backups `0600` in a `0700` directory, 7-day rolling retention; `workspace/` archived deliberately per engagement |
| Artifact version control hygiene | `workspace/`, `data/`, `backups/`, `*.log` excluded via `.gitignore` |
| Inference endpoint control | `OPENAI_BASE_URL` operator-configurable; local model host supported for engagement work |
| Spend control | Prepaid credits, monthly cap, auto top-up disabled, inference-only key |
| Report integrity | The operator persona requires the model to state when something is untested and to never fabricate results or evidence |

---

## 6. Known Residual Risks

Stated rather than omitted.

| Risk | Why it remains | Mitigation |
| :--- | :--- | :--- |
| Prompt jailbreak | A refusal-relaxed model can be talked into unusual behavior | Structural containment (§2) — the blast radius is one scratch container |
| Scope misread by the model | Natural-language scope parsing is imperfect | Operator verifies the model's restatement against `roe.md` before any operational question ([PLAYBOOK.md](PLAYBOOK.md) → *Phase 1*) |
| Engagement data transits a third party | Default inference endpoint is remote | Point `OPENAI_BASE_URL` at a local host; keep identifying data out of prompts |
| Shared workspace across operators | One workspace serves all allowlisted operators | One engagement per workspace; archive and clean between engagements |
| No target-network validation from the lab | Container cannot reach the client network by design | Validate in an isolated mirror or on a dedicated test range |
| Single host, no redundancy | One Debian host carries the whole platform | Hardware watchdog, `restart: unless-stopped`, systemd timers, daily backups |

---

## 7. Reporting a Vulnerability

If you find a security issue in RFASS-001 itself, report it privately to the maintainer rather than opening a public issue. The containment controls in this document are the thing worth attacking: an escape from the container, a bypass of the `DOCKER-USER` rules, or a way to reach the host from inside the agent container is a genuine finding.

---

## 8. Related Documents

- [REDTEAM.md](REDTEAM.md) — operating model and model routing.
- [PLAYBOOK.md](PLAYBOOK.md) — engagement workflow.
- [ATTACK-MAPPING.md](ATTACK-MAPPING.md) — capability-to-ATT&CK mapping and deliberate gaps.
- [ROE-TEMPLATE.md](ROE-TEMPLATE.md) — scope template and authorization gate.
- [ARCHITECTURE.md](ARCHITECTURE.md) — system and network design.
