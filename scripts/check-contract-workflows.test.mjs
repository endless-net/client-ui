import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
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
    assert.match(source, /workflow_dispatch:\s+inputs:/);
    assert.match(source, /^      repetitions:/m);
    assert.doesNotMatch(source, /^  push:/m);
    assert.match(source, /^  pull_request:/m);
    assert.match(source, /type: choice\s+options: \['1', '3'\]\s+default: '1'/);
    assert.equal(source.split(`pass: ${passExpression}`).length - 1, jobs);
    assert.equal(source.match(/fail-fast: false/g)?.length, jobs);
    assert.match(source, /group: \$\{\{ github.workflow \}\}-\$\{\{ github.ref \}\}\s+cancel-in-progress: true/);
    if (file === 'mobile-contract.yml') {
      assert.match(source, /name: ios-contract-failure-\$\{\{ github.run_id \}\}-pass-\$\{\{ matrix.pass \}\}/);
    }
  });
}

test('branch pushes run only the short workflow', () => {
  const root = new URL('../.github/workflows/', import.meta.url);
  for (const file of readdirSync(root).filter((name) => name.endsWith('.yml'))) {
    const source = readFileSync(new URL(file, root), 'utf8');
    if (file === 'release.yml') {
      assert.match(source, /push:\s+tags:/); // Explicit publication is separate.
      continue;
    }
    if (file !== 'short.yml') assert.doesNotMatch(source, /^  push:/m, file);
  }
  const source = readFileSync(new URL('short.yml', root), 'utf8');
  assert.match(source, /push:\s+branches: \[main\]/);
  assert.match(source, /go test -short \.\/\.\.\./);
  assert.match(source, /flutter test --no-pub --tags short/);
  assert.doesNotMatch(source, /matrix:|repository: endless-net\/client|ENDLESSNET_TESTSERVER|flutter build|emulator|simulator/);
  assert.match(source, /cancel-in-progress: true/);
});

function assertNativeBuildOnly(raw) {
  const source = raw.replaceAll('\r\n', '\n');
  assert.match(source, /native_build_only:\s+description: '[^']+'\s+type: boolean\s+default: false/);
  for (const [os, target] of [['ubuntu-latest', 'linux'], ['windows-2022', 'windows'], ['macos-latest', 'macos']]) {
    assert.ok(source.includes(`- os: ${os}\n            target: ${target}`));
  }
  assert.match(source, /run: flutter build \$\{\{ matrix.target \}\} --debug --no-pub/);
  assert.match(source, /run: flutter pub get --enforce-lockfile/);
  assert.match(source, /Validate complete BA and SA trace scope\s+shell: bash/);
  assert.match(source, /libayatana-appindicator3-dev/);
  const steps = source.split(/^      - /m).slice(1);
  for (const marker of ['repository: endless-net/client', 'actions/setup-go@', 'Build pinned producer scenario host', 'Test complete native consumer suite', 'Verify app transport after stream cancellation']) {
    const step = steps.find((value) => value.includes(marker));
    assert.ok(step, marker);
    assert.ok(step.includes('if: ${{ !inputs.native_build_only }}'), marker);
  }
  assert.doesNotMatch(source, /workflow_run:|secrets\.|signing|publish|upload-artifact/);
}

test('native build-only mode compiles real hosts without producer or integration execution', () => {
  const source = readFileSync(new URL('../.github/workflows/contract-consumer.yml', import.meta.url), 'utf8');
  assertNativeBuildOnly(source.replaceAll('\r\n', '\n'));
  assertNativeBuildOnly(source.replace(/\r?\n/g, '\r\n'));
});

test('native build-only guard rejects unguarded testserver even with CRLF', () => {
  const source = readFileSync(new URL('../.github/workflows/contract-consumer.yml', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
  const unsafe = source.replace('name: Build pinned producer scenario host\n        if: ${{ !inputs.native_build_only }}', 'name: Build pinned producer scenario host');
  assert.notEqual(unsafe, source);
  assert.throws(() => assertNativeBuildOnly(unsafe.replaceAll('\n', '\r\n')));
});

test('every Flutter suite explicitly chooses short or integration', () => {
  const root = new URL('../app/test/', import.meta.url);
  for (const name of readdirSync(root).filter((name) => name.endsWith('_test.dart'))) {
    const source = readFileSync(new URL(name, root), 'utf8');
    assert.match(source, /^@Tags\(\['(short|integration)'\]\)\s+library;/, name);
    if (/process_test|wire_test|loopback_contract_test|local_client_events_test/.test(name)) {
      assert.match(source, /^@Tags\(\['integration'\]\)/, name);
    }
  }
});
