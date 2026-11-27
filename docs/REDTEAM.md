# Red Team Operating Model

How RFASS-001 is used by a red team operator during an engagement: the roles, the phase structure, how the uncensored model is routed, and how evidence is handled.

---

## 1. Operating concept

RFASS-001 is an **advisor**, not an agent-of-attack. The operator drives it; it does not drive. This is a deliberate architectural stance, and it is the reason the platform can carry a refusal-relaxed model at all.

An autonomous offensive agent has an unbounded problem space: it decides what to try next, so a mistake propagates. A human-driven chatbot has a bounded one: the operator chooses every action, so a mistake stops at the operator.

| | Autonomous offensive agent | RFASS-001 (operator-driven) |
| :--- | :--- | :--- |
| Decision maker | Model | Operator |
| Worst case of a bad model decision | Chains into the target network | One assistant turn, discarded |
| Reach | Whatever the credentials allow | Container only — no host, no LAN, no tailnet |
| Audit trail | Model-generated | Operator-initiated, externally logged |
| Fits engagement ROE | Only if the ROE permits autonomy | Yes — the operator is the accountable party |

The container's lack of reach is the load-bearing property. See [SECURITY.md](SECURITY.md) → *Structural containment*.

---

## 2. Roles

| Role | Uses RFASS-001 for | Access |
| :--- | :--- | :--- |
| **Lead operator** | Drives the session; decides scope changes; signs off on the report | Telegram allowlist, full workspace |
| **Operator / analyst** | Technique research, artifact generation, ATT&CK mapping | Telegram allowlist, scoped workspace |
| **Observer** (client-side) | Read-only visibility into findings as they are written | Workspace read, no model access |
| **Platform maintainer** | Host maintenance: updates, firewall, backups | SSH via Tailscale |

`TELEGRAM_ALLOWED_USERS` is the enforcement point for model access. Everyone on it can command the agent; everyone off it is dropped before the LLM is invoked.

---

## 3. Engagement phases

The phase structure mirrors a standard red team engagement, and maps one-to-one onto the platform's capabilities.

| Phase | Operator objective | Platform capability | Output |
| :--- | :--- | :--- | :--- |
| **1. Scope** | Lock down authorization, targets, ROE, and out-of-scope | ROE template; operator prompt scope block | `roe.md` signed and loaded |
| **2. Recon** | Build target and person attack surface | OSINT guidance, enum scripts in `/workspace`, attack-surface mapping | Attack surface map |
| **3. Access** | Obtain and hold initial access | Technique reasoning, PoC drafting, local lab validation | Access PoC + detection note |
| **4. Post-exploitation** | Escalate, persist, move laterally, collect | Tradecraft reasoning, evasion analysis, artifact generation | Chain-of-attack notes |
| **5. Reporting** | Deliver findings the client can act on | Report shaping, ATT&CK mapping, remediation + detection guidance | Finding write-ups |

Detailed guidance per phase is in [PLAYBOOK.md](PLAYBOOK.md). The capability-to-tactic mapping is in [ATTACK-MAPPING.md](ATTACK-MAPPING.md).

### Phase 1 is not optional

The platform will happily answer an out-of-scope question — that is what an uncensored model is for. What stops it is the operator prompt's scope block plus the structural containment. The scope document is therefore a **prerequisite artifact, not paperwork**: without `roe.md` loaded, the model has no boundary to enforce beyond the container.

---

## 4. Model routing

The agent is configured with a default model; the operator can switch at runtime with `hermes-ctl model`. Use different profiles for different work.

| Profile | Use for | Why |
| :--- | :--- | :--- |
| **Uncensored / refusal-relaxed** | Technique reasoning, PoC drafting, evasion analysis, detection-gap questions | Dual-use requests get technical answers instead of deflection |
| **Frontier tuned** | Report prose, client-facing summaries, grammar and structure | Better written output; no need for refusal-relaxation |

The default in `docker/config.yaml.example` is the uncensored profile. Switch to a tuned model for the reporting phase; switch back for research.

**Operational note.** Because the agent runs against a remote inference endpoint, engagement material that flows through the model leaves the host. Use the uncensored profile for technique reasoning and general tradecraft. Keep client-identifying data (hostnames, usernames, real IPs, credentials) out of the prompt, or run a local model endpoint instead and point `OPENAI_BASE_URL` at it. The container configuration does not change either way — it is the endpoint URL and the key.

---

## 5. Binding the engagement

```bash
# 1. Create the engagement directory
mkdir -p /opt/ai-lab/hermes/workspace/engagements/<client>-<id>

# 2. Drop in the ROE and fill it in
cp docs/ROE-TEMPLATE.md /opt/ai-lab/hermes/workspace/engagements/<client>-<id>/roe.md
nano /opt/ai-lab/hermes/workspace/engagements/<client>-<id>/roe.md

# 3. Load the operator persona
cp redteam/operator-system-prompt.md /opt/ai-lab/hermes/workspace/

# 4. Point the agent at the engagement
hermes-ctl cli -- chat --system-prompt /opt/data/workspace/operator-system-prompt.md \
  --context /opt/data/workspace/engagements/<client>-<id>/roe.md
```

The exact invocation for step 4 depends on the Hermes CLI surface; `hermes-ctl cli` forwards arbitrary `hermes` subcommands, so check `hermes-ctl cli --help` for the installed version's flags. What matters is that **both** the persona and the scope document are loaded into the session before the first operational question.

To re-scope mid-engagement, update `roe.md` and restart the session. The scope block re-reads it.

---

## 6. Evidence handling

The workspace is the evidence store. Treat it as such.

- **Name every artifact.** `workspace/engagements/<client>-<id>/` with a subfolder per phase (`01-recon/`, `03-access/`, `04-post-ex/`, `05-report/`). The operator has to cite these in the report.
- **Review before it becomes a finding.** The agent drafts; the operator verifies. A PoC that was never executed is not a finding, and the prompt requires the model to say so.
- **Keep it out of version control.** `.gitignore` already excludes `workspace/`, `data/`, `backups/`, `*.log`.
- **Backups are local and permissioned.** `ai-lab-backup.timer` runs daily at 04:00, writes `0600` archives into `/opt/ai-lab/backups/`, and retains 7 days. It copies `data/` and `docker-compose.yml` — the `workspace/` scratch directory is the operator's to archive deliberately under the engagement's own retention rules.
- **Redaction before sharing.** Client data leaves the engagement workspace only after redaction. The model's endpoint is third-party unless you point it at a local one.

---

## 7. Known limits

Stated plainly, because a red team platform that oversells itself is worse than none.

| Limit | Consequence | Mitigation |
| :--- | :--- | :--- |
| The model endpoint is remote by default | Engagement text transits a third party | Point `OPENAI_BASE_URL` at a local model host; keep identifying data out of prompts |
| Prompt-level scope enforcement is not a security boundary | A determined prompt could try to step outside `roe.md` | Structural containment is the real control — no host, no LAN, no tailnet, no inbound |
| No target-network reach | Cannot validate against a live target from inside the lab | Validate in an isolated mirror or on a dedicated test range; keep the lab clean |
| Single container, 4 GB / 3 CPU cap | Heavy tooling (large builds, multi-target sweeps) will thrash | Do heavy work outside the lab; keep the lab for reasoning and drafting |
| No multi-user isolation | All allowlisted operators share one workspace | One engagement per workspace; archive between engagements |

---

## 8. Related documents

- [PLAYBOOK.md](PLAYBOOK.md) — phase-by-phase engagement guidance.
- [ATTACK-MAPPING.md](ATTACK-MAPPING.md) — capability-to-ATT&CK mapping.
- [ROE-TEMPLATE.md](ROE-TEMPLATE.md) — scope template and authorization gate.
- [../redteam/operator-system-prompt.md](../redteam/operator-system-prompt.md) — the persona itself.
- [SECURITY.md](SECURITY.md) — threat model and containment controls.
- [ARCHITECTURE.md](ARCHITECTURE.md) — system and network design.
