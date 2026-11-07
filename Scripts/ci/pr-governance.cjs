'use strict';

const fs = require('node:fs');
const MARKER = '<!-- pitchee-pr-governance:v1 -->';
const SUBMODULES = new Set(['Dependencies/PitcheeCore', 'Docs/Voice-Training-Library']);

function escaped(value) {
  return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/@/g, '&#64;').replace(/\r?\n/g, ' ');
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}
function equal(left, right) { return JSON.stringify(canonical(left)) === JSON.stringify(canonical(right)); }

function catalogDiff(oldText, newText) {
  const before = oldText === null ? {strings: {}} : JSON.parse(oldText);
  const after = newText === null ? {strings: {}} : JSON.parse(newText);
  if (!before.strings || !after.strings || typeof before.strings !== 'object' || typeof after.strings !== 'object' || Array.isArray(before.strings) || Array.isArray(after.strings)) {
    throw new Error('xcstrings must contain a strings object');
  }
  const oldKeys = Object.keys(before.strings), newKeys = Object.keys(after.strings);
  const added = newKeys.filter(key => !Object.hasOwn(before.strings, key)).sort();
  const removed = oldKeys.filter(key => !Object.hasOwn(after.strings, key)).sort();
  const changed = newKeys.filter(key => Object.hasOwn(before.strings, key) && !equal(before.strings[key], after.strings[key])).sort();
  const metadata = [...new Set([...Object.keys(before), ...Object.keys(after)])].filter(key => key !== 'strings' && !equal(before[key], after[key])).sort();
  return {added, removed, changed, metadata, formattingOnly: oldText !== newText && equal(before, after)};
}

async function treeEntry(github, repo, ref, path) {
  let treeSha = ref;
  const pieces = path.split('/');
  for (let i = 0; i < pieces.length; ++i) {
    const {data} = await github.rest.git.getTree({...repo, tree_sha: treeSha});
    if (data.truncated) throw new Error('GitHub truncated a tree; refusing an incomplete diff');
    const entry = data.tree.find(item => item.path === pieces[i]);
    if (!entry) return null;
    if (i === pieces.length - 1) return entry;
    if (entry.type !== 'tree') return null;
    treeSha = entry.sha;
  }
}

async function catalogText(github, repo, ref, path, optional) {
  const entry = await treeEntry(github, repo, ref, path);
  if (!entry && optional) return null;
  if (!entry || entry.type !== 'blob' || !['100644', '100755'].includes(entry.mode)) throw new Error(`Catalog is not a regular file: ${path}`);
  const {data} = await github.rest.git.getBlob({...repo, file_sha: entry.sha});
  if (data.size > 16 * 1024 * 1024 || data.encoding !== 'base64') throw new Error('Catalog exceeds 16 MiB or uses an unsupported encoding');
  return Buffer.from(data.content, 'base64').toString('utf8');
}

function keyList(title, keys) {
  return [`- ${title}: ${keys.length}`, ...keys.map(key => `  - <code>${escaped(key)}</code>`)];
}

async function run({github, context, core}) {
  const number = context.payload.pull_request.number;
  const {data: pr} = await github.rest.pulls.get({...context.repo, pull_number: number});
  if (pr.base.repo.full_name !== `${context.repo.owner}/${context.repo.repo}` || pr.base.ref !== 'main') throw new Error('Unexpected PR base');
  if (pr.changed_files > 3000) throw new Error('PR exceeds GitHub file-list limit; manual catalog review is required');
  const headSha = pr.head.sha;
  const headRepo = {owner: pr.head.repo.owner.login, repo: pr.head.repo.name};
  const {data: comparison} = await github.rest.repos.compareCommitsWithBasehead({...context.repo, basehead: `${pr.base.sha}...${headSha}`, per_page: 1});
  const baseline = comparison.merge_base_commit.sha;
  const files = await github.paginate(github.rest.pulls.listFiles, {...context.repo, pull_number: number, per_page: 100});
  const report = [MARKER, '## PR catalog and submodule summary', '', `Compared PR merge base \`${baseline}\` → head \`${headSha}\`.`, ''];
  const catalogs = files.filter(file => file.filename.endsWith('.xcstrings') || file.previous_filename?.endsWith('.xcstrings'));
  if (!catalogs.length) report.push('No string catalogs changed.');
  for (const file of catalogs) {
    const oldName = file.previous_filename || file.filename;
    const oldText = await catalogText(github, context.repo, baseline, oldName, file.status === 'added');
    const newText = await catalogText(github, headRepo, headSha, file.filename, file.status === 'removed');
    const diff = catalogDiff(oldText, newText);
    report.push('', `### <code>${escaped(file.filename)}</code>`, '', ...keyList('Added keys', diff.added), ...keyList('Removed keys', diff.removed), ...keyList('Changed keys', diff.changed));
    if (file.status === 'renamed') report.push(`- Renamed from <code>${escaped(oldName)}</code>.`);
    if (diff.metadata.length) report.push(`- Catalog metadata changed: ${diff.metadata.map(escaped).join(', ')}.`);
    if (diff.formattingOnly) report.push('**Warning: keys and contents are identical; this diff only reorders or reformats the catalog.**');
  }
  const modulePaths = [...new Set(files.flatMap(file => [file.filename, file.previous_filename]).filter(path => SUBMODULES.has(path)))];
  for (const path of modulePaths) {
    const before = await treeEntry(github, context.repo, baseline, path);
    const after = await treeEntry(github, headRepo, headSha, path);
    if (before?.mode !== '160000' && after?.mode !== '160000') continue;
    if (before?.sha === after?.sha && before?.mode === after?.mode) continue;
    const link = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/workflows/submodule-regression.yml`;
    report.push('', `### <code>${escaped(path)}</code>`, '', `Locked checkpoint: \`${before?.sha || 'absent'}\` → \`${after?.sha || 'absent'}\`.`, `[Submodule regression runs](${link}) — read the exact differences in the regression comment/artifacts before reviewing this bump. No tolerance or automatic acceptance is applied.`);
  }
  const fullReport = report.join('\n') + '\n';
  fs.mkdirSync('.build', {recursive: true});
  fs.writeFileSync('.build/pr-governance.md', fullReport);
  await core.summary.addRaw(fullReport).write();
  // Never execute PR files. The sole artifact is inert text produced here.
  const runURL = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const body = fullReport.length > 55000 ? `${fullReport.slice(0, 54000)}\n\n[Complete key lists in this run's artifact](${runURL}).\n` : fullReport;
  const {data: current} = await github.rest.pulls.get({...context.repo, pull_number: number});
  if (current.head.sha !== headSha || current.base.sha !== pr.base.sha) {
    core.notice('PR changed during analysis; a newer run will publish its summary.');
    return;
  }
  const comments = await github.paginate(github.rest.issues.listComments, {...context.repo, issue_number: number, per_page: 100});
  const existing = comments.find(comment => comment.user?.login === 'github-actions[bot]' && comment.body?.startsWith(MARKER));
  if (existing) await github.rest.issues.updateComment({...context.repo, comment_id: existing.id, body});
  else if (catalogs.length || modulePaths.length) await github.rest.issues.createComment({...context.repo, issue_number: number, body});
}

module.exports = run;
Object.assign(module.exports, {catalogDiff, escaped, treeEntry});
