---
name: dependency-review
description: Evaluate a third-party package before adopting it and produce a decision record. Use when the user says "review this dependency", "should we add this package", "new dependency", or proposes installing something.
assistants:
  copilot:
  cursor:
  windsurf:
---

Produce a decision record for a proposed dependency. Investigation is read-only: query the registry and the repository, read the local manifests, and run nothing that mutates state.

## Before evaluating

Check whether the problem is already solved in this repository. Read the root manifest and the workspace manifests for a package that already covers the need, and search the local shared packages for an existing helper. If one exists, say so — that is usually the answer and the rest of the record becomes moot.

When `gaming-context-docs` is available — resolved as `workspace/gaming-context-docs/` then `$HOME/Workspace/gaming-context-docs/` — read `standards/engineering/principles/technology-selection.md` and hold the candidate against it. If the repo or the doc is absent, say so and fall back to the criteria below.

## Decision record

**Package** — name, proposed version, registry link, and the repository URL.

**Licence** — the SPDX identifier and a compatibility verdict for a commercial closed-source product. Treat copyleft (GPL, AGPL, SSPL) and any licence demanding attribution or source disclosure as a blocker requiring explicit sign-off, and say who needs to sign off. Flag a missing, ambiguous, or dual licence as a blocker too.

**Maintenance** — last release date, last commit date, open issue count, open PR count, number of contributors active in the last year, and whether the project is archived or marked deprecated. These come from registry metadata and the repository — not from recollection. Mark anything you could not fetch as unverified.

**Transitive footprint** — direct dependency count, total transitive count, and any transitive with a known advisory. Note any transitive that duplicates something already in the tree at a different major version.

**Size impact** — unpacked size, and minified+gzip where the package can reach a client bundle. State whether it is ESM-native and tree-shakeable, and whether it lands in a client bundle or is server-only. A server-only dependency is judged very differently from one that ships to users.

**Alternatives** — at least two, one of which is always "write it ourselves" with an honest effort and maintenance estimate. State why the recommended option wins over each.

**Verdict** — adopt / adopt with conditions / reject, naming the single deciding factor. When it is "adopt with conditions", list the conditions as concrete actions.

## Rules

- Never run an install, add, upgrade, or audit-fix command. Never touch a lockfile or a manifest.
- State plainly when a data point could not be verified. Do not estimate a release date, a size, or an issue count.
- Network access may be unavailable. If it is, complete every section you can from local data and list exactly which fields need a manual lookup, with the URL to look them up at.
- Keep the record short enough to be read in full. Bullets, not essays.
