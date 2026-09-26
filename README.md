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

## Model status

Schema v3 remains the stable existing call/type pipeline.

The cross-language structural probe is complete enough to define the first source-semantic v4 contract:

```text
schema/static-execution-model-v4.schema.json
docs/STATIC_EXECUTION_MODEL_V4.md
docs/STRUCTURAL_PROBE_FINDINGS_CROSS_LANGUAGE.md
```

The probe confirmed that frontend lowering differs materially across languages, so raw CPG structure is normalized before reaching the viewer.

Examples include Java/Python/TypeScript foreach loops being lowered differently from C# foreach, and Python `raise` differing from Java/TS/C# `THROW`.

## Next backend milestone

Implement v4 for all production methods:

1. raw structural export;
2. source-semantic normalization;
3. four-language fixture validation;
4. real `gd-cap` validation;
5. viewer migration from V2.4 heuristics to v4 relationships.

## Important UI rule

Folder/module ownership is visual metadata.

It may group the sidebar or architecture/dependency views, but it must **not reorder the execution trace**.

## Product documents

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
