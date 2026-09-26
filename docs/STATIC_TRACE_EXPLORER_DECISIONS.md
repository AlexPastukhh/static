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

Once a real v4 model is available, the viewer must use normalized structural relationships.

## 22. Schema status

Schema v3 remains the stable existing model during migration.

The first v4 source-semantic contract is:

```text
schema/static-execution-model-v4.schema.json
docs/STATIC_EXECUTION_MODEL_V4.md
```

Do not remove the v3 pipeline until v4 has passed fixtures and the real `gd-cap` model.

## 23. Known remaining structural gap

Switch/match case extraction is validated structurally, but legal case fallthrough behavior has not yet received a dedicated regression fixture.

Do not claim complete switch fallthrough fidelity until that focused test passes.

## 24. Runtime overlay

A later runtime overlay may mark observed paths separately.

It must not replace or rewrite the static possible-path semantics.
