# Switch fallthrough gate

## Purpose

This gate addresses the known v4 contract gap:

> Can ordered CASE/DEFAULT branches plus explicit terminating controls preserve a
> fallthrough-capable switch without adding a new schema edge?

## Fixtures

Java and TypeScript use real implicit fallthrough:

```text
case 1:
    callA();
case 2:
    callB();
    break;
```

C# does not permit implicit fallthrough from a non-empty case, so its fixture uses
`goto case 2` and records that separately.

## Acceptance

For Java and TypeScript the normalized model must contain:

```text
SWITCH
  CASE 1
    callA()
    no BREAK / RETURN / THROW
  CASE 2
    callB()
    BREAK
  DEFAULT
    callDefault()
```

The CASE branches must remain in source order.

This is sufficient for the execution-path layer to infer:

```text
enter CASE 1
  -> execute CASE 1 body
  -> no terminating control
  -> continue into next ordered CASE body
```

For C#, branch order and explicit source `goto case 2` evidence are retained, but it is
not classified as implicit language fallthrough.

## Decision rule

If the gate passes for Java and TypeScript, no schema change is needed for this specific
fallthrough shape. The viewer/path engine should derive fallthrough from:

1. control kind = `SWITCH`;
2. ordered branches;
3. absence of `BREAK`, `RETURN`, or `THROW` in the active CASE path.

`MATCH` is intentionally excluded because Python match cases do not fall through.
