---
name: standards-check
description: Fast compliance check of changed files against the Gaming standards repos. Use when the user says "check standards compliance", "does this follow the standards", or "standards check". Cites the source repo and doc for every rule.
assistants:
  copilot:
  cursor:
  windsurf:
---

A fast pass over the changed files against the standards docs. This is not a full review — it does not duplicate `code-reviewer` or `observability-reviewer` scope.

## Standards repos

Resolve each repo by taking the first path that exists:

1. `workspace/{repo}/` relative to the project root
2. `$HOME/Workspace/{repo}/`

The repos are `gaming-context-docs`, `gaming-process-docs`, and `gaming-architecture-docs`.

Standards repos are pulled fresh by the coordinator via `/update-workspace` before this skill runs. Do not refresh them here.

If a repo resolves to no path: name it in the output, list the checks that therefore did not run, and suggest to the developer that they clone it —

```
git clone https://github.com/Flutter-Global/{repo} $HOME/Workspace/{repo}
```

Then skip those checks. Never guess at the content of a rule you could not read, and never fabricate a citation.

## Scope

Check only the changed files — taken from the prompt, or from `git diff --name-only` plus `git diff --cached --name-only`. Do not widen to the rest of the repository.

## Checklist

**(a) Terminology** — `gaming-context-docs` (`standards/naming/`, `concepts/`) plus your global AI instructions § Terminology:
- TSA — never TLA, Service ID, `app_id`, or `service_id`
- `zone` — never a `dc` dimension
- `supplier` — never `provider` (in prose; existing code identifiers are exempt)
- `team` — never squad
- canonical brand names `betfair`, `paddypower`, `skybet` — never a short code
- British spelling `licence`, `licenceModel`
- `Containerfile`, `compose.yaml`, "container image"
- name the repository explicitly rather than saying "the monorepo"
- GFE is a TSA; Venus is the frontend platform; platforms are tags, not directories

**(b) Log dimensions** — `gaming-context-docs/standards/observability/log-dimensions.md`: required root-level fields present or explicitly `null`; `service` holds a TSA; no compound `jurisdiction`; flow detail in `msgContext`; no upstream value re-mapping.

**(c) API patterns** — `gaming-context-docs/standards/engineering/api/api-response-formatting.md` and `http-headers.md`: response envelope shape, status code choice, required and forbidden headers. Apply when the diff touches an HTTP controller or route.

**(d) Configuration hygiene** — `gaming-context-docs/standards/engineering/practices/configuration-hygiene.md` and `fallback-values.md`: no magic values, every default documented and deliberate, no secrets in committed config, fallbacks explicit rather than implicit.

**(e) Process and compliance** — `gaming-process-docs`: the applicable checklist or policy when the diff touches deployment, data handling, retention, or a compliance-relevant flow. Name the specific checklist.

**(f) Architecture decisions** — `gaming-architecture-docs`: whether the change contradicts an existing ADR, or alters a documented service interaction. A new cross-service contract with no ADR behind it is itself a finding.

**(g) Placeholders** — `{curly}` only. Never `<angle>`, never `{{double}}`.

## Output

A table:

| File:line | Rule | Source | Severity |
|---|---|---|---|
| `{file}:{line}` | what is wrong | `{repo}` → `{doc path}` | Critical / High / Medium / Low |

Then:
- A one-line verdict.
- A clear separation between "violates a cited standard" and "no standard found — best-practice observation".
- An explicit list of any repo that was unavailable, and the checks that did not run because of it.
