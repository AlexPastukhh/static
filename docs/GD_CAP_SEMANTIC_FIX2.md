# GD-CAP semantic fix2

The first real-project gate exposed two related issues:

1. only one of six source enhanced-for loops in CopyNoteMaterialFeature.copyMany
   was normalized as FOREACH;
2. 275 raw non-operator calls remained unaccounted for.

The Java frontend represents enhanced-for as raw WHILE with parserTypeName=ForEachStmt.
This fix makes parserTypeName the authoritative Java foreach signal and parses the source
header with a nesting-aware scanner. It correctly handles iterable expressions such as:

  sourceState.elements()
  targetState.elements()

without truncating at the inner closing parenthesis.

The gate now expects all six copyMany enhanced-for loops and rejects leaked
java.util.Iterator lowering targets.

The normalizer also records grouped/sample unmapped raw calls in normalization-report.json
and the GD-CAP gate report, so any remaining unmapped calls can be diagnosed without
uploading the full raw model.
