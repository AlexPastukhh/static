# Structural probe — cross-language findings

This is the evidence record used to freeze the first normalized Static Execution Model v4 contract.

The probe set contains:

| target | AST nodes | calls/operators | controls | CFG nodes | CFG edges |
|---|---:|---:|---:|---:|---:|
| Java `CopyNoteMaterialFeature.copyMany` | 553 | 196 | 43 | 495 | 444 |
| Python fixture | 210 | 58 | 14 | 186 | 172 |
| TypeScript fixture | 249 | 64 | 17 | 221 | 204 |
| C# fixture | 199 | 56 | 18 | 182 | 144 |

The raw probe format is diagnostic evidence, **not** the public v4 model.

## Confirmed across the four frontends

### Distinct call-site identity

Raw CPG ids, source position, AST parentage, and argument/order information distinguish separate call sites.

This includes repeated identical calls on the same source line.

Therefore the final model must not deduplicate on:

```text
caller + line + code + target
```

### Nested/full expressions

AST parent/child relations distinguish:

- outer call;
- nested argument call;
- receiver call;
- sibling calls inside one operator expression.

The final viewer can keep the full outer expression while rendering the nested evaluation relationship without text-containment guessing.

### `if` / `else`

All four fixtures expose the condition subtree and distinct TRUE/FALSE body regions for an explicit `else`.

TRUE/FALSE polarity comes from semantic control-body relations, not from raw CFG successor order.

### Short circuit

The frontends preserve short-circuit operators structurally:

```text
<operator>.logicalAnd
<operator>.logicalOr
```

with ordered operands.

Logical negation is also represented as an operator (`logicalNot` / `not` depending on frontend).

V4 normalizes these as operator expressions. The operator semantics plus ordered children are sufficient; no duplicate `evaluationOrder` field is required.

### Ternary / conditional expression

Java, Python, TypeScript and C# expose `<operator>.conditional` with ordered arguments:

```text
1 condition
2 true expression
3 false expression
```

Ternary therefore remains an expression-level conditional rather than a fabricated control node.

### Classic `for`

Java, TypeScript and C# expose classic `for` with separate semantic regions for:

```text
condition
init
update
body
```

### Source `foreach` / `for ... in` / `for ... of`

Equivalent source loops are lowered differently:

- Java enhanced-for arrives as raw `WHILE` with `parserTypeName = ForEachStmt`;
- Python `for ... in` arrives as raw `WHILE` with iterator/`__next__` machinery;
- TypeScript `for ... of` arrives as raw `WHILE` with iterator machinery;
- C# `foreach` arrives as raw `FOR`.

This proves that a frontend/source normalization layer is mandatory.

V4 exposes one source-semantic `FOREACH` control with:

```text
iterationBinding
iterableExpressionId
BODY branch
```

Synthetic iterator details are extractor provenance and do not appear as ordinary user-visible trace steps.

### `switch` / Python `match`

Java/TypeScript/C# expose `SWITCH`; Python exposes `MATCH`.

Case/default labels appear as `JumpTarget` nodes, but exact placement is frontend-specific.

V4 normalizes those labels into ordered `CASE` / `DEFAULT` branches.

A switch's raw generic body relation is **not** itself a case branch.

### `try` / `catch` / `finally`

All four fixtures expose usable semantic regions for try/catch/finally.

V4 stores one normalized `TRY` control whose ordered branches are:

```text
TRY
CATCH...
FINALLY
```

### Throw / raise

Java/TypeScript/C# expose source throws as `THROW` controls.

Python `raise` is represented as `<operator>.raise`.

Both normalize to one source-semantic `THROW` control.

### Return / early return

All four fixtures contain AST `Return` nodes, including returns inside switch/match cases and final returns.

V4 normalizes every source return to `RETURN`, with an optional value expression.

### Break / continue

All four frontends expose break/continue structurally.

They normalize to branchless `BREAK` and `CONTINUE` controls.

## Source normalization findings

### Column bases differ

Raw columns are not portable:

- Java and Python behave as 1-based in these probes;
- TypeScript and C# behave as 0-based.

Public v4 coordinates are therefore normalized to **1-based** line/column coordinates.

### Offsets are not portable

Offsets were broadly available for Java/Python source-backed nodes, but absent from the TypeScript/C# fixtures.

Offsets remain raw extractor provenance; they are not required public v4 fields.

### `sourceCode` is not uniformly authoritative

Examples from the probe:

- Java source slices are strong when file content is available;
- Python method/control nodes may expose placeholders such as `<empty>` or `if ... : ...`;
- TypeScript method text can be truncated by Joern's code-length limit;
- C# source text was strong in the fixture.

The normalizer therefore reconstructs public `source.text` from the original project source when raw node text is placeholder, lowered, or truncated.

### Parser metadata is not a public semantic contract

`parserTypeName` is very useful in Java (`ForEachStmt`) but is generic or empty in other frontends (`BabelNodeInfo`, `DotNetNodeInfo`, `<empty>`).

It remains normalization evidence, not a public v4 field.

## Public normalization decisions

V4 public paths use project-relative forward slashes:

```text
features/copy/CopyNoteMaterialFeature.java
```

V4 public source coordinates are 1-based.

Synthetic implicit receivers such as Java/C#/TypeScript `this` are omitted from source parameter lists. Explicit source parameters such as Python `self` remain source parameters.

Raw CPG ids may be preserved in `rawNodeIds`, but public semantic ids are deterministic normalized ids.

## Things intentionally not promoted

The probe did not demonstrate a need for:

- duplicate `controlContext[]`;
- separate `sourceOrder`;
- separate `evaluationOrder`;
- mandatory branch merge/join ids.

Order is represented by ordered method/branch bodies and ordered expression children.

Nesting is represented by those same containment relations.

## Remaining focused regression gap

The fixture contains switch/match cases but does not specifically validate legal case fallthrough behavior.

Before claiming complete switch-path fidelity, add one small fallthrough regression fixture for Java/TypeScript/C#.
