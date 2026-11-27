# Red Team Engagement Playbook

Phase-by-phase operator guidance for running an engagement on RFASS-001. Each phase states the objective, what the platform contributes, how to work the session, and what the operator must own personally.

Tactic references use MITRE ATT&CK IDs. The capability mapping behind these phases is in [ATTACK-MAPPING.md](ATTACK-MAPPING.md).

---

## Phase 0 — Pre-engagement

**Objective.** Make sure the lab itself is ready and the paperwork is real.

```bash
# Verify the containment posture before anything else
hermes-ctl status
iptables -L DOCKER-USER -n

# Confirm the model profile the engagement will run on
hermes-ctl model
```

**Operator owns:**
- A signed ROE. Not a draft. See [ROE-TEMPLATE.md](ROE-TEMPLATE.md).
- Client contact and escalation path for out-of-scope findings.
- The engagement objective, in one sentence, that every later artifact will be measured against.

---

## Phase 1 — Scope

**Objective.** Convert the ROE into a model-readable constraint.

**Platform contribution.** Turns the ROE into an explicit in-scope / out-of-scope list and a set of hard constraints the operator persona enforces.

**Session pattern.**

```
Operator:  Here is the ROE. Read it and tell me what is in scope and what you refuse.
Agent:     [summarizes targets, techniques allowed, techniques excluded, window, escalation path]

Operator:  Confirm the refusal boundary: if I ask you for X, what will you do?
Agent:     [states the boundary in its own words — if this does not match the ROE, stop and fix it here]
```

**Operator owns:** verifying the agent's restatement against the actual ROE before any operational question is asked. A model that misreads the scope is a model you do not have.

**Output:** `roe.md` loaded and confirmed.

---

## Phase 2 — Reconnaissance (TA0043)

**Objective.** Build the attack surface, from people and processes outward.

**Platform contribution.** Enumeration script generation, output parsing and normalization, CVE mapping for discovered technology, and attack-surface reasoning from partial data.

**Session pattern.**

```
Operator:  Target is a company of ~200 on Windows 10/11 and Exchange. What do you need me to collect?
Agent:     [prioritized collection list: AD attributes, exposed services, software inventory,
            email/tenant posture, VPN and remote-access entry points]

Operator:  Write the collection script for the AD half, and tell me what each LDAP filter reveals.
Agent:     [script + per-attribute interpretation + what each query exposes in the DC logs]
```

**Operator owns:** deciding where collection actually runs. It does not run from this container — the agent has no route to the client network. Collect from an authorized position, paste results into `/workspace/engagements/<client>-<id>/01-recon/`.

**Detection note to capture:** which of these queries the client's SIEM or EDR would log. Recon is often the quietest phase and the easiest to miss in a report.

**Output:** attack surface map, collection artifacts under `01-recon/`.

---

## Phase 3 — Initial Access (TA0001)

**Objective.** Get the first foothold.

**Platform contribution.** Technique selection and comparison, PoC drafting, exploitation reasoning, phishing simulation copy and its telemetry.

**Session pattern.**

```
Operator:  We have a phishing precondition. Give me the three most likely landing approaches
           and their detection surfaces.
Agent:     [approaches ranked by realism; for each: pretext, landing mechanism, what the mail
            gateway and EDR should catch, and what it will not catch]

Operator:  Draft the lure for a finance user and the simulation telemetry expectations.
Agent:     [lure copy + inert payload design + what the reported-phish flow should capture]
```

**Operator owns:** the social engineering itself, and the decision to send. Nothing leaves the container on its own — the model drafts, the operator acts.

**Detection note to capture:** the gap between what the mail gateway blocks and what the user would have seen. This is frequently the client's most actionable finding.

**Output:** access approach with PoC, lure artifacts, and detection notes under `03-access/`.

---

## Phase 4 — Execution and Post-Exploitation (TA0002, TA0004, TA0005)

**Objective.** Test how far the foothold goes, and whether it would have been seen.

**Platform contribution.** The strongest part of the platform: API sequences, syscall chains, injection structures, token and privilege reasoning, and detection-surface analysis for every technique.

**Session pattern.**

```
Operator:  Assume we are user-level on a patched Windows 11 host. What is the most reliable
           path to SYSTEM that a defender is least likely to catch, and what does each step emit?
Agent:     [technique with full API sequence; per step: the API, the ETW/Sysmon/Defender
            telemetry it produces, the configuration change that would enable detection,
            and the observable footprint of the technique itself]
```

**Operator owns:** the detection story. Ask for it every time. A technique with no telemetry is not a technique the client can fix — it is a technique you cannot put in a report.

**Key question to keep asking:** *"What does this leave behind?"* — the model's value here is the second-order question: registry keys, service creation, memory regions that persist, scheduled tasks, and the artifacts a responder will find.

**Output:** post-exploitation chain, per-step detection notes, and cleanup requirements under `04-post-ex/`.

---

## Phase 5 — Collection, Discovery, and Lateral Movement (TA0007, TA0008, TA0009)

**Objective.** Understand the blast radius of the foothold — how far it reaches.

**Platform contribution.** Discovery command construction, pivot-path identification, collection planning against the stated objective.

**Platform limitation — say this out loud.** RFASS-001's agent cannot move laterally into the client network. The `DOCKER-USER` rules drop `172.28.0.0/24` traffic to `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`, and `100.64.0.0/10`. Lateral movement testing runs from the operator's authorized position on the client side; the platform contributes reasoning, not reach.

**Session pattern.**

```
Operator:  We are user-level on DC01. What is the highest-value discovery sequence before we
           touch anything else, and what does each step log?
Agent:     [ordered discovery sequence; per step: the command, what it enumerates, and the
            corresponding DC-side event IDs]
```

**Output:** discovery results and pivot map under `04-post-ex/`.

---

## Phase 6 — Reporting (TA0040 — as narrative, not action)

**Objective.** Deliver findings the client can act on.

**Platform contribution.** Report shaping, ATT&CK mapping, remediation and detection guidance, honest severity framing.

**Session pattern.**

```
Operator:  Turn this into a finding: title, ATT&CK mapping, description, evidence, impact,
           remediation, and detection guidance. Be honest about severity — we did not get SYSTEM.
Agent:     [finding in report shape]
```

**Operator owns:** severity. The model will frame it; the operator decides. Overstated severity destroys credibility with a technical audience, and the operator will be defending the report in the debrief.

**Report shape per finding:** title · ATT&CK mapping · description · evidence · impact · remediation · detection guidance.

**Output:** final report under `05-report/`.

---

## Phase 7 — Teardown

**Objective.** Close the engagement without leaving the lab or the client exposed.

```bash
# Archive the engagement deliberately (workspace/ is not in the daily backup)
tar -czf /opt/ai-lab/backups/engagement-<client>-<id>-<date>.tar.gz \
  -C /opt/ai-lab/hermes/workspace engagements/<client>-<id>
chmod 600 /opt/ai-lab/backups/engagement-<client>-<id>-<date>.tar.gz

# Tear down the agent, keeping the persistent volumes
hermes-ctl down
```

**Operator owns:**
- Any cleanup the client asked for.
- The retention decision on engagement artifacts.
- Confirming `hermes-ctl down` left the workspace intact (`data/` and `workspace/` are persistent volumes by design).

---

## Session discipline

Practical habits that make the difference between a useful session and a frustrating one.

1. **One engagement per workspace.** `workspace/engagements/<client>-<id>/` keeps artifacts separable. Start a new one per engagement.
2. **Ask for the detection surface every time.** It is the highest-value output and the most frequently forgotten.
3. **Push back on confidence.** If the model states a behavior it is unsure about, ask it to verify. Do not carry an unverified claim into a report.
4. **Keep client identifiers out of the prompt.** The default inference endpoint is remote. Keep hostnames, usernames, real IPs, and credentials out of prompts unless the endpoint is local.
5. **Switch model profile for the report.** `hermes-ctl model` → a tuned model for client-facing prose. The uncensored profile is for technique work.
6. **Archive between engagements.** `hermes-ctl down` keeps the volumes, so a stale engagement's artifacts stay on disk until you clean them up.

---

## Related documents

- [REDTEAM.md](REDTEAM.md) — operating model, roles, model routing, evidence handling.
- [ATTACK-MAPPING.md](ATTACK-MAPPING.md) — capability-to-tactic mapping, including what is deliberately absent.
- [ROE-TEMPLATE.md](ROE-TEMPLATE.md) — scope template and authorization gate.
- [../redteam/operator-system-prompt.md](../redteam/operator-system-prompt.md) — the operator persona.
- [SECURITY.md](SECURITY.md) — threat model and containment controls.
