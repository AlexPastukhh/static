# Joern starter sheet

We will use the official Joern shell and CPG queries.

Typical flow:

```text
import code -> CPG -> CPGQL queries -> JSON/DOT output
```

Useful queries after importing one project:

```scala
cpg.method.name.l
cpg.typeDecl.name.l
cpg.method.name("placeOrder").callee.name.l
cpg.method.name("place_order").callee.name.l
```

For source metadata:

```scala
cpg.method.name("placeOrder").map(m => (m.name, m.filename, m.lineNumber)).l
```

For graph dumps, Joern exposes method graph helpers such as `dotAst` and `dotCfg`.

For data-flow, we will define a source near the program argument and a sink near the shell/process call, then use `reachableByFlows`.

Do not expect the exact same method names across languages:
- C#/Java/TS: `placeOrder`
- Python: `place_order`

We will run and adjust the actual queries interactively because frontend modeling differs by language.
