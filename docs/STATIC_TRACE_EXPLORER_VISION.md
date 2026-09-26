# Static Trace Explorer — product direction

## Goal

Build an AppMap-like explorer for **static end-to-end traces of possible execution paths**.

The central unit is not a global call graph. The user selects an entry method and explores possible paths incrementally.

The primary question is:

> What can execute from here, in what structural/evaluation order, through which conditions and branches, and where does each step belong in the codebase?

## Trace ordering

The downstream execution trace follows source/control-flow/evaluation structure.

It must **not** be reordered by folder/package/module.

Folder ownership remains visible as metadata and styling, but architecture grouping must not change execution-trace order.

## Visual ownership

Folder/module ownership must be obvious at a glance.

- method cards are colored by folder rule;
- sidebar methods may be grouped by folder;
- architecture/dependency-oriented views may group calls by folder;
- the downstream execution trace is not grouped/reordered by folder;
- search works across all groups;
- folder colors are configurable.

Configuration lives in:

`config/static-trace-viewer.config.json`

The browser UI may also override folder colors locally for quick experiments. These UI overrides are stored in browser localStorage and do not modify the repository config file.

## Method node

Each method node should ultimately show:

- folder/package/namespace;
- owner class/type;
- method name;
- file + line/range;
- return type;
- parameter names + types;
- method kind.

## Call site / edge

Each call site should ultimately show:

- original source expression;
- call-site file + line/range/position;
- declared target;
- possible/dispatch targets;
- argument expressions + inferred/declared types when available;
- resolution provenance.

A call site must have stable identity when possible so two distinct calls on the same source line are not accidentally merged.

## Expressions and nested calls

The original outer expression must remain visible.

Example:

```java
key(sourceElement.id())
```

The explorer should preserve:

```text
FULL EXPRESSION
key(sourceElement.id())
```

and also expose its internal evaluation structure:

```text
1 · INNER
    sourceElement.id()

2 · OUTER
    key(<result>)
```

The same principle applies to fluent/chained calls such as:

```java
something.another().again()
```

Final structural relationships must come from CPG/AST information, not text-containment guessing.

## Conditions and branches

Conditions are first-class control nodes.

Calls used to evaluate a condition must be visibly marked as condition calls rather than ordinary sequential calls.

Example target shape:

```text
IF !A() || !B()

condition evaluation
  1 · CONDITION CALL
      A()

  2 · CONDITION CALL
      B()

├─ TRUE
│   └─ ...
└─ FALSE
    └─ ...
```

Boolean `&&` and `||` should preserve short-circuit semantics when the backend provides enough structure.

Branches must be explicit and must never be visually flattened as if sibling calls necessarily execute sequentially.

Target control structures:

- if / else;
- switch / case;
- ternary;
- loops;
- break / continue;
- try / catch / finally;
- throw;
- early return.

## Error paths

Control-flow error paths come from actual structural information such as:

- throw;
- catch;
- branch membership;
- error-return/result branches where structurally identifiable.

Separately, error-like types may be styled by configurable UI rules. Default examples:

- `*Error`
- `*Exception`
- `*Failure`
- `Throwable`

Type styling is a presentation rule and must not be used as a substitute for control-flow analysis.

## Static semantics

Static trace means **what can happen**, not **what did happen**.

A later runtime overlay may distinguish observed paths from statically possible paths.

## Polymorphism

Keep the declared target and possible dispatch implementations separate.

The UI should not collapse an interface/base declaration and its possible runtime implementations into one ambiguous target.

## Navigation

Required interactions:

- downstream trace;
- upstream trace / impact analysis;
- configurable depth;
- lazy/collapsible exploration;
- search;
- folder ownership/grouping where appropriate;
- configurable folder colors;
- jump to source;
- constructor/external toggles;
- cycle protection.

## Current model status

Schema v3 is the stable baseline for the existing normalized model.

It already supports useful method/call/type information, but it does not yet contain the structural relationships required to render branches and nested evaluation authoritatively.

Viewer heuristics may be used for experiments only and must be labeled as heuristics.

## Next extractor milestone

Validate Joern/CPG support and then extract the minimum structural information for schema v4:

1. method return types and parameter names/types where available;
2. call argument expressions/types where available;
3. unique call-site identity and source position/order;
4. AST parent and expression relationships;
5. control structures and condition expressions;
6. branch membership of each relevant call/expression;
7. loop context;
8. try/catch/finally/throw context;
9. evaluation ordering for nested/chained expressions.

Do not add redundant fields before the Joern structural probe shows they are necessary.

## Architecture

```text
source
  ↓
Joern / CPG
  ↓
our extractor
  ↓
normalized static execution model
  ├─ static trace explorer
  ├─ architecture explorer
  ├─ impact analysis
  └─ optional runtime overlay
```
