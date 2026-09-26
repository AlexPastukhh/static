# Static Trace Explorer — Product Requirements

This document is the compact current requirements baseline.

For detailed accepted design decisions, see `STATIC_TRACE_EXPLORER_DECISIONS.md`.

## Product definition

Static Trace Explorer is an AppMap-like explorer for **possible static execution paths**.

The user selects an entry method and incrementally explores possible downstream or upstream paths.

It is not a runtime recorder and it is not primarily a whole-application graph renderer.

## MUST — product semantics

The explorer must:

- represent **what can happen**, not claim what did happen at runtime;
- start from a selected entry method;
- support downstream exploration;
- support upstream/incoming exploration for impact analysis;
- preserve source/control-flow/evaluation structure;
- avoid rendering the whole application graph by default;
- protect against cycles;
- support configurable exploration depth;
- preserve folder/package/module ownership without letting ownership grouping reorder the execution trace;
- keep declared polymorphic target separate from possible implementations.

## MUST — method information

A method node should expose, where available:

- folder/package/namespace;
- owner class/type;
- method name;
- file and source line/range;
- parameter names and types;
- return type;
- method kind.

## MUST — call-site information

A call site should expose, where available:

- original source expression;
- unique/stable call-site identity;
- source file and position/order;
- declared target;
- possible/dispatch targets;
- argument expressions/types;
- resolution provenance.

Distinct call-sites must not be merged merely because they share caller, line, text, and target.

## MUST — expressions

For nested or chained calls:

- preserve the original full outer expression;
- expose inner/nested calls;
- expose their structural/evaluation relationship;
- do not display structurally nested calls as unrelated siblings;
- derive final relationships from CPG/AST structure rather than text guessing.

Example:

```text
FULL EXPRESSION
key(sourceElement.id())

evaluation
  1 INNER  sourceElement.id()
  2 OUTER  key(<result>)
```

## MUST — conditions and control flow

Conditions are first-class nodes.

The model/UI must be able to distinguish calls used to evaluate conditions from ordinary calls.

Required control concepts:

- if / else;
- switch / case;
- ternary;
- loops;
- loop condition/body;
- break / continue;
- try / catch / finally;
- throw;
- early return.

Branches must never be flattened into a simple sibling-call list.

## MUST — short circuit

When structural data is available, `&&` and `||` evaluation must preserve short-circuit semantics.

The UI must not imply that every condition operand always executes.

## MUST — error paths

Explicit error/control-flow paths should be distinguishable from normal paths.

Structural error-path information comes from control flow such as:

- throw;
- catch;
- relevant branches;
- explicit error/result handling when represented structurally.

Configurable type-name patterns such as `*Error`, `*Exception`, `*Failure`, and `Throwable` are styling aids only.

They are not control-flow detection.

## MUST — ownership and UI

Folder/module ownership must be obvious.

Required capabilities include:

- folder badge/color;
- configurable folder colors;
- sidebar grouping by folder;
- search;
- lazy/collapsible exploration;
- jump to source;
- constructor toggle;
- external-call toggle.

Architecture/dependency views may group by folder.

The execution trace may not be reordered by folder.

## Supported language scope

The normalized approach is intended to work across the four current lab languages:

- Java;
- Python;
- TypeScript / Node;
- C# / .NET.

Language frontends may provide different degrees of type precision. The normalized model should preserve available information without fabricating missing precision.

## Current baseline

Schema v3 remains the stable baseline for the current normalized call/type model.

It is sufficient for:

- methods/types;
- direct and multi-hop calls;
- ownership;
- incoming/outgoing navigation;
- polymorphic target representation;
- source-line information.

It is **not** sufficient for authoritative structural execution traces because branch membership and expression/control relationships are not yet normalized.

## NEXT — backend validation before schema v4

Before finalizing schema v4, run a Joern structural probe against a method that contains nested calls and multiple control constructs.

The probe should determine whether we can reliably extract:

- unique call node ID;
- source line;
- source column/order;
- AST parent;
- parent/child expression relationships;
- evaluation order;
- condition expression membership;
- control-structure identity;
- parent control structure;
- TRUE/FALSE or equivalent branch membership;
- loops;
- break/continue;
- try/catch/finally;
- throw;
- early return;
- short-circuit structure.

`CopyNoteMaterialFeature.copyMany` is a strong real-project validation target because it already contains many of these constructs.

## Schema v4 target

Only after the structural probe, introduce the minimum normalized execution model required to render the accepted semantics.

Current target concepts:

```text
CallSite
  callNodeId
  line
  column/order
  code
  declaredTarget
  possibleTargets
  astParentId
  parentExpressionId
  controlNodeId
  controlRole

ControlNode
  controlNodeId
  kind
  sourceText
  line/range
  conditionAst
  parentControlNodeId
  branches[]

ExpressionRelation
  parentExpressionId
  childExpressionIds[]
  evaluationOrder
```

Exact field names may change based on what the language frontends reliably expose.

## LATER

Possible later capabilities:

- runtime overlay distinguishing observed vs statically possible paths;
- richer architecture/dependency views;
- additional library/detail filtering if current external/application/depth controls prove insufficient;
- additional branch merge/join metadata if required for accurate visualization.

## OUT OF SCOPE FOR CURRENT MILESTONE

Do not spend the next iteration on:

- visual polish that depends on branch structure we have not extracted yet;
- pretending sibling calls are sequential;
- text heuristics as the final nested-expression solution;
- duplicating control-context data before a concrete need appears;
- inventing runtime certainty from static analysis;
- redesigning the whole graph viewer before the structural backend is validated.

## Acceptance test for the next milestone

Using a real method such as `CopyNoteMaterialFeature.copyMany`, the extracted structural model should let us distinguish at least:

```text
full outer expression
  ↳ nested inner call

condition
  ↳ calls used by the condition
  ↳ TRUE/FALSE outcomes

loop
  ↳ loop body
  ↳ continue/break where present

try
  ↳ normal body
  ↳ catch
  ↳ throw/rethrow

normal application call
  ↳ declared/possible targets
```

If Joern cannot reliably provide one of these relationships for a language, record that limitation explicitly rather than fabricating it.
