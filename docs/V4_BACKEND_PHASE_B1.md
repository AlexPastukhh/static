# V4 backend - Phase B1

Phase A all-method raw structural export is considered complete after the fix3 four-language review.

This slice implements the first source-semantic normalization kernel:

```text
raw-structural-model-v4.json
    -> Normalize-StaticExecutionModelV4.ps1
    -> static-execution-model-v4.json
    -> normalization-report.json
    -> Validate-StaticExecutionModelV4.ps1
```

## Implemented in B1

- production/test filtering;
- synthetic method/type wrapper filtering;
- project-relative `/` source paths;
- public 1-based columns across frontends;
- source-declared parameters with synthetic `this` removed;
- method kind/signature/return type normalization;
- deterministic SHA-256 based public ids independent of raw Joern ids;
- expression trees for calls/operators/values;
- receiver/argument structure;
- full outer expression with nested calls;
- short-circuit `logical-and` / `logical-or` structure;
- ternary/conditional `CONDITION` / `TRUE` / `FALSE` children;
- call-site identity and target-resolution structure;
- v3-style exact/alias/arity/hierarchy target resolution concepts;
- IF controls with explicit TRUE/FALSE branches;
- RETURN controls from AST Return nodes;
- ordered method/IF-branch bodies for the implemented constructs;
- source reconstruction from original source offsets where available;
- `normalization-report.json` with structural-loss counters;
- four-language B1 semantic regression runner.

## Intentionally not implemented yet

The following raw structures are reported as unmapped and are the next B2 slice:

```text
SWITCH / MATCH
FOR / FOREACH / WHILE / DO_WHILE
TRY / CATCH / FINALLY
THROW / Python raise
BREAK / CONTINUE placement under normalized loop/switch bodies
```

Synthetic iterator lowering is not promoted into public trace expressions merely to fill these gaps.

## Expected B1 reference shape on the current fixtures

The assistant-side reference implementation, run against the reviewed Phase A fix3 raw models, produced schema-valid v4 models with these counts:

| language | types | methods | call sites | expressions | controls |
|---|---:|---:|---:|---:|---:|
| Java | 2 | 7 | 17 | 76 | 12 |
| Python | 1 | 6 | 15 | 77 | 13 |
| TypeScript | 1 | 7 | 13 | 77 | 12 |
| C# | 2 | 6 | 12 | 58 | 8 |

These counts are a B1 regression reference, not a final v4 completeness target. Counts will increase in later slices when loop/try/switch-owned expressions become reachable public semantic steps.

## B1 runner assertions

`Run-V4NormalizationSlice.ps1` checks each language for:

- schema/semantic validator pass;
- target fixture method exists;
- normalized parameter indexes and no synthetic `this`;
- IF has TRUE/FALSE branches;
- top condition is `logical-and` with nested `logical-or`;
- ternary has CONDITION/TRUE/FALSE roles;
- RETURN controls exist;
- repeated same-line nested calls keep distinct public ids;
- iterator lowering does not leak into current public expressions;
- public paths use `/` and columns are 1-based.

## Assistant-side checks before delivery

- all four uploaded Phase A fix3 raw models were parsed;
- a reference normalizer generated schema-valid v4 JSON for all four languages;
- B1 semantic assertions passed on all four reference models;
- public ids stayed identical after remapping every raw Joern id in the input;
- Java/Python offset slicing recovered exact short-circuit source text, including Python parentheses;
- both delivered PowerShell files are ASCII-only for Windows PowerShell 5.1;
- lexical delimiter checks found no unmatched braces/brackets/parentheses outside strings/comments.

The remaining required check is execution by Windows PowerShell against the user's installed Joern-generated raw models.
