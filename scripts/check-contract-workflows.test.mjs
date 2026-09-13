import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

// Structural regression guard, not a YAML parser or GitHub expression engine.
const passExpression = "${{ fromJSON(github.event_name == 'workflow_dispatch' && inputs.repetitions == '3' && '[1,2,3]' || '[1]') }}";
for (const [file, jobs] of [
  ['contract-consumer.yml', 1],
  ['local-rpc.yml', 1],
  ['mobile-contract.yml', 2],
]) {
  test(`${file}: repetitions are opt-in and superseded runs cancel`, () => {
    const source = readFileSync(new URL(`../.github/workflows/${file}`, import.meta.url), 'utf8');
    assert.match(source, /workflow_dispatch:\s+inputs:\s+repetitions:/);
    assert.match(source, /type: choice\s+options: \['1', '3'\]\s+default: '1'/);
    assert.equal(source.split(`pass: ${passExpression}`).length - 1, jobs);
    assert.equal(source.match(/fail-fast: false/g)?.length, jobs);
    assert.match(source, /group: \$\{\{ github.workflow \}\}-\$\{\{ github.ref \}\}\s+cancel-in-progress: true/);
    if (file === 'mobile-contract.yml') {
      assert.match(source, /name: ios-contract-failure-\$\{\{ github.run_id \}\}-pass-\$\{\{ matrix.pass \}\}/);
    }
  });
}
