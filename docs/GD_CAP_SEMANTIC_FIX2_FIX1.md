# GD-CAP semantic fix2 fix1

Windows PowerShell 5.1 does not accept:

  Sort-Object count -Descending, name

The unmapped-call diagnostic sort now uses explicit property hashtables:

  Sort-Object `
      @{ Expression = "count"; Descending = $true }, `
      @{ Expression = "name"; Descending = $false }

No normalization semantics changed.
