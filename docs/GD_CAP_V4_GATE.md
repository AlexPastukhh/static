# GD-CAP whole-project v4 gate

This is the final backend-scale gate before viewer migration.

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
