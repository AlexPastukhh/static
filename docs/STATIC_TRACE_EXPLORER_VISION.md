# Static Trace Explorer — product direction

## Goal

Build an AppMap-like explorer for **static end-to-end traces of possible execution paths**.

The central unit is not a global call graph. The user selects an entry method and explores possible paths incrementally.

## Visual ownership

Folder/module ownership must be obvious at a glance.

- method cards are colored by folder rule;
- sidebar methods are grouped by folder;
- outgoing calls are grouped by target folder;
- search still works across all groups;
- folder colors are configurable.

Configuration lives in:

`config/static-trace-viewer.config.json`

The browser UI may also override folder colors locally for quick experiments. These UI overrides are stored in browser localStorage and do not modify the repository config file.

## Method node

Each node should ultimately show:

- folder/package/namespace;
- owner class/type;
- method name;
- file + line/range;
- return type;
- parameter names + types;
- method kind.

## Call edge

Each call edge should ultimately show:

- source expression;
- call-site file + line;
- declared target;
- dispatch targets;
- argument expressions + inferred types;
- resolution provenance.

## Branches

Branches must be explicit and must never be visually flattened as if calls execute sequentially.

Required shape:

```text
        IF result.failed()
         /             \
      TRUE             FALSE
       ↓                 ↓
 handleError           persist
```

Target control structures:

- if/else;
- switch/case;
- ternary;
- loops;
- try/catch/finally;
- throw;
- early return.

**Current schema v3 does not yet contain call-to-branch membership.**

Therefore viewer V2 must explicitly say that branch information is unavailable rather than invent branch structure.

Next extractor milestone:

1. method return types;
2. parameter names/types;
3. call argument expressions/types;
4. CFG/control structures;
5. branch membership of each call;
6. try/catch/finally/throw context.

## Error paths

Error-like types should be styleable. Default examples:

- `*Error`
- `*Exception`
- `*Failure`
- `Throwable`

Color semantics are UI/model rules, not Joern semantics.

## Static semantics

Static trace means **what can happen**, not **what did happen**.

A later runtime overlay can distinguish observed paths from statically possible paths.

## Polymorphism

Keep declared target and possible dispatch implementations separate.

## Navigation

Required interactions:

- downstream trace;
- upstream trace;
- configurable depth;
- lazy/collapsible exploration;
- search;
- folder grouping;
- configurable folder colors;
- jump to source;
- constructor/external toggles;
- cycle protection.

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
