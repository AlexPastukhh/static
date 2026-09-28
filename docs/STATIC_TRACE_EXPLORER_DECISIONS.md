# Static Trace Explorer — Decisions

This file is the authority for accepted product, visualization, and model decisions.

If an older README, vision document, experiment, or viewer behavior conflicts with this file, this file wins until the other artifact is reconciled.

## 1. Product definition

Static Trace Explorer is an AppMap-like explorer of **possible static execution paths**.

The primary question is:

> What can execute from here, in what structural/evaluation order, through which conditions/branches, and where does each step belong in the codebase?

It is not primarily a whole-application graph renderer.

It is static:

```text
what CAN happen
```

not:

```text
what DID happen
```

## 2. Trace ordering

The downstream trace follows source/control-flow/evaluation structure.

It must not be reordered by folder/package/module.

Folder ownership remains visual/architectural metadata for:

- badges/colors;
- sidebar grouping;
- architecture/dependency views.

## 3. Full expression + nested calls

Keep the original full outer source expression and also expose nested calls.

Example:

```text
FULL EXPRESSION
key(sourceElement.id())

evaluation
  INNER  sourceElement.id()
  OUTER  key(<result>)
```

Final relationships come from normalized AST/expression structure, not text containment.

The same principle applies to fluent/chained calls.

## 4. Same-line repeated calls

Never deduplicate by only:

```text
caller + line + code + target
```

Distinct source call sites need distinct normalized identity.

The probe proved that CPG/AST structure can distinguish repeated identical same-line calls.

## 5. Conditions are first-class

Conditions are explicit control/expression structure.

Calls used by conditions are derived as condition calls from containment.

They are not shown as ordinary unconditional sibling calls.

## 6. Short circuit

`&&` / `||` and language equivalents preserve short-circuit semantics.

The UI must not imply that every operand always executes.

V4 stores semantic logical operator expressions with ordered children; no duplicate `evaluationOrder` field is required.

## 7. Branches

Branches are never flattened into a plain sequential list.

Required source-semantic controls:

- if / else;
- switch / case;
- Python match;
- ternary expression;
- classic for;
- foreach / for-in / for-of;
- while / do-while where supported;
- break / continue;
- try / catch / finally;
- throw / raise;
- early return.

## 8. Error paths

Structural error paths come from actual control structure such as:

- THROW;
- CATCH;
- branch membership;
- explicit structured result/error branches where available.

Separately, configurable type-name patterns may style error-like types:

```text
*Error
*Exception
*Failure
Throwable
```

Type styling never substitutes for control-flow detection.

## 9. Polymorphism

Declared target and possible runtime implementations remain separate.

Do not collapse interface/base declaration and possible dispatch implementations into one target.

## 10. Ownership

Folder/module ownership must be obvious on method cards.

Folder colors are configurable.

Ownership grouping is valid for sidebar/architecture views, not for execution-trace reordering.

## 11. Raw CPG vs source semantics

The structural probe proved that Joern frontends lower equivalent source constructs differently.

Therefore the architecture is:

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
viewer
```

Frontend lowering artifacts are not ordinary trace steps.

Examples:

```text
$iterLocal0
hasNext()
next()
__next__()
_result_0
$obj*
<operator>.alloc
```

## 12. Source normalization

V4 public source paths are project-relative with `/` separators.

V4 public line/column coordinates are 1-based.

Raw offsets are provenance only because they are not consistently available across frontends.

Raw `sourceCode` is not blindly trusted; source text is recovered from the project source when Joern supplies placeholders, lowering text, or truncation.

## 13. FOREACH is source-semantic

Java enhanced-for, Python for-in, TypeScript for-of, and C# foreach are all normalized to:

```text
FOREACH
  iterationBinding
  iterableExpression
  BODY
```

The raw frontend representation (`WHILE`, `FOR`, iterator calls, etc.) is not the public semantic kind.

## 14. Ternary remains an expression

The probe showed `<operator>.conditional` with ordered condition/true/false arguments across all four current languages.

Ternary is therefore modeled as an expression-level conditional, not a fabricated control structure.

## 15. TRY owns catch/finally branches

One normalized TRY control owns ordered branches:

```text
TRY
CATCH...
FINALLY
```

Catch/finally are not duplicated as unrelated top-level controls.

## 16. Throw / raise normalization

Java/TypeScript/C# THROW controls and Python `<operator>.raise` normalize to the same source-semantic `THROW`.

## 17. Return normalization

Source Return AST nodes normalize to `RETURN` controls, including early returns.

## 18. Stable normalized identity

Raw CPG node ids may be kept as provenance but are not the public stability contract.

Call/expression/control/branch ids are deterministic normalized ids derived from source/structural identity.

## 19. No redundant context/order fields

The structural probe did not demonstrate a need for:

- separate `sourceOrder`;
- separate `evaluationOrder`;
- duplicate `controlContext[]`;
- mandatory branch merge/join ids.

Authoritative order comes from ordered bodies and ordered expression children.

Parent/control context can be derived from containment.

## 20. Call roles are derived

Semantic call roles are computed from normalized containment rather than stored twice.

Examples:

- condition call;
- loop-condition call;
- nested argument call;
- return-expression call;
- error-path call;
- catch-path call.

## 21. V2.4 viewer heuristics

V2.4 text-containment grouping remains an experiment only.

The real v4 backend is now available; new product viewer work must use normalized structural relationships rather than V2 text-containment heuristics.

## 22. Schema status

Schema v3 remains available as the legacy/migration baseline.

The v4 source-semantic backend is now the frozen product structural baseline after fixture, fallthrough, target-resolution parity and GD-CAP gates. Its public contract is:

```text
schema/static-execution-model-v4.schema.json
docs/STATIC_EXECUTION_MODEL_V4.md
```

Retain the v3 pipeline as a migration/regression baseline until the product-facing v4 analysis/viewer path is established and no current regression workflow depends on v3.

## 23. Switch fallthrough gate resolved

A dedicated Java/TypeScript/C# fallthrough regression gate now passes.

The existing v4 SWITCH/MATCH representation remains unchanged. Implicit fallthrough is derived in the viewer/path layer from ordered CASE branches plus the absence of terminating BREAK/RETURN/THROW in the preceding branch. C# explicit `goto case` remains explicit source control rather than being reclassified as implicit fallthrough.

## 24. Runtime overlay

A later runtime overlay may mark observed paths separately.

It must not replace or rewrite the static possible-path semantics.


## 22. Architectural roles and orchestration

Architectural labels such as:

```text
FEATURE
DOMAIN
SHARED
INFRASTRUCTURE
ORCHESTRATION
```

are viewer/configuration metadata, not Static Execution Model v4 facts.

A useful conceptual presentation may look like:

```text
UI
  -> FEATURE / ORCHESTRATION
  -> DOMAIN
  -> SHARED / INFRASTRUCTURE
```

but repositories use different naming/layout conventions, so role mapping is configurable and optional. The viewer may use folder/package/namespace patterns plus actual call/control structure to make orchestration recognizable.

Do **not** add `architecturalRole: ORCHESTRATION` (or any other guessed architecture role) to the v4 backend schema merely for viewer convenience. Architectural grouping must never reorder the execution trace or turn ownership interpretation into execution semantics.
