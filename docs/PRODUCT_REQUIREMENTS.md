# Static Trace Explorer — Product Requirements

For accepted design/model decisions, `STATIC_TRACE_EXPLORER_DECISIONS.md` is authoritative.

## Product definition

Static Trace Explorer is an AppMap-like explorer for **possible static execution paths**.

The user selects an entry method and incrementally explores possible downstream/upstream paths.

It is not a runtime recorder and it does not render the whole application graph by default.

## MUST — semantics

The explorer must:

- represent what can happen, not claim what did happen;
- start from a selected entry method;
- support downstream exploration;
- support upstream/incoming impact analysis;
- preserve source/control-flow/evaluation structure;
- preserve folder/module ownership without reordering the trace;
- protect against cycles;
- support configurable depth;
- keep declared polymorphic target separate from possible implementations.

## MUST — methods

Expose where available:

- folder/package/namespace;
- owner type;
- method/function name;
- source file + range;
- parameter names/types;
- return type;
- method kind.

## MUST — call sites

Expose where available:

- original source expression;
- stable normalized call-site identity;
- source file + position;
- declared target;
- possible/dispatch targets;
- argument expressions/types;
- resolution provenance.

Distinct source call sites must not be merged merely because caller/line/text/target are equal.

## MUST — expressions

For nested/chained calls:

- preserve the original full outer expression;
- expose nested/receiver calls;
- expose structural/evaluation relationships;
- derive final relationships from CPG/AST normalization, not text guessing.

## MUST — control flow

Conditions are first-class.

Required concepts:

- if / else;
- switch / case;
- match;
- ternary;
- classic loops;
- foreach / for-in / for-of;
- loop condition/body;
- break / continue;
- try / catch / finally;
- throw / raise;
- early return.

Branches must never be flattened into an unconditional sibling-call list.

## MUST — short circuit

When a language/operator is short-circuiting, the viewer must preserve that semantic.

Do not render every condition operand as always executed.

## MUST — errors

Structural error paths derive from actual control structure.

Configurable type patterns (`*Error`, `*Exception`, `*Failure`, `Throwable`) are presentation rules only.

## MUST — ownership/UI

Required capabilities:

- folder badge/color;
- configurable folder colors;
- sidebar grouping by folder;
- search;
- lazy/collapsible exploration;
- jump to source;
- constructor toggle;
- external-call toggle.

Architecture/dependency views may group by folder; execution traces may not.

## Language scope

Current normalized target:

- Java;
- Python;
- TypeScript / Node;
- C# / .NET.

Frontend precision may differ. Preserve available information without fabricating missing precision.

## Model status

### v3

Schema v3 remains the stable current call/type baseline and continues to support:

- types/methods;
- direct/multi-hop calls;
- ownership;
- incoming/outgoing navigation;
- polymorphic targets;
- source lines.

### v4 contract

The four-language structural probe is complete enough to define the first source-semantic v4 contract.

See:

```text
schema/static-execution-model-v4.schema.json
docs/STATIC_EXECUTION_MODEL_V4.md
docs/STRUCTURAL_PROBE_FINDINGS_CROSS_LANGUAGE.md
```

V4 adds:

- source-declared parameters/return types;
- stable normalized call-site identity;
- nested semantic expressions;
- explicit controls/branches;
- ordered method/branch bodies;
- source-semantic loop normalization;
- try/catch/finally/throw/return structure.

## NEXT — implementation

Implement and validate the v4 backend before another major viewer redesign:

1. export raw structural data for all production methods;
2. normalize raw frontend structures to v4 source semantics;
3. validate the four language fixtures;
4. validate real `gd-cap`;
5. migrate the viewer from V2.4 heuristics to v4 relationships.

## Acceptance

On `CopyNoteMaterialFeature.copyMany`, the model must be able to represent:

```text
full outer expression
  ↳ nested inner call

condition
  ↳ condition expressions/calls
  ↳ TRUE/FALSE outcomes

foreach / for
  ↳ source binding/iterable or init/condition/update
  ↳ loop body
  ↳ continue/break

try
  ↳ TRY body
  ↳ CATCH
  ↳ THROW/rethrow

normal call
  ↳ declared/possible targets

return
  ↳ returned expression
```

For frontend limitations, record the limitation explicitly rather than fabricating precision.

## Current known limitation

Switch/match case structure is available, but exact legal case-fallthrough behavior still needs a focused regression fixture before complete switch-path fidelity is claimed.
