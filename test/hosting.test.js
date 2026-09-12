const {test} = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');
const {spawnSync} = require('node:child_process');
const {configuration} = require('../hosting');

test('allocated port overrides a stale old-host PORT and binds all interfaces', () => {
  const config = configuration({SERVER_PORT: '24680', PORT: '8787'}, __dirname);
  assert.equal(config.port, 24680);
  assert.equal(config.host, '0.0.0.0');
});
test('portable data path and legacy Render disk remain supported', () => {
  assert.equal(configuration({ROOMS_ANALYTICS_DATA_DIR: 'storage'}, __dirname).dataDir, path.join(__dirname, 'storage'));
  assert.equal(configuration({RENDER_DISK_PATH: 'old-disk'}, __dirname).dataDir, path.join(__dirname, 'old-disk'));
  assert.equal(configuration({}, __dirname).port, 8787);
});
test('invalid allocations fail clearly', () => {
  for (const SERVER_PORT of ['0', '65536', '123.5', 'abc']) assert.throws(() => configuration({SERVER_PORT}, __dirname), /integer/);
});
test('entry file can load .env without overwriting panel variables', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rooms-env-test-'));
  try {
    fs.writeFileSync(path.join(dir, '.env'), 'ROOMS_HOSTING_TEST_FILE=loaded\nROOMS_HOSTING_TEST_PANEL=from-file\n');
    const code = `require(${JSON.stringify(path.resolve(__dirname, '../hosting'))}).loadEnvironment(${JSON.stringify(dir)});console.log(JSON.stringify([process.env.ROOMS_HOSTING_TEST_FILE,process.env.ROOMS_HOSTING_TEST_PANEL]));`;
    const env = {...process.env, ROOMS_HOSTING_TEST_PANEL: 'from-panel'};
    delete env.ROOMS_ENV_FILE; delete env.ROOMS_HOSTING_TEST_FILE;
    const child = spawnSync(process.execPath, ['-e', code], {env, encoding: 'utf8', windowsHide: true});
    assert.equal(child.status, 0, child.stderr);
    assert.deepEqual(JSON.parse(child.stdout), ['loaded', 'from-panel']);
  } finally { fs.rmSync(dir, {recursive: true, force: true}); }
});
