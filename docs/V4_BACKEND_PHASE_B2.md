# V4 backend implementation - Phase B2

Phase B2 extends the schema-v4 normalizer from the B1 expression/control kernel to the
remaining control-flow constructs exercised by the four structural fixtures.

Implemented in this slice:

```text
classic FOR
source FOREACH across Java / Python / TypeScript / C#
WHILE
SWITCH / MATCH with CASE / DEFAULT branches
TRY with owned TRY / CATCH / FINALLY branches
THROW, including Python raise
BREAK / CONTINUE
branch-body placement
method-local recursive Block traversal
frontend iterator-lowering suppression
```

B1 behavior remains covered by the fixture runner:

```text
methods/types
source parameters
1-based coordinates
deterministic public ids
CALL / OPERATOR / VALUE expressions
nested calls
IF TRUE/FALSE
short-circuit structure
ternary
RETURN
call-site target structure
```

## FOREACH normalization

The raw frontend shapes differ:

```text
Java       WHILE + parserTypeName=ForEachStmt
Python     lowered WHILE
TypeScript lowered WHILE
C#         lowered FOR
```

B2 reconstructs source-level FOREACH from the original source snippet. The public control
contains:

```text
iterationBinding
iterableExpressionId
BODY branch
```

Iterator machinery is not emitted as public body steps.

## TRY normalization

Raw CATCH and FINALLY controls are not emitted as unrelated public controls. Their raw ids
are retained as provenance on the enclosing TRY, which owns ordered TRY/CATCH/FINALLY
branches.

## THROW normalization

Java, TypeScript and C# raw THROW controls become v4 THROW. Python `<operator>.raise`
also becomes v4 THROW.

Allocation/iterator lowering is not added as a separate method-body step. A source-level
throw value expression is linked through `valueExpressionId`.

## SWITCH / MATCH

JumpTarget nodes are grouped into ordered CASE / DEFAULT branches. This slice verifies
the existing no-fallthrough fixture structure.

Deliberate switch fallthrough remains the next focused schema/semantic gate from the plan.

## Assistant-side checks

Before packaging this slice:

```text
PowerShell files are ASCII-only
balanced PowerShell bracket scan passes
no `$name:` interpolation hazards remain
all raw controls in the four target fixture methods map structurally
all normalized target controls have a method/branch placement in structural simulation
FOREACH parsing succeeds for all four fixture languages
SWITCH/MATCH extraction finds 2 CASE + 1 DEFAULT in every fixture
no target fixture raw control remains unexplained in structural simulation
```

The actual PowerShell normalizer and schema validator still require the Windows project
environment for the final execution gate.
