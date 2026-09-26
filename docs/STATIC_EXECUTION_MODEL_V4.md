# Static Execution Model v4

## Status

The four-language structural probe is complete enough to freeze the first source-semantic v4 contract.

Schema v3 remains the stable production baseline until the v4 extractor/normalizer/viewer migration is complete.

Machine-readable schema:

```text
schema/static-execution-model-v4.schema.json
```

## Architecture

```text
source code
  ↓
Joern frontend / CPG
  ↓
raw structural extraction
  ↓
source-semantic normalization
  ↓
Static Execution Model v4
  ↓
viewer / search / AI / later runtime overlay
```

The source-semantic normalization step is mandatory because equivalent source constructs are lowered differently by different Joern frontends.

## Static meaning

The model represents:

```text
what CAN happen
```

not:

```text
what DID happen
```

Runtime-observed paths can be overlaid later without changing the static meaning.

## Ordering

`Method.body` and every `Branch.body` are ordered arrays of semantic step references.

They are authoritative for structural trace order.

Folder/package ownership never reorders them.

`Expression.children` is also ordered and is authoritative for nested expression structure.

No duplicate `sourceOrder` or `evaluationOrder` field is stored.

## Source contract

Public v4 source data uses:

- project-relative paths;
- `/` path separators;
- 1-based lines;
- 1-based columns.

The public model preserves source-level text.

Raw lowering details such as the following must not appear as ordinary trace steps:

```text
$iterLocal0
hasNext()
next()
__next__()
_result_0
$obj4
<operator>.alloc
```

They may remain in raw/debug provenance.

## IDs

Method identity remains the normalized method `fullName`.

`CallSite.id`, `Expression.id`, `Control.id`, and `Branch.id` are deterministic normalized ids.

Raw Joern ids are CPG-local provenance only and may be retained in `rawNodeIds`.

A normalized id must include enough source/structure context to distinguish two identical calls on the same line. Recommended seed components:

```text
language
project-relative file
method fullName
semantic kind
normalized source anchor
AST/order path
```

## Method

A method/function stores:

- name/fullName/owner;
- kind;
- signature;
- return type;
- source range;
- source-declared parameters;
- ordered semantic body.

Synthetic implicit receivers (`this`) are not source parameters.

Explicit source parameters such as Python `self` remain parameters.

## Expression

Expression kinds:

```text
CALL
OPERATOR
VALUE
OTHER
```

Every expression preserves its source snippet.

Nested evaluation is represented by ordered `children`.

Child roles include:

```text
RECEIVER
ARGUMENT
OPERAND
BASE
INDEX
CONDITION
TRUE
FALSE
VALUE
OTHER
```

This is sufficient for:

- full outer expression + nested calls;
- fluent/chained receiver calls;
- repeated same-line calls;
- short-circuit boolean expressions;
- ternary expressions.

Operators are normalized to source-semantic names where useful, for example:

```text
logical-and
logical-or
logical-not
conditional
assignment
addition
index-access
field-access
```

The normalizer does not need to reproduce every raw Joern operator node; only structure relevant to the static trace must survive.

## CallSite

A `CallSite` contains target-resolution semantics:

- deterministic id;
- caller;
- `expressionId` linking to the CALL expression that owns the source text/arguments;
- declared target;
- dispatch targets;
- possible targets;
- unresolved targets;
- resolution provenance;
- internal/external classification.

Call arguments are not duplicated on `CallSite`.

They are the ordered `ARGUMENT` / `RECEIVER` children of the linked CALL expression, whose child expressions already carry source text and type.

This avoids storing two competing argument structures.

Incoming/outgoing indexes are built from `caller` and target arrays.

## Control

Normalized control kinds:

```text
IF
SWITCH
MATCH
FOR
FOREACH
WHILE
DO_WHILE
TRY
THROW
RETURN
BREAK
CONTINUE
```

Control fields are interpreted by kind:

```text
IF / WHILE / DO_WHILE / FOR
  conditionExpressionId

SWITCH / MATCH
  valueExpressionId

RETURN / THROW
  valueExpressionId

FOR
  initExpressionIds
  updateExpressionIds

FOREACH
  iterationBinding
  iterableExpressionId
```

### FOREACH

`iterationBinding` preserves the source binding, for example:

```text
Element sourceElement
i, item
const item
string item
```

`iterableExpressionId` points to the source iterable expression.

Frontend iterator lowering is not shown as source execution steps.

## Branch

Normalized branch kinds:

```text
TRUE
FALSE
CASE
DEFAULT
BODY
TRY
CATCH
FINALLY
```

Expected shapes:

```text
IF
├─ TRUE
└─ FALSE
```

An IF without source `else` still gets an empty FALSE branch, representing the fallthrough possibility.

```text
FOR / FOREACH / WHILE
└─ BODY
```

```text
TRY
├─ TRY
├─ CATCH
└─ FINALLY
```

```text
SWITCH / MATCH
├─ CASE
├─ CASE
└─ DEFAULT
```

Case/catch labels remain source-level labels.

## Short-circuit semantics

`logical-and` and `logical-or` are semantic operator expressions with ordered operands.

The viewer must interpret their operator semantics correctly:

```text
A && B
A false  → B not evaluated
A true   → evaluate B
```

```text
A || B
A true   → B not evaluated
A false  → evaluate B
```

Therefore condition calls are not rendered as if every operand always executes.

## Call roles are derived, not duplicated

The viewer can derive call meaning from containment:

- under IF condition → condition call;
- under loop condition → loop-condition call;
- nested under another call argument → nested argument call;
- under RETURN → return-expression call;
- under THROW → error-path call;
- inside CATCH branch → catch-path call.

V4 therefore does not store a second `callRole`/`controlRole` enum.

## Relationship to v3

V4 carries forward validated v3 semantics:

- types/inheritance;
- method identity;
- declared targets;
- possible targets;
- dispatch targets;
- unresolved targets;
- hierarchy-assisted resolution;
- external vs unresolved-on-internal-type classification;
- production/test filtering.

Structural additions are:

- source-declared parameters and return types;
- semantic expressions;
- semantic controls/branches;
- ordered method/branch bodies;
- stable normalized call-site identity.

## Next implementation milestone

Do not redesign the viewer again yet.

Implement in this order:

1. extend raw Joern export from one probe method to all production methods;
2. implement source-semantic v4 normalization;
3. generate v4 models for Java/Python/TypeScript/C# fixtures;
4. validate them with `Validate-StaticExecutionModelV4.ps1`;
5. generate a real `gd-cap` v4 model;
6. replace V2.4 nested-call/control heuristics with v4 relationships;
7. then iterate the branch UI using exported viewer result JSON.
