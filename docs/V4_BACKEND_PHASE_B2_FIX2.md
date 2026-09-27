# V4 backend Phase B2 fix2

Fixes C# THROW value extraction.

Observed C# raw shape:

```text
THROW
  -> Call: new InvalidOperationException("selected")
```

The previous helper searched descendants and could still leave `valueExpressionId` null
for the single direct constructor-call form on Windows PowerShell.

Fix2:

- prefers a direct non-operator `new ...` Call owned by THROW;
- keeps ranked descendant selection for Java/TypeScript lowering;
- uses array-safe ranked-result handling;
- has a conservative direct non-container fallback;
- runner now verifies the THROW valueExpressionId resolves to a real expression.

This should also account for the previous C# `unmappedRawCalls = 1`, because the constructor
call becomes the THROW value expression and is normalized as a call site.
