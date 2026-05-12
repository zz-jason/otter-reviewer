"use strict";

const assert = require("assert");
const { filterCodexReview, parseAllowedLines } = require("../bin/otter-reviewer");

const diff = `diff --git a/src/server.js b/src/server.js
index 1111111..2222222 100644
--- a/src/server.js
+++ b/src/server.js
@@ -1,2 +1,4 @@
 const a = 1;
+const b = req.query.cmd;
 const c = 3;
+execSync(b);
`;

const allowed = parseAllowedLines(diff);
assert.deepStrictEqual([...allowed.get("src/server.js")].sort((a, b) => a - b), [1, 2, 3, 4]);

const review = filterCodexReview(
  diff,
  {
    summary: "sample",
    comments: [
      { path: "src/server.js", line: 4, body: "valid", severity: "high" },
      { path: "src/server.js", line: 99, body: "invalid" },
      { path: "missing.js", line: 1, body: "invalid" },
    ],
  },
  10
);

assert.strictEqual(review.comments.length, 1);
assert.strictEqual(review.comments[0].path, "src/server.js");
assert.strictEqual(review.comments[0].line, 4);
assert.match(review.comments[0].body, /^\*\*high\*\*: valid/);
assert.match(review.summary, /Filtered out 2/);

console.log("filter.test.js passed");
