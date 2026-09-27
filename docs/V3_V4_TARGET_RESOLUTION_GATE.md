# V3/V4 target-resolution regression gate

## Goal

Prove that the V4 normalizer preserves the stable V3 target-resolution behavior while
keeping V3 as a regression oracle only.

V3 is not joined into V4 normalization and is not an input dependency.

## Same-CPG oracle

The gate reuses each fixture's existing:

```text
results/v4-fixtures/<language>/cpg.bin
```

It runs the stable V3 `joern-export.sc` and `Normalize-StaticModel.ps1` against that same
CPG. This removes frontend rebuild drift from the comparison.

## V4 parity fixes included in this pack

The V4 resolver is aligned to stable V3 behavior for:

- exact/full-owner alias matching;
- overload arity filtering;
- declared-target fallback when Joern has one resolved target but no direct target;
- unresolved target preservation on otherwise internal calls;
- internal-owner detection for unresolved calls;
- unresolved base hints;
- production test-target filtering.

The source-semantic V4 suppression rules remain unchanged.

## Call-site comparison

V3 has no stable structural call-site id, so the gate does not perform a fragile
caller+line one-to-one join.

Instead it compares a multiset of target-resolution semantics:

For internal calls:

```text
caller
line
declaredTarget
dispatchTargets
possibleTargets
unresolvedTargets
resolution
```

For external/unresolved calls:

```text
caller
line
classification
targets
internalOwner
unresolvedBaseHints
```

Repeated same-line calls are counted independently.

Only methods present in both models participate in this target-resolution gate. Synthetic
wrapper differences such as TypeScript `:program` are reported separately.

Known V3-only iterator-lowering calls are allowed because V4 intentionally suppresses
frontend lowering from the public source-semantic model. Any other unmatched V3 call
fails the gate.

## Expected result

```text
V3/V4 TARGET RESOLUTION GATE PASS
```

After this passes, the next backend gate is whole-project GdCap V4 normalization and the
`CopyNoteMaterialFeature.copyMany` acceptance case.

Gate scratch output is written under `results/v4-fixtures/target-parity/`, which is already ignored.
