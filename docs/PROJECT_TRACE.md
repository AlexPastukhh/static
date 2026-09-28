# Static Trace Explorer — Project Trace

Status: **append-oriented engineering history**  
Current work authority: `../CURRENT_WORK.md`  
Current forward plan: `NEXT_MILESTONE_VIEWER_V4.md`

This file records material work already performed, why it was needed, and what evidence closed it.

It is intentionally different from a to-do list:

```text
PROJECT_TRACE = what materially happened + result + retained knowledge
CURRENT_WORK  = what is true now
NEXT_MILESTONE = what should happen next
```

Do not use old `PENDING` statements in historical phase documents as current work state. When history and current state differ, `CURRENT_WORK.md` wins for current status while this trace explains how that state was reached.

---

## Status vocabulary

- `DONE` — completed and retained in the current baseline.
- `PASS` — an explicit regression/acceptance gate passed.
- `SUPERSEDED` — useful historical work replaced by a later mechanism.
- `HISTORICAL` — retained context, not current work.
- `NEXT` — current forward work, owned by the current milestone plan.

---

## 2026-09-26 — Initial Static Trace Explorer prototype

**Commit:** `bcabc7774f6dad7928f9b80820002611dfda29c3`  
**Result:** `DONE`

Established the initial polyglot static-analysis lab and browser viewer experiments.

Key product direction emerged:

- entry-method-centric exploration rather than a mandatory whole-program graph;
- downstream/upstream call navigation;
- source ownership/provenance;
- browser-based static trace inspection.

The early v1/v2 viewer and v3 application model remain historical stepping stones rather than the final structural product model.

---

## 2026-09-26 — Product requirements reconciled

**Commit:** `b6dc6524d1cd3860e210bfebf522543056c9c90a`  
**Result:** `DONE`

The product was narrowed from a generic call graph into a static execution-path explorer.

Accepted semantics included:

- `CAN happen`, not `DID happen`;
- explicit branches and structural controls;
- folder/module ownership visible without reordering execution;
- nested outer/inner calls;
- conditions containing their calls;
- no invented sibling sequencing;
- lazy path expansion;
- declared polymorphic target separated from possible implementations.

The authoritative decision record is `STATIC_TRACE_EXPLORER_DECISIONS.md`.

---

## 2026-09-26 — Static Execution Model v4 contract frozen

**Commit:** `ba2bef11d013e62c6b4432590c3d97fc4f339ff5`  
**Result:** `DONE`

Cross-language structural probes showed that raw Joern AST/control lowering cannot be exposed directly as product semantics.

The architecture was formalized as:

```text
raw frontend/CPG facts
  -> source-semantic normalization
  -> language-neutral Static Execution Model v4
```

The v4 public contract introduced:

- source-declared method parameters/return type;
- deterministic semantic IDs;
- ordered method/branch bodies;
- expression trees with calls/operators/values;
- explicit controls/branches;
- stable call-site identity;
- possible target structure.

Primary contract artifacts:

```text
schema/static-execution-model-v4.schema.json
docs/STATIC_EXECUTION_MODEL_V4.md
```

---

## 2026-09-26/27 — Phase A: all-method raw structural export

**Result:** `DONE`

Implemented the raw structural exporter for relevant source methods and preserved enough provenance for source-semantic normalization.

Important retained boundary:

```text
exporter = facts
normalizer = production scope + source semantics
```

Production/test filtering therefore stays in normalization rather than being duplicated in Scala exporter logic.

A Windows path bug was found when Joern emitted pseudo-file `<empty>`.

Fix retained:

- treat `<...>` pseudo filenames as non-filesystem provenance;
- guard invalid Windows path characters;
- avoid `Test-Path` on invalid pseudo paths;
- keep sourceCode/code fallback behavior.

---

## 2026-09-26/27 — Phase B1: core v4 normalization

**Result:** `DONE`

Implemented and validated:

- production/test filtering;
- project-relative forward-slash paths;
- 1-based public coordinates;
- source-declared parameters with synthetic Java/C#/TS `this` removed;
- deterministic public IDs independent of raw Joern IDs;
- CALL / OPERATOR / VALUE expression trees;
- receiver/argument relations;
- nested calls and full outer expressions;
- IF TRUE/FALSE;
- short-circuit logical-and/logical-or;
- ternary CONDITION/TRUE/FALSE;
- RETURN;
- call-site target structure.

PowerShell 5.1 compatibility lesson retained: when a colon follows interpolation use `${Kind}:` rather than `$Kind:`.

---

## 2026-09-26/27 — Phase B2: controls and source-semantic lowering

**Result:** `DONE`

Implemented and validated:

- classic FOR;
- FOREACH across Java/Python/TypeScript/C#;
- WHILE;
- SWITCH/MATCH CASE/DEFAULT;
- TRY/CATCH/FINALLY;
- THROW including Python `raise`;
- BREAK/CONTINUE;
- recursive Block traversal;
- iterator-lowering suppression.

Two material fixes were required:

1. Python FOREACH ownership/traversal was corrected so semantic control containers are traversed before lowering suppression and FOREACH bodies cannot remain orphaned.
2. C# THROW value selection was corrected to preserve direct `new ...` construction while keeping Java/TS descendant ranking behavior.

---

## 2026-09-27 — Switch fallthrough gate

**Result:** `PASS`

A dedicated fixture was added for Java, TypeScript and C#.

- Java and TypeScript exercise legal implicit fallthrough.
- C# uses explicit `goto case` because non-empty implicit fallthrough is not legal in C#.

Result: the existing v4 SWITCH representation is sufficient.

No new public schema edge was added.

The path/viewer layer should derive implicit fallthrough from:

```text
ordered CASE branches
+ no terminating BREAK / RETURN / THROW in the preceding branch
```

This closed the earlier structural-probe fallthrough gap.

---

## 2026-09-27 — v3 -> v4 target-resolution parity gate

**Result:** `PASS`

V4 resolution was aligned with the stable v3 oracle while keeping structural call-site identity independent from v3 JSON.

Retained rules include:

- exact/full-owner aliases rather than unsafe short-owner aliases;
- overload arity filtering;
- declared-target fallback when one resolved target exists but direct target is missing;
- unresolved targets remain visible even on otherwise-internal calls;
- internal-owner detection;
- unresolved base hints;
- production test-target filtering.

Comparison uses multiset semantics because v3 lacks stable structural call-site IDs.

V3 is a regression oracle, not a required v4 structural input.

---

## 2026-09-27 — GD-CAP scale gate: validator performance issue

**Result:** `DONE`

The first real-project validation appeared hung because reference validation scanned expressions linearly for every call site.

At approximately:

```text
3,798 call sites × 18,986 expressions
```

that became tens of millions of PowerShell comparisons.

Fix retained:

- build an `expressionById` hashtable once;
- validate references by O(1) lookup;
- sort parameter indexes once.

No validation rule was weakened.

---

## 2026-09-27 — GD-CAP semantic fixes from whole-project evidence

**Result:** `DONE`

The whole-project gate exposed several frontend-lowering classes that small fixtures had not fully covered.

### Enhanced-for source header parsing

Real Java enhanced-for headers such as:

```java
for (Element element : sourceState.elements())
```

were not safely parsed by the original simple regex when the iterable contained nested parentheses.

Fix:

- nesting-aware Java enhanced-for header splitting;
- prefer raw control `sourceCode` for `ForEachStmt`;
- reject leaked iterator lowering from public semantics.

### Wrapper recursion and constructor/return lowering

A large unmapped-call class came from calls hidden behind non-call AST wrappers and Java `return new X(...)` lowering.

Fix:

- recursively traverse non-call expression wrappers;
- skip synthetic `<operator>.alloc`;
- narrow synthetic receiver suppression;
- for lowered RETURN blocks prefer the outer source constructor expression;
- recurse through otherwise-unhandled AST containers without duplicating explicit Call/Return/Control traversal.

This reduced unmapped raw calls from hundreds to seven.

### Array enhanced-for iterable calls

The final seven unmapped calls were Java enhanced-for iterable expressions returning arrays, such as:

```text
path.split(...)
value.toCharArray()
elementList.getSelectedIndices()
```

These lower differently from Iterable-based foreach.

Fix:

- dedicated source-semantic Java FOREACH iterable resolver;
- same-header non-operator call matching;
- reject iterator/hasNext/next lowering helpers;
- exact source expression preference, with terminal source method fallback when frontend receivers are rewritten.

This is a general Java array-enhanced-for rule, not a GD-CAP-specific hardcode.

---

## 2026-09-27 — GD-CAP whole-project v4 gate

**Commit:** `f3b86399972a662e866e010bd0c6983f9412f506`  
**Result:** `PASS`

Final accepted summary:

```text
Types:              103
Methods:            715
Call sites:         3939
Expressions:        20036
Controls:           1563
Unmapped calls:     0
Unmapped controls:  0
```

The focused `CopyNoteMaterialFeature.copyMany` acceptance also passed.

Retained acceptance evidence is now stored at `../evidence/gd-cap/gd-cap-v4-gate-report.json`. The repository-normalized LF file has SHA256 `d6dfbb2ce1daf4f82fd18440e5003a774ad0d8e079e909f6ee01abef5d39b047`; the original uploaded Windows/CRLF report had SHA256 `04cd00f84b5c503b4b449a94891eb23a5c35fbe4383f8b8a4b2e486fba349975`. The JSON meaning is unchanged. The report records `result: PASS`, zero unmapped calls/controls, no gate failures, and the accepted whole-project counts above.

This closes the production v4 backend milestone.

Backend state after this event:

```text
FROZEN BASELINE
```

The next product phase is not more backend normalization work by default. It is consuming v4 through a reusable project-analysis entrypoint and v4 viewer/application layer.

---

## 2026-09-28 — Transfer-ready work state introduced

**Result:** `DONE`

The repository snapshot was updated so a new chat can continue without reconstructing the project from conversation history.

Added/current handoff artifacts:

```text
../CURRENT_WORK.md
work-manifest.json
PROJECT_TRACE.md
NEXT_MILESTONE_VIEWER_V4.md
```

Older backend phase plans are retained as history but are explicitly no longer the current work queue. The handoff/trace/evidence artifact set was committed to `main` as `630af119d05695e01ffde38661920a8e8a4e38ff` (`Add transferable project trace and current work handoff`), on top of backend-freeze commit `f3b86399972a662e866e010bd0c6983f9412f506`.

The transfer refresh also made the accepted architecture-visibility rule explicit: `FEATURE`, `DOMAIN`, `SHARED`, `INFRASTRUCTURE`, and `ORCHESTRATION` are viewer/config roles. `ORCHESTRATION` must not be invented as a v4 backend field; it is interpreted from configuration together with real call/control structure.

---

## 2026-09-29 — Handoff provenance metadata corrected

**Result:** `DONE` in the transfer snapshot

The transfer metadata was reconciled with repository state after the handoff commit was pushed:

- handoff artifacts are no longer described as an uncommitted overlay;
- committed handoff origin is `630af119d05695e01ffde38661920a8e8a4e38ff`;
- backend-freeze origin remains `f3b86399972a662e866e010bd0c6983f9412f506`;
- the retained GD-CAP report now distinguishes the original Windows/CRLF SHA256 (`04cd00...`) from the Git/repository-normalized LF SHA256 (`d6dfbb...`).

No backend semantics, schema, fixture, gate outcome, or forward-plan ordering changed in this correction.

---

# Current continuation point

`NEXT`

Continue from `NEXT_MILESTONE_VIEWER_V4.md`, beginning with a unified v4 project-analysis entrypoint and preserving the frozen backend contract unless a reproducible regression requires change.
