# Next Step Plan — Production v4 Backend

> **HISTORICAL / COMPLETED MILESTONE PLAN**
>
> The production v4 backend milestone described below has been completed. The unchecked boxes and future-tense wording are retained as historical planning context and must not be used as the current work queue.
>
> Current state: `../CURRENT_WORK.md`  
> Current forward plan: `NEXT_MILESTONE_VIEWER_V4.md`  
> Engineering history: `PROJECT_TRACE.md`

## Status

This plan starts from repository state after commit:

```text
ba2bef11d013e62c6b4432590c3d97fc4f339ff5
Freeze static execution model v4 contract
```

The v4 **contract** is now frozen enough to implement against:

```text
schema/static-execution-model-v4.schema.json
docs/STATIC_EXECUTION_MODEL_V4.md
scripts/Validate-StaticExecutionModelV4.ps1
```

Schema v3 remains the stable existing production baseline during this milestone.

The viewer is intentionally **not** the next implementation target.

---

## Goal of this milestone

Build the first real production pipeline that turns a source project into a schema-valid
Static Execution Model v4:

```text
source project
    ↓
Joern frontend
    ↓
CPG
    ↓
all-method raw structural export
    ↓
source-semantic v4 normalization
    ↓
Static Execution Model v4
    ↓
v4 validation + regression checks
```

The milestone is complete only when the same pipeline succeeds on:

1. Java structural fixture;
2. Python structural fixture;
3. TypeScript structural fixture;
4. C# structural fixture;
5. real `gd-cap`.

---

# Corrections made after reviewing the previous plan

## Correction 1 — do not make the v3 application model a required join input

The previous plan proposed:

```text
v3 application-model
        +
raw structural export
        ↓
v4
```

That is risky.

Schema v3 does not contain unique structural call-site identity. Two source calls can have
the same caller, line, text, and target while still being different call sites. Joining
v3 call rows back onto structural call nodes could therefore become ambiguous.

### Revised rule

Reuse the **validated v3 target-resolution logic**, not the v3 JSON as the authoritative
call-site join source.

The raw v4 exporter must emit enough target information for each raw call node:

```text
rawCallNodeId
methodFullName/direct target
Joern possible callees
caller
AST/source identity
```

Then `Normalize-StaticExecutionModelV4.ps1` applies the already-proven v3 concepts:

```text
exact target resolution
alias resolution
arity protection
type hierarchy expansion
declared target
dispatch targets
possible targets
unresolved targets
internal/external classification
```

The v3 model remains a **regression oracle**, not a structural input dependency.

---

## Correction 2 — raw exporter should not own production/test policy

The raw structural exporter should export all relevant internal source methods represented
by the CPG.

Production/test filtering belongs to normalization, where the existing v3 filtering rules
can be reused consistently.

Reason:

```text
Joern extraction = facts
normalizer       = product/source semantics and scope
```

This avoids duplicating test-detection logic in Scala and PowerShell.

The final v4 output still defaults to:

```text
scope = production
```

with an explicit `IncludeTests` option if needed.

---

## Correction 3 — source text cannot blindly trust Joern `code` / `sourceCode`

The probes showed that source representation varies by frontend.

The v4 normalizer must use this priority:

```text
1. exact original source file slice when safely recoverable
2. trustworthy Joern sourceCode
3. trustworthy Joern code
4. diagnostic failure / skip synthetic artifact
```

Placeholder or lowering text such as these must not become public source expressions:

```text
<empty>
if ... : ...
$iterLocal0
hasNext()
next()
__next__()
$obj*
<operator>.alloc
```

`endLine` / `endColumn` remain optional when the frontend does not provide enough reliable
information to reconstruct them.

---

## Correction 4 — keep the current v3 pipeline untouched during implementation

Do not rewrite:

```text
scripts/Analyze-Project.ps1
scripts/joern-export.sc
scripts/Normalize-StaticModel.ps1
```

while building the first v4 pipeline.

Create parallel v4 entry points instead.

Only after the v4 fixtures and real `gd-cap` pass should the generic project analysis
entry point be reconsidered.

This gives us a working fallback and a clean v3-v4 regression baseline.

---

## Correction 5 — add a normalization report

Schema-valid JSON alone does not tell us whether the normalizer silently discarded
important structure.

Every v4 build should also produce a machine-readable diagnostics report, for example:

```text
normalization-report.json
```

It should count at least:

```text
raw methods
included methods
excluded test methods
raw calls
normalized call sites
raw controls
normalized controls
synthetic nodes suppressed
foreach normalizations
throw/raise normalizations
returns normalized
unresolved source snippets
unmapped raw calls
unmapped raw controls
ID collisions
validation result
```

Warnings should be explicit rather than hidden.

---

# Implementation deliverables

## 1. `scripts/joern-structural-export-v4.sc`

Purpose:

> Export raw structural facts for every relevant internal source method in one CPG.

It is not the semantic normalizer.

### Required method facts

For each method:

```text
raw node id
name
fullName
signature
owner
file
line
column
return type
parameters
AST root/body identity
```

Parameters must preserve raw Joern indexes because source-parameter cleanup happens later.

### Required AST facts

For relevant AST nodes:

```text
raw node id
node kind
code
sourceCode when available
line
column
offset / offsetEnd when available
order
argumentIndex when available
parent ids
child ids
```

Do not require generic `lineNumberEnd` / `columnNumberEnd`; the installed Joern version has
already proven those accessors are not portable on generic nodes.

### Required call facts

For every call, including operators needed for expression semantics:

```text
raw call id
name
code
methodFullName
typeFullName when available
signature
dispatch type
line
column
order
argumentIndex
AST parent
ancestor calls
arguments
possible Joern callees
control ancestry / region membership when available
```

Non-operator business calls and semantic operators must remain distinguishable.

### Required control facts

For control structures:

```text
raw control id
kind
parserTypeName when available
code/sourceCode
line/column
parent control ids
condition roots/nodes
TRUE/FALSE body roots/nodes
DO body
FOR init/update/body
TRY/CATCH/FINALLY body roots/nodes
```

### Required exit/case facts

Also export enough AST information to normalize constructs that are not uniformly emitted
as ControlStructure nodes:

```text
Return
JumpTarget
Python <operator>.raise
conditional operator
break / continue
```

### Output

Initial implementation may use one JSON file:

```text
raw-structural-model-v4.json
```

Do not introduce streaming/NDJSON until file size or memory measurements show it is needed.

---

## 2. `scripts/Export-StructuralModelV4.ps1`

Purpose:

> Build or reuse one CPG and invoke the all-method raw structural exporter.

Inputs:

```text
-Language
-Source
-OutputDirectory
-ReuseCpg
```

Supported languages:

```text
java
python
typescript
javascript
csharp
```

Responsibilities:

```text
locate Joern
select frontend
build CPG
run joern-structural-export-v4.sc
validate raw JSON can be parsed
print summary
```

It must keep the current known frontend options:

```text
Java       --enable-file-content
TS/JS      exclude node_modules and dist
Python     normal frontend invocation
C#         normal frontend invocation
```

The exporter should not rebuild the CPG when `-ReuseCpg` is explicitly requested and a
valid CPG already exists.

---

## 3. `scripts/Normalize-StaticExecutionModelV4.ps1`

Purpose:

> Convert raw frontend/CPG structure into the source-semantic v4 contract.

Proposed inputs:

```text
-RawStructuralModelPath
-Language
-SourceRoot
-OutputPath
-IncludeTests
```

Do **not** require `application-model.json` as an input.

### Normalization stages

Implement the normalizer as explicit stages rather than one long transformation.

Suggested internal stages:

```text
Load-RawModel
Build-SourceIndex
Select-IncludedMethods
Build-TypeIndex
Build-MethodIndex
Normalize-Methods
Normalize-Expressions
Normalize-Controls
Build-OrderedBodies
Resolve-CallTargets
Validate-References
Write-V4Model
Write-NormalizationReport
```

---

# Source normalization rules

## Paths

Public v4 paths:

```text
project-relative
forward slash separators
```

Example:

```text
gdcap/features/copy/CopyNoteMaterialFeature.java
```

Never expose machine-specific absolute paths in the model.

---

## Coordinates

Public v4 coordinates are:

```text
line   = 1-based
column = 1-based
```

The normalizer owns frontend-specific column correction.

Do not assume every Joern frontend uses the same raw column base.

---

## Source ranges

Start line/column should be retained whenever available.

`endLine` / `endColumn` are populated only when they can be derived safely.

They are not fabricated.

---

## Parameters

Normalize source-declared parameters to indexes:

```text
0..N-1
```

Synthetic implicit receivers such as Java/C#/TS `this` are removed.

Explicit source parameters such as Python `self` remain.

---

# Deterministic normalized IDs

Raw Joern ids are useful provenance but are not stable public identity.

Normalized IDs must be deterministic for the same source snapshot and normalizer version.

Use a canonical seed containing at least:

```text
language
project-relative file
method fullName
semantic node kind
source start line/column when available
structural AST/order path
```

The structural path is essential for repeated identical calls on the same line.

Recommended public id form:

```text
expr:<short-hash>
call:<short-hash>
ctrl:<short-hash>
branch:<short-hash>
```

Use a stable hash algorithm such as SHA-256 over the UTF-8 canonical seed.

Store raw Joern ids separately in:

```text
rawNodeIds[]
```

### Required regression

Run the same fixture twice from independently rebuilt CPGs.

Normalized public IDs must remain identical.

If they do not, the milestone is not complete.

---

# Expression normalization

The v4 expression tree should preserve only structure relevant to static trace semantics.

Required public kinds:

```text
CALL
OPERATOR
VALUE
OTHER
```

## Calls

A public CALL expression owns:

```text
source expression
type
ordered RECEIVER / ARGUMENT children
callSiteId
```

The full outer expression remains intact.

Nested argument/receiver calls remain explicit child expressions.

No text-containment heuristic is used.

---

## Operators that must be normalized in this milestone

At minimum:

```text
logical-and
logical-or
logical-not
conditional
assignment
addition / other operator only when needed to preserve relevant nesting
index-access
field-access when structurally relevant
```

We do not need to reproduce every Joern operator node.

---

## Short circuit

For:

```text
A && B
A || B
```

preserve ordered operand children and normalized operator identity.

The viewer can then derive the short-circuit execution alternatives without pretending both
operands always execute.

---

## Ternary

Normalize the three ordered children as:

```text
CONDITION
TRUE
FALSE
```

Ternary stays an expression, not a fabricated Control node.

---

# Control normalization

Required public controls:

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

---

## IF

Every normalized IF contains:

```text
conditionExpressionId
TRUE branch
FALSE branch
```

An IF without an explicit source `else` still gets an empty FALSE branch to represent the
fallthrough alternative.

TRUE/FALSE labels come from semantic body relations, never CFG successor order.

---

## Classic FOR

Normalize:

```text
initExpressionIds
conditionExpressionId
updateExpressionIds
BODY branch
```

---

## FOREACH

The normalizer, not the raw exporter, converts frontend-specific lowering into:

```text
FOREACH
iterationBinding
iterableExpressionId
BODY branch
```

Known frontend cases:

```text
Java enhanced-for      raw WHILE / ForEachStmt lowering
Python for-in          raw WHILE / iterator lowering
TypeScript for-of      raw WHILE / iterator lowering
C# foreach             raw FOR
```

The following must not appear as ordinary public body steps merely because the frontend
generated them:

```text
$iterLocal*
hasNext
next
__next__
iterator-result temporaries
```

---

## TRY / CATCH / FINALLY

Normalize one source TRY into one public TRY control with ordered branches:

```text
TRY
CATCH...
FINALLY
```

Do not also emit the same catch/finally regions as unrelated top-level controls.

Catch labels should preserve source-level declaration text/type when recoverable.

---

## THROW

Normalize:

```text
Java/TS/C# raw THROW
Python <operator>.raise
```

to public:

```text
THROW
```

with `valueExpressionId` where applicable.

Constructor/allocation lowering used to create an exception object is not exposed as
separate business execution steps unless a genuine source call needs to remain visible.

---

## RETURN

Normalize every source Return AST node to:

```text
RETURN
```

with optional `valueExpressionId`.

This includes early return inside branches/cases.

---

## SWITCH / MATCH

Normalize ordered:

```text
CASE
DEFAULT
```

branches from JumpTarget/source structure.

Do not treat a generic switch TRUE_BODY relation as a case.

---

# Call target resolution

Reuse the already-proven v3 resolution semantics inside the new v4 normalizer.

Required behavior:

```text
exact target match
safe alias match
arity protection
type hierarchy expansion
declared target
dispatch targets
possible targets
unresolved targets
resolution = joern | joern+hierarchy | unresolved
classification = internal | external | unresolved-on-internal-type
```

The v4 call site is keyed by its normalized structural identity.

This is what prevents same-line calls from being merged.

---

# Ordered method and branch bodies

`Method.body` and `Branch.body` are authoritative ordered semantic steps.

Build these from normalized source/AST containment, not folder grouping and not raw CFG
successor order.

A semantic node that belongs inside another normalized control branch must not also appear
as an unrelated top-level method step.

Likewise, a child expression is not duplicated as a sibling top-level expression step.

---

# Diagnostics and invariants

The normalizer should fail or warn explicitly for structural loss.

## Hard failures

Examples:

```text
duplicate normalized ID
dangling body reference
CALL expression without matching CallSite
CallSite linked to multiple CALL expressions
FOREACH without iterable/binding
IF without TRUE/FALSE branches
internal possible target missing from methods
invalid public path/coordinate normalization
```

These are already compatible with the existing v4 validator philosophy.

## Warnings / report counters

Examples:

```text
source snippet fallback to Joern code
unmapped raw operator
suppressed synthetic node
unmapped JumpTarget
unknown foreach lowering
unknown parser/control shape
unresolved call target
missing source column
missing source end range
```

Warnings belong in the normalization report, not silently discarded.

---

# Fixture pipeline

## 4. `scripts/Run-V4FixturePipeline.ps1`

The fixture runner should:

1. build/reuse each fixture CPG;
2. export raw v4 structural facts;
3. normalize v4;
4. run `Validate-StaticExecutionModelV4.ps1`;
5. run semantic assertions;
6. write a compact result summary.

Languages:

```text
java
python
typescript
csharp
```

Expected generated location:

```text
results/v4-fixtures/<language>/
    cpg.bin
    raw-structural-model-v4.json
    static-execution-model-v4.json
    normalization-report.json
```

CPG/raw scratch output should not be committed.

After the model format stabilizes, small normalized fixture JSON files may be promoted to
golden regression fixtures if useful.

---

# Required semantic fixture assertions

The fixture tests must verify more than JSON-schema validity.

## All languages

Verify:

```text
nested outer/inner call relation exists
repeated same-line calls have distinct normalized IDs
IF has TRUE/FALSE branches
logical AND/OR operand order is correct
ternary has CONDITION/TRUE/FALSE children
foreach source semantics are normalized
while remains WHILE, not FOREACH
TRY owns TRY/CATCH/FINALLY branches
RETURN nodes are normalized
BREAK/CONTINUE are structurally placed
synthetic iterator lowering is absent from public body steps
```

## Python

Additionally verify:

```text
match → MATCH
raise → THROW
```

## Java / TypeScript / C#

Additionally verify switch/case extraction.

---

# Focused switch fallthrough gate

The current repo correctly records switch fallthrough as the remaining known structural
gap.

Before declaring the v4 control model implementation complete, add one small fixture for
Java/TypeScript/C#:

```text
switch (mode) {
    case 1:
        callA();
        // deliberate fallthrough
    case 2:
        callB();
        break;
    default:
        callDefault();
}
```

Question to answer:

> Can the current v4 branch/body representation preserve the possible fallthrough path
> without inventing incorrect execution semantics?

### Decision rule

If yes:

```text
keep schema v4 unchanged
add regression assertion
```

If no:

```text
make the smallest evidence-driven schema revision
update contract docs
then continue
```

Do not postpone a discovered schema deficiency until viewer work.

---

# v3 → v4 regression checks

## 5. Target-resolution parity

Add a focused regression check, for example:

```text
scripts/Compare-V3V4TargetResolution.ps1
```

It should compare known calls from the existing labs and real project.

At minimum retain the already-proven polymorphic behavior:

```text
declared interface/base target
possible concrete implementations
hierarchy-assisted resolution where required
```

For repeated same-line calls, compare as a multiset or by structural source identity rather
than collapsing them into a v3-style key.

The purpose is not byte-for-byte v3/v4 equality.

The rule is:

> structural precision may improve in v4, but already-correct target resolution must not
> regress.

---

# Real-project gate: `gd-cap`

After all four fixture pipelines pass, run the production v4 pipeline on the whole Java
source tree for `gd-cap`.

Expected artifacts:

```text
results/real-projects/gd-cap/v4/
    raw-structural-model-v4.json
    static-execution-model-v4.json
    normalization-report.json
```

Use `CopyNoteMaterialFeature.copyMany` as the detailed acceptance method.

Required observations:

```text
outer + nested calls remain structurally related
condition calls live under conditions
TRUE/FALSE paths are explicit
foreach/for structure is source-semantic
continue/break are placed correctly
TRY/CATCH/THROW paths are explicit
RETURN is explicit
declared/possible targets survive
same-line calls are not merged
synthetic Joern iterator/allocation lowering is hidden
folder ownership does not reorder execution steps
```

Also inspect the normalization report for unexpected structural loss.

---

# Production orchestration

## 6. `scripts/Build-StaticExecutionModelV4.ps1`

Only after fixture normalization is stable, add one user-facing v4 orchestrator:

```text
-Language
-Source
-Output
-IncludeTests
-ReuseCpg
```

It should run:

```text
build/reuse CPG
    ↓
raw structural export
    ↓
v4 normalization
    ↓
v4 validator
    ↓
summary/report
```

Keep `Analyze-Project.ps1` on v3 during this milestone.

Do not replace the existing entry point until v4 has passed `gd-cap`.

---

# Assistant/user workflow during implementation

The implementation workflow should stay:

1. fetch current `main`;
2. apply and inspect changes on the assistant side;
3. run local static/schema checks there;
4. send one ready archive;
5. user applies final archive;
6. user runs only Joern/runtime checks that require the Windows environment;
7. user uploads compact outputs/errors when needed;
8. no intermediate manual editing and no long `git diff` pager review.

---

# Proposed file set for the milestone

```text
scripts/
    joern-structural-export-v4.sc
    Export-StructuralModelV4.ps1
    Normalize-StaticExecutionModelV4.ps1
    Run-V4FixturePipeline.ps1
    Compare-V3V4TargetResolution.ps1
    Build-StaticExecutionModelV4.ps1

docs/
    NEXT_STEP_V4_BACKEND_PLAN.md

existing and retained:
    joern-structural-probe.sc
    Run-StructuralProbe.ps1
    Validate-StaticExecutionModelV4.ps1
    Normalize-StaticModel.ps1
    Analyze-Project.ps1
```

A fallthrough fixture may extend the existing structural fixture files rather than creating
a second fixture family.

---

# Execution order

## Phase A — raw exporter

Deliver:

```text
joern-structural-export-v4.sc
Export-StructuralModelV4.ps1
```

Acceptance:

```text
all four fixtures export parseable all-method raw JSON
no probe method-name filter is required
raw call node identity is retained
```

---

## Phase B — normalization kernel

Deliver:

```text
Normalize-StaticExecutionModelV4.ps1
normalization-report.json
```

Implement first:

```text
methods/parameters
expressions/calls
IF
short circuit
ternary
RETURN
```

Then:

```text
FOR/FOREACH/WHILE
TRY/CATCH/FINALLY
THROW
SWITCH/MATCH
BREAK/CONTINUE
```

This order keeps failures localized while still converging on one final model.

---

## Phase C — four-language regression

Deliver:

```text
Run-V4FixturePipeline.ps1
Compare-V3V4TargetResolution.ps1
```

Acceptance:

```text
Java       PASS
Python     PASS
TypeScript PASS
C#         PASS
```

and normalized IDs are stable across repeated CPG rebuilds.

---

## Phase D — switch fallthrough gate

Run focused fallthrough tests.

Either confirm the current schema or make the smallest required evidence-driven adjustment.

---

## Phase E — real `gd-cap`

Generate and validate the all-method v4 model.

Inspect `copyMany` deeply plus target-resolution parity.

---

## Phase F — backend milestone freeze

Only when all previous phases pass:

```text
update docs with observed implementation limitations
commit v4 backend
```

Then the next milestone becomes:

```text
viewer consumes v4
```

At that point V2.4 text heuristics can finally be removed.

---

# Definition of done

This milestone is complete when all of the following are true:

- [ ] one CPG can be exported structurally for all relevant internal source methods;
- [ ] Java fixture produces schema-valid v4;
- [ ] Python fixture produces schema-valid v4;
- [ ] TypeScript fixture produces schema-valid v4;
- [ ] C# fixture produces schema-valid v4;
- [ ] normalized IDs survive independent CPG rebuilds;
- [ ] repeated same-line calls remain distinct;
- [ ] nested/full expressions are structural, not text heuristics;
- [ ] short-circuit structure is preserved;
- [ ] source foreach is normalized across all four languages;
- [ ] Python raise is normalized to THROW;
- [ ] TRY/CATCH/FINALLY is represented without duplicate top-level regions;
- [ ] RETURN / BREAK / CONTINUE placement is correct;
- [ ] switch/match cases are structural;
- [ ] switch fallthrough behavior is tested explicitly;
- [ ] v3 polymorphic target behavior does not regress;
- [ ] synthetic frontend lowering does not leak into normal trace steps;
- [ ] public paths and coordinates follow the v4 contract;
- [ ] `gd-cap` whole-project v4 generation passes validation;
- [ ] `copyMany` passes the detailed semantic acceptance review;
- [ ] normalization report contains no unexplained structural-loss warnings;
- [ ] existing v3 pipeline remains operational;
- [ ] viewer has not been redesigned prematurely.

---

# What is explicitly not part of this milestone

Do not spend this milestone on:

```text
viewer visual redesign
branch animation/polish
runtime overlay
new architecture views
new security/taint work
global graph redesign
premature schema fields without evidence
replacing v3 before v4 is proven
```

The backend must become authoritative first.
