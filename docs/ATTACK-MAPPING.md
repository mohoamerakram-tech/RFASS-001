# Platform Capability → MITRE ATT&CK Mapping

What RFASS-001 actually contributes to an engagement, mapped against MITRE ATT&CK tactics. This document exists to keep the platform honest: the mapping is about **operator support**, not automated attack capability.

---

## 1. Reading the mapping

| Column | Meaning |
| :--- | :--- |
| **Tactic** | ATT&CK tactic the operator is working through |
| **Operator task** | What the human actually does |
| **Platform contribution** | What the AI assistant does for the operator |
| **Platform requirement** | What must be true of RFASS-001 for that to work |
| **Not provided** | The part the platform does *not* help with — read this column |

The last column is the important one. RFASS-001 is a reasoning and drafting aid. It has no target-network reach, no exploit execution against a live target, and no credential store. Anything the mapping implies beyond that is not implied.

---

## 2. Tactic coverage

### Reconnaissance — TA0043

| Field | Detail |
| :--- | :--- |
| **Operator task** | Build the target attack surface; enumerate hosts, services, people, and technology |
| **Platform contribution** | Enumeration script generation; parsing and normalizing collected output; mapping discovered technology to known CVEs; attack-surface reasoning from partial data |
| **Platform requirement** | Public-internet egress for OSINT sources; `/workspace` for collected and derived artifacts |
| **Not provided** | Scanning of client infrastructure. The container cannot reach the LAN or tailnet by design; reconnaissance of in-scope client systems runs from an authorized position outside this lab |

### Resource Development — TA0042

| Field | Detail |
| :--- | :--- |
| **Operator task** | Build phishing lures, weaponized documents, malicious payloads, infrastructure |
| **Platform contribution** | Pretext and lure drafting; payload source drafting; awareness-simulation messaging; shellcode and loader source review; detection guidance for the payload |
| **Platform requirement** | `/workspace` for artifact generation; `rembg.service` on `127.0.0.1:7000` for local image manipulation |
| **Not provided** | Delivery infrastructure, hosting, or anything that reaches a target unprompted |

### Initial Access — TA0001

| Field | Detail |
| :--- | :--- |
| **Operator task** | Gain the first foothold: valid credentials, a phished user, an exposed service, a malicious file |
| **Platform contribution** | Technique selection and comparison; PoC drafting in the container; exploitation reasoning; phishing simulation copy and telemetry expectations |
| **Platform requirement** | `/workspace` as the build surface; uncensored model profile for dual-use technique questions |
| **Not provided** | Execution against a live target. Local lab validation only — the container has no route to the client |

### Execution — TA0002

| Field | Detail |
| :--- | :--- |
| **Operator task** | Run code on a compromised host |
| **Platform contribution** | API sequences and syscall chains; APC injection and thread-context hijack structure; process hollowing and reflective loading source; how each technique appears in telemetry |
| **Platform requirement** | Container shell for compile-and-inspect cycles in the lab |
| **Not provided** | Execution on the target host. This is where the lab and the engagement environment must be joined deliberately by the operator |

### Persistence — TA0003

| Field | Detail |
| :--- | :--- |
| **Operator task** | Survive reboot and re-entry |
| **Platform contribution** | Service and scheduled-task abuse; COM hijack and registry run-key reasoning; which persistence mechanisms survive which cleanup |
| **Platform requirement** | `/workspace` for artifact drafts |
| **Not provided** | Install and execution on the target |

### Privilege Escalation — TA0004

| Field | Detail |
| :--- | :--- |
| **Operator task** | Turn user-level access into administrative control |
| **Platform contribution** | Token and privilege reasoning; named-pipe impersonation structure; service-permission abuse analysis; UAC bypass technique discussion and its telemetry |
| **Platform requirement** | Uncensored model profile; container shell for PoC inspection |
| **Not provided** | Exploitation of the target |

### Defense Evasion — TA0005

| Field | Detail |
| :--- | :--- |
| **Operator task** | Stay under the defender's radar |
| **Platform contribution** | **The strongest capability in the platform.** Detection-surface analysis is exactly what the model is good at: ETW provider and event-ID mapping, Sysmon configuration gaps, AMSI and Defender telemetry coverage, unbacked memory region characteristics, and the observable footprint of each evasion technique |
| **Platform requirement** | Uncensored model profile; `/workspace` for binary and log analysis artifacts |
| **Not provided** | A bypass that is guaranteed to work. The model reasons about coverage; it cannot see the client's actual detection pipeline |

### Credential Access — TA0006

| Field | Detail |
| :--- | :--- |
| **Operator task** | Obtain credentials from memory, caches, or configuration |
| **Platform contribution** | Technique review and comparison; AD enumeration reasoning; credential-store and cache location guidance; what a defender's telemetry looks like for each approach |
| **Platform requirement** | `/workspace` as the analysis surface |
| **Not provided** | Credential harvesting executed against a target, and any credential storage |

### Discovery — TA0007

| Field | Detail |
| :--- | :--- |
| **Operator task** | Map the environment after gaining access |
| **Platform contribution** | Enumeration command construction; AD and network-topology reasoning; interpretation of collected output; pivot-path identification |
| **Platform requirement** | Container shell for script development and dry runs |
| **Not provided** | Discovery against the client environment from this lab |

### Lateral Movement — TA0008

| Field | Detail |
| :--- | :--- |
| **Operator task** | Move to the next host |
| **Protocol** | Pass-the-hash, SMB and WMI pivoting, remote service creation, and tunneling technique reasoning |
| **Platform requirement** | `/workspace` |
| **Not provided** | **All lateral movement.** The `DOCKER-USER` rules drop traffic from `172.28.0.0/24` to `192.168.0.0/16`, `10.0.0.0/8`, `172.16.0.0/12`, and `100.64.0.0/10`. The agent cannot pivot into the target network even if fully jailbroken — this is a deliberate containment decision, not a limitation to work around |

### Collection — TA0009

| Field | Detail |
| :--- | :--- |
| **Operator task** | Collect the data the objective requires |
| **Platform contribution** | Collection planning against the stated objective; staging and archival structure; collection-script drafting |
| **Platform requirement** | `/workspace` for staging |
| **Not provided** | Collection from client systems |

### Command and Control — TA0011

| Field | Detail |
| :--- | :--- |
| **Operator task** | Maintain command and control over compromised assets |
| **Platform contribution** | C2 protocol and beaconing-interval reasoning; jitter and dead-drop-resolver design discussion; malleable-profile awareness |
| **Platform requirement** | `/workspace` |
| **Not provided** | Any C2 infrastructure. **RFASS-001's own chat gateway is a legitimate operator channel and is deliberately not a C2 channel** — it is allowlisted, outbound-only, and bound to `127.0.0.1:8642` |

### Exfiltration — TA0010

| Field | Detail |
| :--- | :--- |
| **Operator task** | Move data out covertly |
| **Platform contribution** | Channel comparison and detection-surface analysis; cloud and DNS exfiltration technique discussion; what each channel looks like on the wire and in the client's logs |
| **Platform requirement** | `/workspace` |
| **Not provided** | Exfiltration channels or infrastructure. Public-internet egress is permitted for the *model endpoint*; engagement data egress is the operator's decision, made knowingly |

### Impact — TA0040

| Field | Detail |
| :--- | :--- |
| **Operator task** | Demonstrate business impact without causing real harm |
| **Platform contribution** | Impact framing for the report; ransomware-style destructive-path *discussion* for detection purposes; business-impact narrative for the client |
| **Platform requirement** | `/workspace` for simulation artifacts |
| **Not provided** | Destructive capability against live systems. This is the platform's clearest line: reason about impact, demonstrate it in the lab, never perform it against a target |

---

## 3. Platform-side tactics

The platform is itself a system, and it has a defensive surface worth mapping.

| Platform asset | Defensive concern | Control |
| :--- | :--- |
| Telegram gateway | Unauthorized operator access | `TELEGRAM_ALLOWED_USERS` numeric allowlist, default-deny |
| Hermes agent container | Container escape, host compromise | Unprivileged UID, `cap_drop: ALL`, `no-new-privileges`, no Docker socket |
| Egress path | Pivot into the client network | `DOCKER-USER` DROP rules for RFC 1918 and CGNAT ranges |
| Inference endpoint | Client data exposure | Remote endpoint by default; `OPENAI_BASE_URL` is operator-configurable and can point at a local model host |
| Workspace and backups | Engagement artifact leakage | `0600` backups, `700` directories, `.gitignore` exclusions, 7-day retention |
| Chat gateway port | Inbound exposure | Bound strictly to `127.0.0.1:8642`; host UFW default-deny incoming |

---

## 4. Summary

**Strongest contribution:** defense evasion reasoning and detection-surface analysis (TA0005), followed by technique-level execution reasoning (TA0002).

**Deliberate gaps:** lateral movement (TA0008), C2 (TA0011), exfiltration (TA0010), impact (TA0040). These are structural, not accidental — they are the containment boundary.

**Read the platform as:** a way to move the operator's *thinking* faster and deeper, with the parts that would move the operator's *footprint* into the client network removed by design.

See [SECURITY.md](SECURITY.md) for the containment controls, and [PLAYBOOK.md](PLAYBOOK.md) for how these capabilities are applied in phase order.
