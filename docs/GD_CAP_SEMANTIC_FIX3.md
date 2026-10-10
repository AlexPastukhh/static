# GD-CAP semantic fix3

The whole-project report reduced the remaining issue to 279 unmapped raw calls.
The diagnostic sample shows a strong pattern:

- Java `return new X(...)` lowering hides constructors and all nested calls inside a
  synthetic Block;
- source call chains rooted at `new X(...)` can lose their real receiver because the
  old synthetic-receiver heuristic guessed from text before the first parenthesis;
- frontend Local/Unknown wrappers can hide call roots from method/branch traversal.

Fix3:

1. Java RETURN recognizes lowered object-construction Blocks and selects the outer
   `<init>` call as the source-semantic return value.
2. `<init>` still suppresses its synthetic `$objN` allocation receiver.
3. Real receivers such as `new ProcessBuilder(...).directory(...)` are no longer
   classified as implicit merely because the text before the first `(` lacks a dot.
4. Non-call expression wrappers preserve semantic child expressions while skipping
   `<operator>.alloc`.
5. Method/branch traversal recurses through otherwise-unhandled AST containers.

Regression check against the real CopyNoteMaterialFeature.copyMany structural probe:
`return new CopyOutcome(prepared.stream().map(...).toList(), createdAssets.size())`
selects the outer CopyOutcome constructor and recursively covers constructor + stream +
map + toList + size.

No schema change is required.
