# Static Trace Explorer — Decisions

This file records accepted product, visualization, and model decisions so the direction does not drift while iterating.

## Authority

This is the decision record.

If an older vision, viewer experiment, README, or prototype conflicts with this file, this file has precedence until the conflicting document/code is reconciled.

Experimental viewer behavior is not automatically a product decision.

---

## 1. Trace ordering

The downstream execution trace must **not** be reordered by folder/package.

Order should follow source/control-flow/evaluation structure.

Folder/package remains visual metadata:

- folder badge;
- folder color;
- architectural ownership;
- sidebar grouping;
- optional dependency-oriented views.

The sidebar may group methods by folder. Architecture/dependency views may group by folder. The execution trace may not be reordered by folder.

---

## 2. Full expression + nested calls

For nested expressions, keep the full outer source expression.

Example:

```java
key(sourceElement.id())
```

The outer call is shown as the **full expression**:

```text
OUTER / FULL EXPRESSION
key(sourceElement.id())
```

The nested call is also shown explicitly:

```text
INNER / NESTED CALL
sourceElement.id()
```

The UI should make the relationship obvious rather than displaying the two calls as unrelated siblings.

Preferred conceptual representation:

```text
FULL EXPRESSION
key(sourceElement.id())

evaluation:
  1 · INNER
      sourceElement.id()

  2 · OUTER
      key(<result>)
```

The original full expression must never be lost.

---

## 3. Fluent / chained calls

For expressions such as:

```java
something.another().again()
```

keep the original expression visible:

```text
FULL EXPRESSION
something.another().again()
```

When structural information is available, also show the internal evaluation chain:

```text
something
   ↓
another()
   ↓
again()
```

This should be derived from AST/call structure, not guessed from text in the final model.

---

## 4. Same-line repeated calls

Do **not** blindly deduplicate calls using only:

```text
caller + line + code + target
```

Two calls on the same line may be distinct AST call-sites.

The final execution model should preserve enough structural identity to distinguish them, targeting at least:

```text
callNodeId
source line
source column / order
AST parent id
```

Until those identifiers exist, UI heuristics must be marked as heuristics.

---

## 5. Conditions are first-class nodes

Conditions must be represented explicitly.

Example source:

```java
if (!FileNameRules.isSafeNoteName(sourceNote)
    || !FileNameRules.isSafeNoteName(targetNote)) {
    throw new IOException(...);
}
```

Target visualization:

```text
IF
!isSafeNoteName(sourceNote)
|| !isSafeNoteName(targetNote)

condition evaluation:
  1 · CONDITION CALL
      FileNameRules.isSafeNoteName(sourceNote)

  2 · CONDITION CALL
      FileNameRules.isSafeNoteName(targetNote)

        ┌─ TRUE  → ERROR BRANCH → throw IOException
        └─ FALSE → continue
```

Calls used to evaluate the condition must be marked as condition calls, not ordinary sequential calls.

---

## 6. Short-circuit conditions

Boolean operators such as `&&` and `||` should preserve short-circuit semantics when the backend provides enough structure.

Example:

```text
A()
 │
 ├─ short-circuit branch
 │
 └─ evaluate B()
```

Do not present all condition calls as if all of them always execute.

---

## 7. Branches

Branches must never be flattened into a plain list.

Required branch/control concepts:

- if / else;
- switch / case;
- ternary;
- loop condition/body;
- continue / break;
- try / catch / finally;
- throw;
- early return.

Target shape:

```text
IF condition
├─ TRUE
│   └─ ...
└─ FALSE
    └─ ...
```

Sibling calls must not imply sequential execution unless the execution model actually establishes that order.

---

## 8. Call roles

A call-site should eventually have an explicit semantic role when it can be derived structurally.

Candidate roles:

```text
NORMAL_CALL
CONDITION_CALL
LOOP_CONDITION_CALL
NESTED_ARGUMENT_CALL
CHAIN_CALL
RETURN_EXPRESSION_CALL
ERROR_PATH_CALL
CATCH_PATH_CALL
```

These roles are semantic/UI metadata derived from AST + control-flow structure.

The exact stored enum may change after the Joern structural probe; the product requirement is the ability to distinguish these meanings in the resulting model/UI.

---

## 9. Error paths

Error paths should be visually distinguishable.

Control-flow error paths must come from structural information such as `throw`, `catch`, branch membership, or other explicit flow.

Separately, error-like types may use configurable style rules. Default examples:

```text
*Error
*Exception
*Failure
Throwable
```

Type-name styling belongs to our configurable UI/model layer.

Type-name patterns must **not** be used as a substitute for determining control-flow error paths.

Error branch styling must not be hard-coded to one language.

---

## 10. Folder ownership

Folder/package ownership should be immediately visible on every method card.

Example:

```text
features/copy
CopyNoteMaterialFeature.copyMany
```

Folder colors are configurable.

The same ownership metadata should be usable by both humans and AI.

Folder grouping is appropriate for the sidebar and architecture/dependency views, but not for reordering the downstream execution trace.

---

## 11. Current V2.4 heuristics

V2.4 may temporarily infer nested expressions by same-line text containment, for example:

```text
sourceElement.id()
key(sourceElement.id())
```

This is only an experiment.

The final implementation must use structural relations from the CPG/AST.

---

## 12. Backend target for schema v4

Schema v4 should be created only after the structural probe demonstrates what Joern can reliably provide.

The target is the minimum model needed to represent the accepted UI semantics without fabricating structure.

### Call site target

```text
callNodeId
line
column / order
code
declaredTarget
possibleTargets
AST parent id
parent expression id
controlNodeId
controlRole
```

### Control node target

```text
controlNodeId
kind
source text
line/range
condition AST
parentControlNodeId
branches[]
```

### Expression relationships target

```text
parentExpressionId
childExpressionIds[]
evaluationOrder
```

### Branch membership target

```text
TRUE
FALSE
CASE
LOOP_BODY
CATCH
FINALLY
ERROR
RETURN
```

These are target fields/concepts, not a promise that every language frontend exposes every field identically.

Do not add redundant representations until a concrete need is demonstrated.

---

## 13. UI principle

The trace should answer:

> What can execute from here, in what structural/evaluation order, through which conditions/branches, and where does every step belong in the codebase?

The UI should preserve both:

1. the original source expression;
2. the decomposed structural/evaluation view.

Neither should replace the other.

---

## 14. Runtime semantics

This remains a static trace:

```text
what CAN happen
```

not:

```text
what DID happen
```

A later runtime overlay may mark observed paths separately.

---

## 15. Things not yet promoted to requirements

The following may become useful, but are **not** current mandatory schema requirements until validated by the structural probe:

- a separate `sourceOrder` field in addition to source position and `evaluationOrder`;
- a duplicated `controlContext[]` stack if `parentControlNodeId` relationships are sufficient;
- an explicit branch merge/join-point field;
- additional detail-level modes beyond the existing application/external/constructor/depth controls.

Do not add them preemptively.
