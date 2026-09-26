# Expected static facts

These are the facts we will use as a "golden checklist".
Exact synthetic/constructor method counts are intentionally not specified because analyzers model them differently.

## Common architecture

```text
Main
 |
 v
OrderService.placeOrder
 |         |              |
 |         |              +--> AuditService.flagLargeOrder   [conditional]
 |         |
 |         +--> OrderRepository.save
 |
 +--> PaymentGateway.pay
          |
          +--> CardGateway.pay
          +--> BankGateway.pay
```

The normal run selects `CardGateway`.

The normal order amount is `125`, so:

```text
AuditService.flagLargeOrder
```

exists in the static code/call structure but is not executed by the normal scenario.

## Queries we will ask every tool

### Q1 Types
Find:
- Order
- PaymentGateway / IPaymentGateway
- CardGateway
- BankGateway
- PaymentGatewayFactory
- AuditService
- OrderRepository
- OrderService
- UnsafeCli

### Q2 Callers
Who calls `OrderService.placeOrder`?

Expected user-code caller:
- Main / application entry point

### Q3 Callees
What can `OrderService.placeOrder` call?

Expected user-code calls:
- `PaymentGateway.pay`
- `AuditService.flagLargeOrder` (conditional)
- `OrderRepository.save`

Some analyzers will report concrete implementations instead of or in addition to the interface call.

### Q4 Polymorphism
Possible implementations/targets of `PaymentGateway.pay`:
- `CardGateway.pay`
- `BankGateway.pay`

This is one of the most useful precision comparisons.

### Q5 Source mapping
For named methods, retrieve:
- source file
- line/range

### Q6 AST
Show AST for `OrderService.placeOrder`.

### Q7 CFG
Show control-flow graph for `OrderService.placeOrder`.

It should contain a branch equivalent to:

```text
order.amount > 1000
   /          \
 audit        skip
   \          /
     save
```

### Q8 Data flow / taint
Trace command-line input to the deliberately unsafe shell execution path.

Conceptually:

```text
argv / args
   |
   v
UnsafeCli.run(...)
   |
   v
shell/process execution sink
```

### Q9 Machine-readable export
Save whatever the tool exposes to `results/<tool>/` as one or more of:
- JSON
- SARIF
- SCIP
- DOT
- GraphML
- CSV
- tool database

## Important interpretation rule

A static analyzer seeing both `CardGateway` and `BankGateway` is not "wrong" just because the normal execution uses only `CardGateway`.
That difference is exactly what this lab is designed to expose:

- static = possible
- runtime = observed
