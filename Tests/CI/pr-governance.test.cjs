'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {catalogDiff, escaped, treeEntry} = require('../../Scripts/ci/pr-governance.cjs');
const {existingIssue} = require('../../Scripts/ci/submodule-drift.cjs');

test('xcstrings distinguishes real changes from formatting and metadata', () => {
  const before = JSON.stringify({sourceLanguage: 'en', strings: {keep: {value: 'same'}, change: {value: 'old'}, remove: {}}});
  const after = JSON.stringify({strings: {add: {}, change: {value: 'new'}, keep: {value: 'same'}}, sourceLanguage: 'en'});
  assert.deepEqual(catalogDiff(before, after), {added: ['add'], removed: ['remove'], changed: ['change'], metadata: [], formattingOnly: false});
  const reordered = JSON.stringify({strings: {remove: {}, change: {value: 'old'}, keep: {value: 'same'}}, sourceLanguage: 'en'}, null, 2);
  assert.equal(catalogDiff(before, reordered).formattingOnly, true);
  const metadata = catalogDiff(before, before.replace('"en"', '"fr"'));
  assert.equal(metadata.formattingOnly, false);
  assert.deepEqual(metadata.metadata, ['sourceLanguage']);
});

test('catalog additions, removals and unusual keys are not lost', () => {
  const catalog = '{"strings":{"__proto__":{},"@someone <script>\n":{}}}'.replace('\n', '\\n');
  assert.equal(catalogDiff(null, catalog).added.length, 2);
  assert.equal(catalogDiff(catalog, null).removed.length, 2);
  assert.equal(escaped('@someone <script>\nnext'), '&#64;someone &lt;script&gt; next');
});

test('tree lookup rejects truncated API results instead of inventing missing files', async () => {
  const github = {rest: {git: {getTree: async () => ({data: {truncated: true, tree: []}})}}};
  await assert.rejects(treeEntry(github, {}, 'sha', 'file'), /truncated/);
});

test('drift deduplication is per submodule and does not mistake PRs or human comments', () => {
  const marker = '<!-- pitchee-submodule-drift:Dependencies/PitcheeCore -->';
  const issues = [
    {number: 1, user: {type: 'User'}, body: marker},
    {number: 2, user: {type: 'Bot'}, body: marker, pull_request: {}},
    {number: 3, user: {type: 'Bot'}, body: marker},
  ];
  assert.equal(existingIssue(issues, 'Dependencies/PitcheeCore').number, 3);
  assert.equal(existingIssue(issues, 'Docs/Voice-Training-Library'), undefined);
});
