# Rules of Engagement Template

Copy this into `/opt/ai-lab/hermes/workspace/engagements/<client>-<id>/roe.md`, fill it in, and load it before the first operational question. See [REDTEAM.md](REDTEAM.md) → *Binding the engagement*.

**Why this file exists.** RFASS-001 runs a refusal-relaxed model. That model will answer an out-of-scope request if nothing tells it otherwise. This document is what tells it otherwise. It is a load-bearing part of the platform, not paperwork — see [SECURITY.md](SECURITY.md) → *Instructional vs. structural containment*.

---

## 1. Authorization

| Field | Value |
| :--- | :--- |
| **Client organization** | |
| **Engagement name** | |
| **Engagement ID** | |
| **Rules of Engagement signed by** | |
| **Client technical contact** | |
| **Client escalation contact (24/7)** | |
| **Start date / End date** | |
| **Engagement window (time-of-day, timezone)** | |
| **Operator(s)** | |

---

## 2. Objective

State the engagement objective in one sentence. Every artifact produced during the engagement is measured against this sentence.

```
The objective of this engagement is:
```

---

## 3. In-scope targets

List every target explicitly. Targets not listed here are out of scope.

| Target | Type | Method | Notes |
| :--- | :--- | :--- | :--- |
| | IP / hostname / CIDR / domain / asset tag | | |

---

## 4. Out of scope

Explicitly excluded targets, techniques, and actions. The assistant must refuse these.

| Excluded | Reason |
| :--- | :--- |
| | |

**Default exclusions** — remove any that the client has explicitly permitted in writing:

- Production data modification or deletion.
- Denial of service, stress testing, or resource exhaustion of any kind.
- Physical access or social engineering of client staff beyond the agreed simulation list.
- Third-party or shared services not explicitly listed in section 3.
- Persistence beyond the end of the engagement window without a written extension.
- Out-of-band communication with any party outside the client organization.

---

## 5. Permitted techniques

| Allowed | Constraints |
| :--- | :--- |
| Credential access (specific type) | |
| Initial access (specific type) | |
| Execution (specific type) | |
| Persistence (specific type) | |
| Privilege escalation (specific type) | |
| Defense evasion (specific type) | |
| Discovery / collection (specific type) | |
| Lateral movement (specific type) | |

---

## 6. Rate limiting and operational safety

| Constraint | Value |
| :--- | :--- |
| Maximum concurrent operators | |
| Maximum requests per hour | |
| Maximum automated actions per session | |
| Mandatory operator approval for any autonomous action | |
| Business hours restriction | |

> Recommended: **the operator approves every action.** RFASS-001 is an operator-driven advisor. Autonomous action is outside the platform's design.

---

## 7. Data handling

| Rule | Value |
| :--- | :--- |
| Client data may be stored in the lab workspace | Yes / No — conditions |
| Client data may be sent to the remote inference endpoint | Yes / No — conditions |
| Credentials collected during the engagement | Retention period, storage location, who may access |
| Engagement artifacts retention period | |
| Who may receive the final report | |

> **Note.** The default inference endpoint is remote. If section 7 says client data may not be sent to it, either point `OPENAI_BASE_URL` at a local model host, or keep identifying data out of prompts. The container configuration is unchanged either way.

---

## 8. Detection validation

| Rule | Value |
| :--- | :--- |
| The client will provide SIEM / EDR logs during the engagement | Yes / No |
| Detection findings are in scope | Yes / No |
| Log access window | |
| Client-side monitoring is handled by | |

---

## 9. Stop conditions

The operator halts immediately, without further testing, when any of these occur:

- Any action lands on a target that is not listed in section 3.
- Client or third-party monitoring detects the engagement.
- A production system shows availability impact.
- Client business operations are affected in any way.
- Sensitive data is encountered that is outside the agreed collection scope.
- A personal safety or legal risk is identified.
- Any other condition the client specifies.

**On a stop condition:** the operator confirms to the client, collects the evidence gathered so far, and moves to reporting. The engagement does not resume without written client approval.

---

## 10. Sign-off

| Role | Name | Date | Signature |
| :--- | :--- | :--- | :--- |
| Client lead | | | |
| Engagement lead | | | |

---

## 11. Operator confirmation

Complete before the first operational question. The model restates the scope in its own words; the operator verifies that restatement against this document.

```text
Engagement: <client> / <engagement id>
Authorized window: <start> - <end>
In scope: <targets>
Out of scope: <exclusions>
Permitted techniques: <techniques>
Stop conditions: <conditions>
Escalation contact: <name, contact>

Confirm: read this scope and tell me what you will do and what you will refuse.
```

**If the model's restatement does not match this document, stop and correct it before proceeding.**

---

## Related documents

- [REDTEAM.md](REDTEAM.md) — binding the engagement, evidence handling.
- [PLAYBOOK.md](PLAYBOOK.md) — phase-by-phase engagement guidance.
- [../redteam/operator-system-prompt.md](../redteam/operator-system-prompt.md) — the operator persona and its scope block.
- [SECURITY.md](SECURITY.md) — instructional vs. structural containment.
