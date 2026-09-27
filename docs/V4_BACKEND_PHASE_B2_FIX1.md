# V4 backend Phase B2 fix1

Fixes over-broad iterator-lowering suppression.

The Python frontend places a source `for` loop inside a synthetic Block whose aggregate
Joern `code` contains tmp/iterator lowering text. B2 accidentally used that Block as a
suppression seed, which hid the normalized FOREACH wrapper and real source body steps.

Fix1:
- never uses Block/ControlStructure/Method as a lowering seed;
- never suppresses a raw control normalized as FOREACH;
- does not suppress semantic container descendants;
- traverses Block and normalized ControlStructure nodes before suppression;
- asserts every FOREACH BODY branch is non-empty.

Regression review against all four Phase A fix3 raw models confirmed that the source
business call inside each FOREACH body remains visible while iterator-lowering calls stay
suppressible.
