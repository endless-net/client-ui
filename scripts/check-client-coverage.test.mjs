import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { validateCoverage } from './check-client-coverage.mjs';

const fixture = () => JSON.parse(readFileSync(new URL('../tests/client-coverage.json', import.meta.url), 'utf8'));
test('trace matrix includes the full 104-ID goal but does not claim completion', () => {
  assert.deepEqual(validateCoverage(fixture()), { requirements: 104, completeScenarios: 0, totalScenarios: 14 });
  assert.throws(() => validateCoverage(fixture(), { requireComplete: true }), /incomplete/);
});
test('deleting the sole coverage of a BA requirement fails', () => {
  const matrix = fixture();
  for (const scenario of matrix.scenarios) scenario.requirements = scenario.requirements.filter((id) => id !== 'UBR-40');
  assert.throws(() => validateCoverage(matrix), /Every UF/);
});
test('desktop-only execution cannot stand in for mobile', () => {
  const matrix = fixture();
  matrix.execution.pop();
  assert.throws(() => validateCoverage(matrix), /omits a platform/);
});
test('a test file is not product acceptance evidence', () => {
  const matrix = fixture();
  matrix.scenarios[0].implementation = 'complete';
  assert.throws(() => validateCoverage(matrix), /all five platforms/);
});
test('unverified green execution cannot be asserted without a run', () => {
  const matrix = fixture();
  matrix.execution[0].status = 'passed';
  assert.throws(() => validateCoverage(matrix));
});
test('missing tests and out-of-repository references fail validation', () => {
  for (const path of ['app/test/missing.dart', '../client/AGENTS.md']) {
    const matrix = fixture();
    matrix.sharedEnvelopeTests.push(path);
    assert.throws(() => validateCoverage(matrix));
  }
});
