# GD-CAP whole-project v4 gate

This is the final backend-scale gate before viewer migration.

## Final accepted result

The backend freeze run passed the complete whole-project gate.

```text
GD-CAP V4 GATE PASS
Types:              103
Methods:            715
Call sites:         3939
Expressions:        20036
Controls:           1563
Unmapped calls:     0
Unmapped controls:  0
```

This result closes the backend-scale milestone. Future backend semantic changes require a reproducible regression fixture and re-running the relevant gates plus this real-project gate.

## Retained final evidence

The final successful user-run gate artifact is retained in this transfer snapshot at:

```text
evidence/gd-cap/gd-cap-v4-gate-report.json
```

SHA256:

```text
04cd00f84b5c503b4b449a94891eb23a5c35fbe4383f8b8a4b2e486fba349975
```

The report itself records:

- `gate: gd-cap-v4-whole-project`;
- `result: PASS`;
- source `C:\gd-cap\java-src`;
- the exact final counts shown above;
- `unmappedRawCalls: 0`;
- `unmappedRawControls: 0`;
- `unsupportedControlSteps: 0`;
- `unsupportedBlockSteps: 0`;
- `unresolvedSourceSnippets: 0`;
- `idCollisions: 0`;
- empty gate `failures` and `warnings`.

The original uploaded final-pass bundle also contained the generated CPG, raw structural model, normalization report and normalized v4 model. Those large generated artifacts are intentionally not copied into the transfer repository snapshot; the retained gate report is the durable acceptance evidence.

It runs the complete production pipeline against the real GD-CAP Java source tree:

```text
GD-CAP source
  -> Joern all-method structural export
  -> Static Execution Model v4 normalization
  -> schema/reference validation
  -> whole-project regression checks
  -> CopyNoteMaterialFeature.copyMany acceptance
```

## Default source

The runner keeps the path already used by the structural probe:

```text
C:\gd-cap\java-src
```

Override `-Source` if needed.

## Production baseline

The gate preserves the established v3 production baseline:

```text
types:                 103
methods:               715
excluded test types:    44
excluded test methods: 106
```

A mismatch is treated as a regression in production/test filtering or method/type ownership.

## Normalizer acceptance

The following must be zero:

- normalized ID collisions;
- unmapped raw non-operator calls;
- unmapped raw controls;
- unsupported control steps;
- unsupported block steps;
- unresolved source snippets.

The raw exporter may keep frontend lowering evidence. The public v4 model must account for
or intentionally suppress that evidence during normalization.

## copyMany acceptance

The gate finds:

```text
gdcap.features.copy.CopyNoteMaterialFeature.copyMany
```

and checks the source-semantic properties needed by the product:

- source file and line;
- `CopyOutcome` return type;
- six source-declared parameters and no implicit `this`;
- IF, classic FOR, FOREACH, TRY, THROW and RETURN controls;
- TRY/CATCH branch ownership;
- no orphan controls;
- calls to source/target load, canModify, prepareOne, cleanup, save and rollback check;
- internal target resolution for the CopyNoteMaterialFeature and NoteSafePersistence calls.

The gate writes:

```text
results\v4-fixtures\gd-cap\gd-cap-v4-gate-report.json
```

even when an acceptance assertion fails. That report is the preferred artifact to upload
for diagnosis.

## Reuse

After the first run, use `-ReuseCpg` to avoid rebuilding the CPG while iterating only on
normalization or gate assertions.
