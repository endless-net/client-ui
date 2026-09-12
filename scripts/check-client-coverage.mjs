import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ids = (prefix, count) => Array.from({ length: count }, (_, i) => `${prefix}-${String(i + 1).padStart(2, '0')}`);
const expectedRequirements = [...ids('UF', 23), ...ids('UBR', 40), ...ids('UI-AC', 27)];
const platforms = ['android', 'ios', 'linux', 'macos', 'windows'];

export function validateCoverage(matrix, { requireComplete = false, repositoryRoot = root } = {}) {
  const file = (path) => {
    assert.equal(typeof path, 'string', 'Evidence path must be a string');
    const rel = relative(repositoryRoot, resolve(repositoryRoot, path));
    assert(!isAbsolute(path) && rel !== '..' && !rel.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`), 'Evidence must stay in the owning repository');
    assert(existsSync(resolve(repositoryRoot, path)), `Missing evidence file: ${path}`);
  };
  assert.deepEqual([...matrix.platforms].sort(), platforms, 'All five target platforms are required');
  file(matrix.sources.sa);
  for (const path of matrix.sharedEnvelopeTests) file(path);
  assert.deepEqual(matrix.scenarios.map((s) => s.id).sort(), ids('US', 14), 'All 14 SA scenarios are required exactly once');
  const covered = new Set();
  let complete = 0;
  for (const scenario of matrix.scenarios) {
    assert(scenario.title?.trim(), 'Scenario title is required');
    assert(['missing', 'partial', 'complete'].includes(scenario.implementation), 'Unknown implementation state');
    assert(scenario.requirements.length > 0, 'Scenario requirements are missing');
    assert.equal(new Set(scenario.requirements).size, scenario.requirements.length, 'Duplicate scenario requirement');
    for (const id of scenario.requirements) {
      assert(expectedRequirements.includes(id), `Unknown requirement: ${id}`);
      covered.add(id);
    }
    for (const test of scenario.testEvidence) {
      file(test.path);
      assert(test.scope?.trim(), 'Evidence must describe its actual scope');
    }
    if (scenario.implementation === 'complete') {
      assert(scenario.testEvidence.length, 'Complete scenario requires tests');
      const accepted = scenario.acceptanceEvidence;
      assert.deepEqual(accepted.map((e) => e.platform).sort(), platforms, 'Complete scenario requires acceptance on all five platforms');
      for (const evidence of accepted) {
        assert.equal(evidence.level, 'product', 'Mock/unit evidence cannot close product acceptance');
        assert.match(evidence.url, /^https:\/\/github\.com\/endless-net\/[a-z-]+\/(actions\/runs\/\d+|blob\/[a-f0-9]{40}\/\S+)$/, 'Acceptance must reference an immutable owning-repository artifact or run');
      }
      complete++;
    }
  }
  assert.deepEqual([...covered].sort(), [...expectedRequirements].sort(), 'Every UF/UBR/UI-AC must be traced');
  const executions = new Set();
  for (const execution of matrix.execution) {
    file(execution.workflow);
    assert(execution.scope?.trim(), 'Execution scope is required');
    assert(['pending', 'passed', 'failed'].includes(execution.status), 'Unknown execution state');
    if (execution.status === 'passed') {
      assert.match(execution.run, /^https:\/\/github\.com\/endless-net\/client-ui\/actions\/runs\/\d+$/, 'Passed execution requires a run');
    }
    for (const platform of execution.platforms) {
      assert(platforms.includes(platform) && !executions.has(platform), 'Invalid or duplicate execution platform');
      executions.add(platform);
    }
  }
  assert.deepEqual([...executions].sort(), platforms, 'Execution matrix omits a platform');
  if (requireComplete) {
    assert.equal(complete, 14, 'Planned functional scope is incomplete');
    assert(matrix.execution.every((e) => e.status === 'passed'), 'Required native execution is unproven');
  }
  return { requirements: covered.size + matrix.scenarios.length, completeScenarios: complete, totalScenarios: 14 };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const matrix = JSON.parse(readFileSync(resolve(root, 'tests/client-coverage.json'), 'utf8'));
  console.log(JSON.stringify(validateCoverage(matrix, { requireComplete: process.argv.includes('--require-complete') })));
}
