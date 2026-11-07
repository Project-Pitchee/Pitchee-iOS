'use strict';

const {execFileSync} = require('node:child_process');
const pins = [
  {name: 'Core', path: 'Dependencies/PitcheeCore', owner: 'project-pitchee', repo: 'Core'},
  {name: 'Articles', path: 'Docs/Voice-Training-Library', owner: 'project-pitchee', repo: 'Articles'},
];

function marker(path) { return `<!-- pitchee-submodule-drift:${path} -->`; }
function existingIssue(issues, path) {
  return issues.find(issue => !issue.pull_request && issue.user?.type === 'Bot' && issue.body?.includes(marker(path)));
}

async function run({github, context, core}) {
  const issues = await github.paginate(github.rest.issues.listForRepo, {...context.repo, state: 'open', per_page: 100});
  const summary = ['## Locked submodules and upstream HEAD', '', '| Submodule | Locked | Upstream | State |', '|---|---|---|---|'];
  for (const module of pins) {
    const configuredURL = execFileSync('git', ['config', '--file', '.gitmodules', '--get', `submodule.${module.path}.url`], {encoding: 'utf8'}).trim();
    const expectedURL = `https://github.com/${module.owner}/${module.repo}.git`;
    if (configuredURL !== expectedURL) throw new Error(`Upstream URL changed for ${module.path}; update the reviewed drift-watch repository mapping.`);
    // Read the committed gitlink, not a possibly modified submodule worktree.
    const tree = execFileSync('git', ['ls-tree', 'HEAD', '--', module.path], {encoding: 'utf8'});
    const matched = /^160000 commit ([0-9a-f]{40})\t/.exec(tree);
    if (!matched) throw new Error(`Missing committed gitlink: ${module.path}`);
    const locked = matched[1];
    const repo = await github.rest.repos.get({owner: module.owner, repo: module.repo});
    const upstream = (await github.rest.repos.getCommit({owner: module.owner, repo: module.repo, ref: repo.data.default_branch})).data.sha;
    if (!/^[0-9a-f]{40}$/.test(upstream)) throw new Error(`Invalid upstream SHA for ${module.path}`);
    summary.push(`| ${module.name} | \`${locked}\` | \`${upstream}\` | ${locked === upstream ? 'Aligned' : 'Drift detected'} |`);
    if (locked === upstream) continue;
    const body = [
      marker(module.path), `The locked ${module.name} checkpoint differs from its upstream default-branch HEAD.`, '',
      `- Path: \`${module.path}\``, `- Locked: \`${locked}\``, `- Upstream: \`${upstream}\``,
      `- [Review changes](https://github.com/${module.owner}/${module.repo}/compare/${locked}...${upstream})`, '',
      'Review the contract changes and start a manual bump PR when ready. The submodule regression workflow will report old/new outputs.',
      'This watch only reports drift; it never changes gitlinks or merges PRs.',
    ].join('\n');
    const existing = existingIssue(issues, module.path);
    if (existing) {
      if (existing.body !== body) await github.rest.issues.update({...context.repo, issue_number: existing.number, body});
      core.info(`Updated existing ${module.name} drift issue #${existing.number}.`);
    } else {
      const created = await github.rest.issues.create({...context.repo, title: `${module.name} upstream changed; review the locked checkpoint`, body});
      issues.push(created.data);
    }
  }
  await core.summary.addRaw(summary.join('\n')).write();
}
module.exports = run;
module.exports.existingIssue = existingIssue;
