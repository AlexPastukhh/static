# GD-CAP semantic fix4

The real-project gate is down to seven unmapped calls:

- split x5
- toCharArray x1
- getSelectedIndices x1

All seven are Java enhanced-for iterable expressions that return arrays.

Examples:

  for (... : path.split("/"))
  for (... : value.toCharArray())
  for (... : elementList.getSelectedIndices())

Java array enhanced-for lowering differs from Iterable-based lowering. The source iterable
call can be placed beside synthetic index/length mechanics instead of under iterator().
The previous generic exact-text resolver could therefore select a lowering wrapper or miss
the call when javasrc2cpg rewrote the receiver in raw code.

Fix4 adds a FOREACH-specific iterable resolver:

1. inspect non-operator calls on the source header line;
2. reject iterator/hasNext/next lowering calls;
3. prefer exact source-code match;
4. otherwise match the terminal source method name on that same line;
5. fall back to the generic resolver for identifiers/literals/non-call expressions.

This is a general Java array-enhanced-for rule; it is not GD-CAP-specific.
