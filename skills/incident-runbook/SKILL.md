---
name: incident-runbook
description: Structure an incident investigation or post-mortem. Use when the user mentions an incident, a post-mortem, "investigate this outage", or asks for a runbook write-up.
assistants:
  copilot:
  cursor:
  windsurf:
---

Structure the investigation as the sections below. Everything is blameless: describe systems, signals, and decisions — never individuals, never roles used as a stand-in for individuals.

Where a fact is not established, write `{unknown — needs {source}}` rather than filling the gap. Never invent a timestamp, a metric value, a log line, or a request volume.

## Sections

**Incident summary** — one line: what broke, for whom, for how long.

**Timeline** — UTC timestamps, in order: first impact, detection, escalation, mitigation applied, resolution. For each entry name the source of the timestamp — the alert, the log line, the deploy record, the dashboard. An entry with no source is `{unknown — needs {source}}`.

**Blast radius** — affected services by TSA; affected brands, jurisdictions, products, and platforms; the user-visible symptom; the estimated affected request or user volume with the query behind the estimate; and anything that degraded silently rather than failing outright.

**Detection** — what alerted, how long after first impact, and who or what it reached. If nothing alerted, or the alert fired late or on the wrong signal, that alerting gap is itself a finding and belongs in follow-up actions.

**Root cause** — the chain of contributing factors. Distinguish the trigger (what made it happen now) from the root cause (what made it possible at all). Name the specific commit, configuration change, dependency, or capacity limit where it is identifiable; say `{unknown — needs {source}}` where it is not.

**Remediation applied** — what was done to stop the impact, when, and whether it is permanent or a temporary hold that still needs unwinding. Note anything left in a non-standard state.

**Follow-up actions** — numbered. Each has an owner placeholder `{owner}`, a concrete deliverable, and a priority. Group them under three headings, and do not conflate them:
- Prevent recurrence
- Improve detection
- Reduce time to mitigate

**What went well** — short and factual. What worked is worth protecting.

## Rules

- Blameless throughout. No names, no "the on-call should have".
- Never fabricate data. `{unknown — needs {source}}` is a complete and acceptable answer.
- Use `{curly}` placeholders.
- Use TSA values for service names when the project `{instructionsFile}` or `gaming-context-docs/architecture/service-registry.md` is available — resolved as `workspace/gaming-context-docs/` then `$HOME/Workspace/gaming-context-docs/`. If neither is available, use the service name as the user gave it and note that the TSA was not verified.
