# Documentation

## `context/` — project context

These four files are the project state in writing. They're committed for a purpose: they're what you (person or agent) need to read to pick up the work without reconstructing the reasoning from code.

| File | What it's for |
| --- | --- |
| [CONTEXT.md](context/CONTEXT.md) | What the platform is and why it's built this way |
| [GOTO.md](context/GOTO.md) | What's missing, in order |
| [AVANCES.md](context/AVANCES.md) | What was done and when |
| [AUDITORIA-PLANTILLA.md](context/AUDITORIA-PLANTILLA.md) | What was broken in the initial version |

When closing a block of work, update `AVANCES.md` and `GOTO.md`. If the decision changes the architecture, also add an ADR.

## `uso/` — for the dev consuming the platform

| File | What it's for |
| --- | --- |
| [CONECTAR.md](uso/CONECTAR.md) | Connect VS Code (Continue, Cline), Open WebUI, SDKs, and what name resolves from where |

## `ops/` — for whoever operates it

| File | What it's for |
| --- | --- |
| [RUNBOOK.md](ops/RUNBOOK.md) | Diagnosis by symptom and by alert |
| [TROUBLESHOOTING.md](ops/TROUBLESHOOTING.md) | Common failures and how to resolve them |
| [VERSIONS.md](ops/VERSIONS.md) | Pinned versions and how to update them |

## `adr/` — architecture decisions

One [ADR](adr/) per decision that isn't understood by reading the code. Repository comments reference them by path.
