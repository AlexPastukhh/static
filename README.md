# Static Trace Explorer

Static Trace Explorer is an AppMap-like browser for **static end-to-end traces of possible execution paths**.

Select an entry method and explore what can happen from that point without rendering the whole application graph by default.

## Architecture

```text
source
  ↓
Joern / CPG
  ↓
raw structural extraction
  ↓
source-semantic normalization
  ↓
Static Execution Model
  ↓
Static Trace Explorer
```

Static means:

```text
what CAN happen
```

not:

```text
what DID happen
```

A runtime-observed overlay may be added later.

## Languages

Current lab/normalization scope:

- Java
- Python
- TypeScript / Node
- C# / .NET

## Current status

The Static Execution Model v4 backend is now the frozen product baseline for structural analysis.

Completed gates:

```text
four-language v4 fixtures       PASS
switch/fallthrough gate         PASS
v3/v4 target-resolution parity PASS
GD-CAP whole-project v4         PASS
unmapped calls                  0
unmapped controls               0
```

The current product phase is **v4 application/viewer integration**, not more backend redesign by default.

Start here before changing the repository:

```text
CURRENT_WORK.md
docs/work-manifest.json
docs/PROJECT_TRACE.md
docs/NEXT_MILESTONE_VIEWER_V4.md
```

The older v3 pipeline and V1/V2 viewer remain useful migration/history artifacts, but new product work should consume the v4 model directly.

## Important UI rule

Folder/module ownership is visual metadata.

It may group the sidebar or architecture/dependency views, but it must **not reorder the execution trace**.

## Product and handoff documents

- `CURRENT_WORK.md` — current work/handoff authority
- `docs/PROJECT_TRACE.md` — engineering history
- `docs/NEXT_MILESTONE_VIEWER_V4.md` — current forward plan
- `docs/work-manifest.json` — machine-readable current state
- `docs/PRODUCT_REQUIREMENTS.md`
- `docs/STATIC_TRACE_EXPLORER_DECISIONS.md` — authoritative decision record
- `docs/STATIC_TRACE_EXPLORER_VISION.md`
- `docs/STATIC_EXECUTION_MODEL_V4.md`
- `docs/STRUCTURAL_PROBE_FINDINGS_CROSS_LANGUAGE.md`

## Repository areas

```text
config/      viewer configuration
docs/        product/model direction and evidence
schema/      normalized model schemas
scripts/     Joern export, normalization, validation, viewer generation
viewer/      browser viewer templates
fixtures/    focused structural regression fixtures
results/     generated analysis results
```
