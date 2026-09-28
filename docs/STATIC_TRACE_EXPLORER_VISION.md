# Static Trace Explorer — product direction

## Goal

Build an AppMap-like explorer for **static end-to-end traces of possible execution paths**.

The central unit is an entry method plus an incrementally expanded structural trace, not a global graph.

Primary question:

> What can execute from here, in what structural/evaluation order, through which conditions and branches, and where does each step belong in the codebase?

## Trace and ownership

Trace order follows source/control-flow/evaluation structure.

Folder/module ownership remains immediately visible through badges/colors/sidebar groups, but must not reorder the trace.

## Source fidelity

The explorer preserves both:

1. the original source expression;
2. its decomposed structural/evaluation view.

Example:

```text
FULL EXPRESSION
key(sourceElement.id())

evaluation
  INNER  sourceElement.id()
  OUTER  key(<result>)
```

## Controls

Conditions and branches are first-class.

Target source-semantic constructs include:

- IF TRUE/FALSE;
- SWITCH/MATCH CASE/DEFAULT;
- ternary expressions;
- FOR / FOREACH / WHILE;
- BREAK / CONTINUE;
- TRY / CATCH / FINALLY;
- THROW;
- RETURN.

Short-circuit boolean semantics must be visible rather than pretending all operands always execute.

## Errors

Error-path structure comes from actual control flow.

Configurable error-like type patterns are styling only.

## Polymorphism

Declared target and possible dispatch implementations remain separate.

## Static meaning

Static trace means:

```text
what CAN happen
```

A later runtime overlay may separately mark what was observed.

## Backend architecture

The structural probes proved that frontend lowering differs by language, so the architecture is:

```text
source
  ↓
Joern / CPG
  ↓
raw structural extraction
  ↓
source-semantic normalization
  ↓
Static Execution Model v4
  ↓
trace / architecture / impact / AI
```

## Current status

The all-method Static Execution Model v4 backend is implemented and frozen after:

- four-language fixture validation;
- focused switch/fallthrough validation;
- v3/v4 target-resolution parity validation;
- real GD-CAP whole-project validation with zero unmapped calls/controls.

The current milestone is to make v4 the product-facing analysis/viewer path:

```text
unified project analysis entrypoint
  -> safe CPG reuse/cache
  -> viewer v4
  -> lazy inter-method paths
  -> ownership/search/export
  -> application shell
```

Viewer V1/V2 remains historical/experimental. New viewer semantics must come from v4 structural relationships rather than text-containment heuristics.

Current work/handoff authority: `../CURRENT_WORK.md`.

## Product documents

- `docs/PRODUCT_REQUIREMENTS.md`
- `docs/STATIC_TRACE_EXPLORER_DECISIONS.md` — authority
- `docs/STATIC_EXECUTION_MODEL_V4.md`
- `docs/STRUCTURAL_PROBE_FINDINGS_CROSS_LANGUAGE.md`
