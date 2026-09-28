# Static Trace Explorer — Current Work / Handoff

Status: **CURRENT handoff authority for work state**  
Repository base commit: `f3b86399972a662e866e010bd0c6983f9412f506` (`Freeze v4 backend after GD-CAP whole-project gate`)  
Handoff overlay status: **snapshot-local documentation/evidence overlay** created `2026-09-28`; these handoff files are not part of the base commit unless the user later commits/pushes them.  
Snapshot handoff refresh: `2026-09-28`

This file is the first document a new chat or maintainer should read.

It answers four questions:

1. What is this application?
2. What is already complete and must not be redone casually?
3. What is the current next work?
4. Which artifacts are authoritative for each kind of fact?

For the chronological engineering record, read `docs/PROJECT_TRACE.md`.  
For the current detailed implementation plan, read `docs/NEXT_MILESTONE_VIEWER_V4.md`.  
For machine-readable state, read `docs/work-manifest.json`.

---

## 1. Product in one paragraph

Static Trace Explorer is an AppMap-like explorer for **possible static execution paths**.

The user selects an entry method and incrementally explores what **CAN happen** from that point. The product preserves source/control/evaluation structure, explicit branches and loops, nested expressions, possible polymorphic targets, and code ownership/provenance without rendering the entire application graph by default.

The intended application flow is approximately:

```text
Open project
  -> Analyze / reuse analysis
  -> choose entry method
  -> inspect possible static execution paths
  -> expand calls lazily
  -> inspect branches / expressions / ownership
  -> search / export current result
```

Static meaning is always:

```text
what CAN happen
```

not:

```text
what DID happen
```

A runtime-observed overlay is a later, separate capability.

---

## 2. Current architectural boundary

The backend pipeline is now established as:

```text
source
  ↓
Joern / CPG
  ↓
raw structural export
  ↓
source-semantic normalization
  ↓
Static Execution Model v4
  ↓
validated model
  ↓
viewer / path derivation / application shell   ← CURRENT PRODUCT PHASE
```

The **v4 backend baseline is frozen** for product work.

Do not reopen schema/exporter/normalizer semantics merely because the viewer needs a convenient representation. Change backend semantics only when a concrete reproducible regression demonstrates that the public v4 model is wrong or insufficient.

When such a regression exists:

```text
small fixture first
  -> reproduce
  -> smallest semantic fix
  -> existing regression gates
  -> real-project gate
```

---

## 3. Backend v4 freeze evidence

The completed backend gates are:

```text
four-language structural/normalization fixtures    PASS
switch / fallthrough focused gate                  PASS
v3 -> v4 target-resolution parity gate             PASS
GD-CAP whole-project v4 gate                        PASS
```

Final accepted GD-CAP whole-project summary:

```text
types:               103
methods:             715
call sites:         3939
expressions:       20036
controls:           1563
unmapped calls:        0
unmapped controls:     0
```

Production/test baseline retained:

```text
production types:      103
production methods:    715
excluded test types:    44
excluded test methods: 106
```

The detailed real-project acceptance also covers `gdcap.features.copy.CopyNoteMaterialFeature.copyMany` and verifies source-declared parameters, control structure, nested calls, return construction, foreach normalization, try/catch ownership, and relevant internal target resolution.

Retained final PASS evidence:

```text
evidence/gd-cap/gd-cap-v4-gate-report.json
SHA256: 04cd00f84b5c503b4b449a94891eb23a5c35fbe4383f8b8a4b2e486fba349975
```

The retained report says `result: PASS`, contains no gate `failures` or `warnings`, and records the same final counts above. The original user-provided final-pass bundle SHA256 is `b1123726bd31f3c7972614bbcae9748b611a8a5985404a0ee1c9d562a098c01f`; the large generated CPG/raw/model files remain build artifacts and are not copied into the handoff repository snapshot.

Primary gate artifacts/scripts:

```text
scripts/Run-V4NormalizationSlice.ps1
scripts/Run-V4SwitchFallthroughGate.ps1
scripts/Run-V3V4TargetResolutionGate.ps1
scripts/Run-GdCapV4Gate.ps1
```

The frozen **public backend contract** is:

```text
schema/static-execution-model-v4.schema.json
docs/STATIC_EXECUTION_MODEL_V4.md
```

The frozen **implementation/validation baseline** that realizes that contract is:

```text
scripts/Validate-StaticExecutionModelV4.ps1
scripts/Export-StructuralModelV4.ps1
scripts/Normalize-StaticExecutionModelV4.ps1
scripts/joern-structural-export-v4.sc
```

---

## 4. Important backend knowledge already learned

Do not lose these implementation lessons when continuing the product:

- Frontend lowering differs materially across Java, Python, TypeScript and C#; the viewer must consume normalized source semantics, not raw Joern lowering.
- Public normalized IDs are deterministic and independent from raw Joern node IDs.
- Source parameter lists omit synthetic implicit receivers such as Java/C#/TS `this`; explicit Python `self` remains source-declared.
- Nested expressions are structural and preserve the full outer source expression plus inner calls.
- IF, short-circuit boolean operations, ternary, loops, TRY/CATCH/FINALLY, THROW/raise, RETURN, BREAK and CONTINUE are normalized explicitly.
- Java enhanced-for lowering differs for Iterable and array-valued iterables. The normalizer has dedicated source-semantic foreach iterable resolution; do not replace it with generic iterator-lowering inspection.
- Java constructor/return lowering can place `new X(...)` behind wrapper/block nodes; non-call wrappers recurse and RETURN selection preserves the outer constructor expression.
- Synthetic receiver suppression must be narrow. Broad text heuristics previously hid legitimate calls.
- Joern pseudo-files such as `<empty>` are not filesystem paths.
- The v4 validator must use indexed expression lookup; the earlier O(N*M) reference scan was too slow at real-project scale.
- Switch implicit fallthrough does **not** require a new schema edge. Path/viewer logic derives it from ordered CASE branches plus absence of terminating control in the preceding branch.
- The stable v3 target-resolution behavior remains a regression oracle, not an input join dependency for structural v4 call sites.

See `docs/PROJECT_TRACE.md` for the chronological history behind these rules.

---

## 5. Product semantics that are already decided

These are not open UI brainstorming items unless new evidence requires revision:

- trace order follows source/control/evaluation structure;
- folder/package/module ownership is visible metadata and must not reorder execution;
- calls remain searchable;
- branches are explicit and intuitive;
- nested expressions preserve the full outer expression and visually distinguish outer/inner calls;
- condition expressions expose the calls they contain;
- sibling calls must not be presented as sequential execution unless the model actually supplies ordering/branch evidence;
- declared target and possible dispatch targets stay distinct;
- path expansion is lazy rather than whole-program graph rendering;
- configurable colors/ownership grouping belong to the viewer/config layer;
- architectural roles such as `FEATURE`, `DOMAIN`, `SHARED`, `INFRASTRUCTURE`, and `ORCHESTRATION` are viewer/config metadata, not v4 backend facts;
- orchestration should be recognizable from configured ownership plus the actual call/control structure; do not invent backend `architecturalRole: ORCHESTRATION`;
- error-like type patterns are styling, not semantic control-flow inference;
- runtime observations, if added later, are an overlay on static possibility rather than a replacement.

Authoritative product decision record: `docs/STATIC_TRACE_EXPLORER_DECISIONS.md`.

---

## 6. Current product gap

The repository now has an authoritative v4 backend, but the **application-facing path is still split between old v3 analysis/viewer experiments and the new v4 backend**.

In particular:

- `scripts/Analyze-Project.ps1` belongs to the older generic/v3 pipeline;
- V1/V2 viewer templates are historical experiments;
- there is not yet one product-grade v4 entry point that accepts an arbitrary source project and produces the canonical v4 analysis bundle;
- the current viewer does not yet render v4 expressions/controls/branches directly;
- there is no finished application shell for Open Project -> Analyze -> Explore.

This is the main boundary the next work must cross.

---

## 7. Current next work

Detailed plan: `docs/NEXT_MILESTONE_VIEWER_V4.md`.

Recommended order:

```text
1. unified v4 analysis entrypoint
2. analysis fingerprint / CPG cache
3. viewer v4 loader + method search + entry selection
4. expression rendering
5. controls / branches / loops / try rendering
6. lazy inter-method expansion
7. polymorphic target presentation
8. ownership / folder context + configuration
9. viewer search + export-current-result
10. application shell
11. multi-project regression corpus
12. performance / large-model loading
```

**Slice 1** stops at a validated reusable v4 analysis bundle. **Slices 1-3 together** establish the first minimal end-to-end `source project -> validated v4 -> viewer` path. Visual polish is explicitly out of scope for that first end-to-end milestone.

---

## 8. Artifact authority map

Use this map to avoid treating an old plan as current state.

### Current work / handoff authority

```text
CURRENT_WORK.md                         current human work state / handoff
docs/work-manifest.json                machine-readable current state
docs/PROJECT_TRACE.md                  append-oriented engineering history
docs/NEXT_MILESTONE_VIEWER_V4.md       current detailed forward plan
```

### Product meaning / decisions

```text
docs/PRODUCT_REQUIREMENTS.md
docs/STATIC_TRACE_EXPLORER_DECISIONS.md   authoritative accepted decisions
docs/STATIC_TRACE_EXPLORER_VISION.md
config/static-trace-viewer.config.json
```

### Backend public contract

```text
docs/STATIC_EXECUTION_MODEL_V4.md
schema/static-execution-model-v4.schema.json
```

### Retained backend acceptance evidence

```text
evidence/gd-cap/gd-cap-v4-gate-report.json
```

### Backend implementation / validation

```text
scripts/joern-structural-export-v4.sc
scripts/Export-StructuralModelV4.ps1
scripts/Normalize-StaticExecutionModelV4.ps1
scripts/Validate-StaticExecutionModelV4.ps1
scripts/Run-V4NormalizationSlice.ps1
scripts/Run-V4SwitchFallthroughGate.ps1
scripts/Run-V3V4TargetResolutionGate.ps1
scripts/Run-GdCapV4Gate.ps1
fixtures/structural-probe/
fixtures/fallthrough-probe/
```

### Historical implementation plans/evidence

These remain useful history but are **not the current work queue**:

```text
docs/NEXT_STEP_V4_BACKEND_PLAN.md
docs/V4_BACKEND_PHASE_A.md
docs/V4_BACKEND_PHASE_B1.md
docs/V4_BACKEND_PHASE_B2.md
docs/V4_BACKEND_PHASE_B2_FIX1.md
docs/V4_BACKEND_PHASE_B2_FIX2.md
docs/STRUCTURAL_PROBE_FINDINGS_CROSS_LANGUAGE.md
```

---

## 9. Handoff protocol for future chats

A new chat should start with:

```text
Read in this order:
1. CURRENT_WORK.md
2. docs/work-manifest.json
3. docs/PROJECT_TRACE.md
4. docs/PRODUCT_REQUIREMENTS.md
5. docs/STATIC_TRACE_EXPLORER_DECISIONS.md
6. docs/STATIC_EXECUTION_MODEL_V4.md
7. docs/NEXT_MILESTONE_VIEWER_V4.md

Backend v4 is frozen after the final GD-CAP whole-project PASS.
Do not restart backend design without a concrete regression case.
Continue from the first incomplete item in NEXT_MILESTONE_VIEWER_V4.md.
```

Then inspect only the implementation files relevant to the selected next item.

---

## 10. Required maintenance after future work

To keep future snapshots transferable, do **not** create a new competing to-do/ledger for every chat.

Maintain these existing artifacts instead:

1. **`docs/PROJECT_TRACE.md`** — append a concise event when a material milestone, gate, bug class, decision or implementation slice completes.
2. **`CURRENT_WORK.md`** — update only the current truth: baseline, current phase, current next work, blockers and artifact map.
3. **`docs/work-manifest.json`** — keep the machine-readable state synchronized with `CURRENT_WORK.md`.
4. **`docs/NEXT_MILESTONE_VIEWER_V4.md`** — mark acceptance items done and revise the forward plan when evidence changes it.
5. Product/contract docs — update only if product semantics or the public backend contract actually change.

History should normally be appended, not rewritten. If a prior trace entry was wrong, add a correction entry with the new basis.

---

## 11. Environment / collaboration constraints learned so far

The primary development environment has been Windows PowerShell 5.1.

When changing `.ps1` files:

- stay PowerShell 5.1 compatible;
- prefer ASCII-only script text where practical;
- avoid risky interpolation such as `$var:`; use `${var}:` when a colon follows an interpolated variable;
- do not assume `pwsh` is installed;
- reuse CPGs while iterating when the source/frontend did not change.

For review/debugging, prefer exported model/result JSON over screenshots when the JSON can preserve the relevant structure.
