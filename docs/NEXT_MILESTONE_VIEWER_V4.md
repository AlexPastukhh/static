# Next Milestone — Product v4 Pipeline and Viewer

Status: **CURRENT forward plan**  
Depends on: frozen Static Execution Model v4 backend  
Current-state owner: `../CURRENT_WORK.md`

The previous backend milestone is complete. This plan starts from the accepted whole-project backend baseline and moves Static Trace Explorer from a backend/tooling repository toward a reusable application.

---

## Goal

Establish one reusable end-to-end product path:

```text
arbitrary supported source project
  -> analyze / reuse cached CPG
  -> produce validated Static Execution Model v4
  -> choose entry method
  -> render source-semantic static execution structure
  -> expand internal calls lazily
  -> inspect provenance / possible targets / branches
  -> search / export current result
```

The milestone is successful when a second project can be analyzed and explored without manually assembling internal backend runners or relying on V2 text heuristics. Slice 1 produces only the validated reusable analysis bundle; Slices 1-3 together form the first minimal end-to-end source-to-viewer path.

---

## Non-negotiable constraints

Do not regress these accepted semantics:

- v4 backend is the source-semantic public contract;
- trace order is execution/control/evaluation order, not folder grouping;
- ownership/folder/package is metadata and visual context;
- `FEATURE`, `DOMAIN`, `SHARED`, `INFRASTRUCTURE`, and `ORCHESTRATION` are optional viewer/config roles, never fabricated backend v4 facts;
- orchestration is shown by configured ownership plus real call/control relationships, not by forcing a new schema role;
- nested source expressions preserve both full outer expression and inner calls;
- conditions expose their expressions/calls;
- branches remain alternatives, not flattened sequential siblings;
- declared target and possible dispatch targets remain separate;
- lazy expansion is preferred over whole-program graph rendering;
- switch fallthrough is derived in the path/viewer layer from ordered branches plus terminating control evidence;
- runtime-observed paths, if added later, remain a separate overlay.

Do not modify the v4 schema/normalizer merely to make HTML rendering easier.

---

# Slice 1 — Unified v4 analysis entrypoint

## Problem

The repository currently has proven v4 building blocks but no single product-grade command for arbitrary projects.

`scripts/Analyze-Project.ps1` belongs to the older v3/generic path and should not silently become the new v4 contract by patching unrelated behavior into it.

## Deliverable

Add a new explicit v4 entrypoint, recommended name:

```text
scripts/Analyze-StaticTrace.ps1
```

Suggested interface:

```powershell
.\scripts\Analyze-StaticTrace.ps1 `
    -Source C:\path\to\project `
    -Output C:\path\to\analysis
```

Initial options:

```text
-Source
-Output
-Language auto|java|python|typescript|csharp
-Scope production|all
-ReuseCpg
```

The runner should orchestrate existing backend pieces rather than duplicate their logic:

```text
language/front-end selection
  -> CPG build or reuse
  -> Export-StructuralModelV4.ps1
  -> Normalize-StaticExecutionModelV4.ps1
  -> Validate-StaticExecutionModelV4.ps1
  -> compact analysis report
```

Canonical output bundle:

```text
<analysis>/
  static-execution-model-v4.json
  normalization-report.json
  analysis-report.json
  cpg.bin                # cache/local artifact when retained
```

## Acceptance

Slice 1 ends at a validated analysis bundle; it does **not** need to render the viewer yet.

- [ ] works on the existing four structural fixture languages;
- [ ] works on GD-CAP without changing v4 semantics;
- [ ] one command clearly reports language, scope, model path and validation result;
- [ ] failed validation returns a non-zero exit;
- [ ] old v3 entrypoint remains available during migration;
- [ ] PowerShell 5.1 compatible.

---

# Slice 2 — Analysis fingerprint and CPG cache

## Goal

Avoid paying frontend/CPG cost again when source and relevant frontend inputs are unchanged.

## Minimum design

Create an analysis fingerprint from at least:

```text
normalized source file inventory/content signal
+ selected language/frontend
+ frontend/tool version relevant to CPG meaning
+ analysis scope/config inputs that require rebuilding the CPG
```

Keep CPG reuse distinct from model regeneration:

```text
source/frontend unchanged
  -> reuse CPG
normalizer/viewer changed
  -> regenerate v4 model/viewer from cached CPG
```

Do not treat `-ReuseCpg` as proof that the CPG matches current source. The cache should make that relationship explicit.

## Acceptance

- [ ] cache hit/miss is visible in `analysis-report.json`;
- [ ] changed source invalidates CPG reuse;
- [ ] unchanged source permits v4 normalizer/viewer iteration without rebuilding frontend state;
- [ ] cache files remain out of Git by default.

---

# Slice 3 — Viewer v4 skeleton

## Goal

Create a new viewer path that consumes v4 directly. Do not retrofit semantic behavior into V2 text-containment heuristics.

## First screen

Minimum useful UI:

```text
Static Trace Explorer
Project / analysis identity
Search entry method [________________]

matching methods...
```

Selecting a method should show:

```text
owner / namespace / package
method name + signature
source file + line
return type
parameters
ordered method body
```

## Data layer

Build indexes once in the viewer/runtime rather than repeatedly scanning the full JSON:

```text
methodById/fullName
expressionById
controlById
callSiteById
possibleTarget -> method index where internal
source/folder ownership index
search index
```

Keep the renderer separated from model indexing so future large-model loading can be optimized without changing semantics.

## Acceptance

- [ ] opens a v4 model directly;
- [ ] method search works;
- [ ] one selected method renders ordered body items from v4 IDs/relations;
- [ ] no V2 nested-call text heuristic is used for v4 rendering;
- [ ] source provenance is visible.

---

# Slice 4 — Expression rendering

## Goal

Make nested/chained evaluation understandable without losing the original source expression.

Example target:

```java
new CopyOutcome(
    prepared.stream().map(PreparedCopy::element).toList(),
    createdAssets.size()
)
```

Desired structural view:

```text
FULL: new CopyOutcome(...)

new CopyOutcome
├─ prepared.stream()
│  └─ map(...)
│     └─ toList()
└─ createdAssets.size()
```

Exact visual tree shape may vary, but semantics must come from v4 expression children/roles.

Show structural roles where useful:

```text
receiver
argument
operand
condition
true
false
base/index
other
```

## Acceptance

- [ ] full source expression is always available;
- [ ] inner calls are individually inspectable/searchable;
- [ ] outer and inner calls are visually distinguishable;
- [ ] no call is hidden only because it lives behind a non-call wrapper.

---

# Slice 5 — Controls, branches and loops

## IF / ternary / short circuit

Render branch alternatives explicitly.

```text
IF condition
├─ TRUE
└─ FALSE
```

Calls inside the condition belong to the condition view, not as unrelated sibling steps.

## Loops

Render source semantics rather than compiler/frontend lowering.

FOREACH target:

```text
FOREACH <binding>
IN <iterable expression>
  BODY ...
```

Never expose Java lowering such as `iterator() / hasNext() / next()` as if it were source logic.

FOR target:

```text
FOR
  init
  condition
  body
  update
```

## TRY

```text
TRY
├─ TRY body
├─ CATCH <type/parameter>
└─ FINALLY
```

THROW/RETURN/BREAK/CONTINUE remain explicit terminating/control steps.

## SWITCH/MATCH

Render ordered CASE/DEFAULT branches.

For languages with implicit fallthrough, derive a possible path to the next ordered case when the preceding case has no terminating BREAK/RETURN/THROW. Do not invent a new v4 schema relation for this unless a new regression disproves the current gate.

## Acceptance

- [ ] IF alternatives are not flattened sequentially;
- [ ] short-circuit possibility is visible;
- [ ] foreach shows source binding/iterable, not lowering helpers;
- [ ] TRY/CATCH ownership is correct;
- [ ] early RETURN/THROW termination is visible;
- [ ] switch fallthrough gate behavior can be reproduced by viewer/path logic.

---

# Slice 6 — Lazy inter-method expansion

## Goal

Turn a local method structure into an explorable possible execution path without constructing a giant expanded graph.

Initial presentation:

```text
call Foo.bar(...)
  possible target(s): ...
  [+] expand
```

Expansion rules:

- expand internal methods on demand;
- preserve the call-site context where expansion originated;
- protect against cycles;
- enforce configurable expansion depth;
- allow collapse/re-expand without rebuilding the whole model;
- keep external/unresolved calls visible but non-expandable unless another source is available.

## Path semantics

Do not infer that two sibling calls from separate branches both execute in one path.

The expansion system should operate over branch-aware structure, not just call-graph reachability.

## Acceptance

- [ ] internal call expands lazily;
- [ ] recursion/cycles terminate safely;
- [ ] depth limit works;
- [ ] branch context survives expansion;
- [ ] same target reached from different call sites remains distinguishable.

---

# Slice 7 — Polymorphic target presentation

For a call such as:

```text
storage.save(...)
```

show separately:

```text
Declared target
  Storage.save

Possible targets
  FileStorage.save
  MemoryStorage.save
  ...
```

Do not promote one possible implementation to guaranteed execution without evidence.

Expansion can allow:

- one selected possible target;
- multiple branches/alternatives;
- compact collapsed target set.

## Acceptance

- [ ] declared target is distinct from possible targets;
- [ ] unresolved/internal-owner hints remain inspectable;
- [ ] viewer preserves v3-parity target facts carried by v4.

---

# Slice 8 — Ownership, folder context and configuration

Ownership should answer immediately:

```text
where in the codebase does this step belong?
```

Display useful combinations of:

```text
folder/package/namespace
owner type
source file
configured logical group
```

Viewer configuration may map patterns to labels/colors, for example:

```json
{
  "ownership": [
    { "pattern": "*/features/*", "role": "FEATURE" },
    { "pattern": "*/application/*", "role": "ORCHESTRATION" },
    { "pattern": "*/usecases/*", "role": "ORCHESTRATION" },
    { "pattern": "*/domain/*", "role": "DOMAIN" },
    { "pattern": "*/shared/*", "role": "SHARED" },
    { "pattern": "*/infrastructure/*", "role": "INFRASTRUCTURE" }
  ]
}
```

A useful conceptual ownership flow is often:

```text
UI
  -> FEATURE / ORCHESTRATION
  -> DOMAIN
  -> SHARED / INFRASTRUCTURE
```

but this is a **viewer/config interpretation**, not a guaranteed architecture or a new backend `architecturalRole` field. The actual trace order and relationships always come from v4 call/control/evaluation facts.

The tool should not assume every repository uses `features/domain/shared`. Real projects may use `application`, `usecases`, `handlers`, `services`, `commands`, or other conventions, so role mappings must be configurable and optional.

## Acceptance

- [ ] ownership is visible on every rendered call/method where known;
- [ ] colors/groups are configurable;
- [ ] grouping never changes trace order;
- [ ] `ORCHESTRATION` can be represented through configuration where useful;
- [ ] no architecture role is fabricated into the v4 backend model.

---

# Slice 9 — Search and export-current-result

## Search

Support at least:

- method name/signature;
- owner/package/folder;
- source expression/call text;
- possible target name.

## Export current result

The viewer should export the user's current analysis state as JSON for debugging/review without requiring screenshots.

Suggested content:

```json
{
  "modelIdentity": "...",
  "entryMethod": "...",
  "expandedCallSites": [],
  "selectedPossibleTargets": {},
  "visibleBranches": [],
  "viewerSettings": {},
  "modelReferences": []
}
```

The exact shape is a viewer artifact, not part of Static Execution Model v4.

## Acceptance

- [ ] exported result is sufficient to reproduce the visible logical state;
- [ ] it does not embed the entire source project unnecessarily;
- [ ] model IDs remain the join keys to the canonical v4 model.

---

# Slice 10 — Application shell

Only after the v4 viewer path is stable enough to use.

Minimum application experience:

```text
[ Open Project ]
Project: ...
Language: auto / detected
Analysis: cache hit | rebuilding | ready

[ Analyze ]

Search entry point...
```

Useful actions:

```text
Open project
Open previous analysis
Analyze / re-analyze
Explore
Settings
Export current result
```

A local browser-hosted HTML implementation is acceptable initially; packaging technology should not drive semantics.

## Acceptance

- [ ] a user does not need to know the internal exporter/normalizer commands;
- [ ] analysis errors are visible and actionable;
- [ ] previous valid analysis can be reopened;
- [ ] viewer receives exactly the validated v4 model/bundle.

---

# Slice 11 — Multi-project regression corpus

GD-CAP is the heavy real Java baseline, not a product-specific hardcode target.

Add a small external/project corpus over time, approximately:

```text
Java        2–3 projects
Python      2–3 projects
TypeScript  2–3 projects
C#          2–3 projects
```

For each project record:

```text
analysis completes
schema validator passes
unmapped calls = 0 or explicitly understood/accepted diagnostic
unmapped controls = 0 or explicitly understood/accepted diagnostic
entry method can be explored
source-semantic structures render plausibly
```

When a new frontend edge case appears:

```text
reproduce in minimal fixture
  -> backend fix only if model semantics are actually wrong
  -> regression gate
  -> project revalidation
```

Do not add project-name-specific normalization rules.

---

# Slice 12 — Performance / large-model loading

Optimize only after the functional v4 viewer exists.

Expected areas:

- CPG fingerprint/cache;
- model cache;
- indexed lookup rather than repeated full-array scans;
- lazy method/body loading if model size requires it;
- virtual rendering for large expanded traces;
- bounded DOM size;
- optional split/packaged analysis bundle if one monolithic JSON becomes a measured bottleneck.

Do not prematurely split the public v4 contract merely because a future scale issue is imaginable.

---

# Known open product/design questions

These are not blockers for the first viewer slice, but should stay explicit:

1. Exact viewer implementation stack/package format after the browser prototype becomes productized.
2. Exact cache fingerprint strategy that balances correctness and speed across languages/frontends.
3. How many possible polymorphic targets to expand simultaneously by default.
4. Whether very large v4 models eventually need a packaged/indexed on-disk format in addition to canonical JSON.
5. Whether architecture/impact views become separate screens or projections of the same v4 model.

These questions must not be answered by altering backend semantics prematurely.

---

# Definition of done for this milestone

The product v4 milestone is complete when:

- [ ] one command analyzes an arbitrary supported project into a validated v4 bundle;
- [ ] unchanged-source CPG reuse is safe and visible;
- [ ] a user can search/select an entry method;
- [ ] the viewer renders v4 expression structure;
- [ ] the viewer renders branches/loops/try source-semantically;
- [ ] switch fallthrough behavior follows the focused gate;
- [ ] internal calls expand lazily with cycle/depth protection;
- [ ] possible polymorphic targets are explicit alternatives;
- [ ] folder/package ownership is visible without reordering execution;
- [ ] search works across methods/calls/provenance;
- [ ] current viewer state can be exported as JSON;
- [ ] a minimal application shell hides internal pipeline plumbing;
- [ ] at least one additional real project beyond GD-CAP is used to validate transferability of the workflow;
- [ ] `CURRENT_WORK.md`, `work-manifest.json` and `PROJECT_TRACE.md` are updated to the next current state.

---

# Explicitly later

Do not block this milestone on:

```text
runtime-observed overlay
full dynamic tracing
security/taint product features
whole-application architecture graph polish
IDE plugin integration
cloud service/multi-user infrastructure
AI-generated architectural labeling stored in backend semantics
```
