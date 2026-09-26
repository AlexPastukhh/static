# Static Trace Explorer

Static Trace Explorer is an AppMap-like browser for **static end-to-end traces of possible execution paths**.

The user selects an entry method and explores what can happen from that point without rendering the entire application graph by default.

## Core idea

```text
source code
  ↓
Joern / CPG
  ↓
extractor
  ↓
normalized static execution model
  ↓
Static Trace Explorer
```

The explorer is static:

```text
what CAN happen
```

not:

```text
what DID happen
```

A runtime-observed overlay may be added later.

## Current scope

The repository contains experiments and normalization work for:

- Java
- Python
- TypeScript / Node
- C# / .NET

The current schema v3 is useful for methods, calls, ownership, polymorphic targets, and multi-hop traversal, but it does not yet provide the structural branch/expression relationships required for the final trace model.

The next backend milestone is to validate and extract the structural information required for schema v4:

- unique call-site identity;
- source position/order;
- AST parent/expression relationships;
- condition calls;
- control structures;
- branch membership;
- loops;
- try/catch/finally/throw context;
- evaluation ordering for nested/chained expressions.

## Product documents

- [`docs/PRODUCT_REQUIREMENTS.md`](docs/PRODUCT_REQUIREMENTS.md) — current product requirements and scope.
- [`docs/STATIC_TRACE_EXPLORER_DECISIONS.md`](docs/STATIC_TRACE_EXPLORER_DECISIONS.md) — accepted product/UI/model decisions.
- [`docs/STATIC_TRACE_EXPLORER_VISION.md`](docs/STATIC_TRACE_EXPLORER_VISION.md) — concise product direction.

When documents disagree, `STATIC_TRACE_EXPLORER_DECISIONS.md` is the decision record and has precedence until the other document is reconciled.

## Important UI rule

Folder/module ownership is visual metadata. It may group the sidebar or architecture/dependency views, but it must **not reorder the downstream execution trace**.

The execution trace follows source/control-flow/evaluation structure.

## Repository areas

```text
config/      viewer configuration
docs/        product direction and decisions
schema/      normalized model schemas
scripts/     Joern export, normalization, validation, viewer generation
viewer/      browser viewer templates
java-lab/    Java synthetic lab
python-lab/  Python synthetic lab
node-lab/    TypeScript/Node synthetic lab
dotnet-lab/  C#/.NET synthetic lab
results/     generated analysis results kept in the repository
```
