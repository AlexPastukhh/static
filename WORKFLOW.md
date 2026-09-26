# Our workflow

## Phase 0 — Environment inventory
Record OS and versions:

```bash
git --version
docker --version
dotnet --info
java -version
mvn -version
node --version
npm --version
python3 --version
```

Missing tools are installed only when needed.

## Phase 1 — Baseline
Build/run each project with no analyzer.
Goal: prove the sample itself is healthy.

Save output:

```text
results/baseline/
```

## Phase 2 — Joern
Goal: test the unified Code Property Graph idea first.

For each language:
1. create/import CPG;
2. list methods/types;
3. query caller/callee;
4. inspect possible call targets;
5. dump AST/CFG for `placeOrder`;
6. attempt data-flow from CLI input to shell sink;
7. export JSON/DOT where useful.

Save:

```text
results/joern/<language>/
```

Decision after this phase:
- Is Joern accurate enough across all four languages?
- Is C# noticeably weaker?
- Is its unified model worth the precision tradeoff?

## Phase 3 — SCIP
Goal: establish a language-aware symbol/reference baseline.

For each language:
1. generate `index.scip`;
2. inspect symbols and occurrences;
3. verify definitions/references;
4. verify interface/implementation navigation where supported.

Save:

```text
results/scip/<language>/index.scip
```

Decision:
- Is SCIP enough for navigation/indexing?
- Which graph facts are missing versus Joern?

## Phase 4 — CodeQL
Goal: compare deeper semantic/data-flow quality.

For each language:
1. create a CodeQL database;
2. run small custom queries for methods/calls;
3. run a data-flow query for the unsafe path;
4. export CSV/JSON/SARIF.

Important: CodeQL licensing/entitlement must be respected. For the cleanest free experiment, use this intentionally shareable sample repository under its MIT license in a usage mode permitted by GitHub's current CodeQL terms.

Save:

```text
results/codeql/<language>/
```

Decision:
- How much better is semantic/call/data-flow precision?
- Is the licensing acceptable for the intended product?

## Phase 5 — SonarQube Community Build
Goal: establish what Sonar gives us as a ready-made static analysis product.

1. start local SonarQube;
2. scan each sample;
3. compare issues, complexity and security findings;
4. inspect APIs/UI for structural information;
5. explicitly record what is *not* available as a reusable call/CFG/data-flow model.

Save exported API/SARIF/JSON where available.

## Phase 6 — Semgrep OSS
Goal: test fast rule-based/taint-oriented analysis.

1. run stock rules;
2. write one deliberately small cross-language-ish rule if practical;
3. test the unsafe CLI sink;
4. compare path depth with Joern/CodeQL.

## Phase 7 — Native precision baseline
Start with C# + Roslyn.

Build a tiny extractor that emits:

```json
{
  "types": [],
  "methods": [],
  "calls": [],
  "implements": [],
  "sourceLocations": []
}
```

Compare Roslyn's result against Joern and SCIP.

Only if useful, add analogous native frontends later:
- Java: compiler/SootUp/JavaParser
- TS: TypeScript Compiler API
- Python: Pyright/AST

## Phase 8 — Scorecard
For each tool/language score factual capabilities, not marketing:

| Capability | C# | Java | TS | Python |
|---|---:|---:|---:|---:|
| Types/symbols | | | | |
| Source ranges | | | | |
| References | | | | |
| Calls | | | | |
| Possible polymorphic targets | | | | |
| AST | | | | |
| CFG | | | | |
| Interprocedural data flow | | | | |
| Machine-readable output | | | | |
| Setup friction | | | | |
| License fit | | | | |

We will fill this from observed results.
