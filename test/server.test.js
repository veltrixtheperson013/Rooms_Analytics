const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const {spawn} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
let child, base, folder, cookie;
async function request(route, options = {}) { return fetch(base + route, {redirect: 'manual', ...options}); }
function json(body, headers = {}) { return {method: 'POST', headers: {'Content-Type': 'application/json', ...headers}, body: JSON.stringify(body)}; }
before(async () => {
  folder = fs.mkdtempSync(path.join(os.tmpdir(), 'rooms-test-'));
  const probe = net.createServer(); await new Promise(r => probe.listen(0, '127.0.0.1', r));
  const port = probe.address().port; await new Promise(r => probe.close(r));
  base = `http://127.0.0.1:${port}`;
  child = spawn(process.execPath, ['server.js'], {cwd: path.join(__dirname, '..'), windowsHide: true, env: {...process.env, NODE_ENV: 'test', SERVER_PORT: String(port), PORT: '8787', ROOMS_ANALYTICS_DATA_DIR: folder, ROOMS_DASHBOARD_CODE: 'test-dashboard-code', ROOMS_ANALYTICS_TOKEN: 'test-ingest-token', ROOMS_ANALYTICS_GIST_ID: ''}, stdio: 'ignore'});
  for (let i = 0; i < 100; i++) { try { if ((await request('/health')).ok) return; } catch {} await new Promise(r => setTimeout(r, 50)); }
  throw new Error('Server did not start');
});
after(async () => { if (child) { const stopped = new Promise(r => child.once('exit', r)); child.kill(); await stopped; } if (folder) fs.rmSync(folder, {recursive: true, force: true}); });
test('private pages and both analytics aliases require login', async () => {
  for (const route of ['/', '/index.html', '/app.js']) assert.equal((await request(route)).status, 303);
  for (const route of ['/api/analytics', '/analytics']) assert.equal((await request(route)).status, 401);
  assert.equal((await request('/login')).status, 200);
});
test('wrong code fails; correct code sets an HttpOnly session', async () => {
  assert.equal((await request('/api/login', json({code: 'wrong'}))).status, 401);
  const response = await request('/api/login', json({code: 'test-dashboard-code'}));
  assert.equal(response.status, 200); const header = response.headers.get('set-cookie');
  assert.match(header, /HttpOnly/); assert.match(header, /SameSite=Strict/); cookie = header.split(';')[0];
  assert.equal((await request('/api/analytics', {headers: {cookie}})).status, 200);
});
test('ingest uses its separate token and rejects default credentials', async () => {
  assert.equal((await request('/api/ingest', json({TotalSessions: 1}, {'x-rooms-token': 'change-me-local-token'}))).status, 401);
});
test('newer snapshots win; retries and stale uploads cannot roll back totals', async () => {
  const headers = {'x-rooms-token': 'test-ingest-token'};
  const snapshot = {TotalSessions: 5, Revision: 5, TotalDeaths: 2, LastUpdatedUtc: new Date().toISOString(), Categories: {Game: {TotalSessions: 5}}, DeathCauses: {'A-60': 2}};
  assert.equal((await request('/api/ingest', json(snapshot, headers))).status, 200);
  assert.equal((await (await request('/api/ingest', json(snapshot, headers))).json()).mode, 'stale');
  assert.equal((await (await request('/api/ingest', json({TotalSessions: 2}, headers))).json()).mode, 'stale');
  const data = await (await request('/api/analytics', {headers: {cookie}})).json();
  assert.equal(data.TotalSessions, 5); assert.equal(data.TotalDeaths, 2);
});
test('malformed, negative, nested, and delta payloads are rejected', async () => {
  const headers = {'x-rooms-token': 'test-ingest-token'};
  for (const payload of [null, [], {TotalSessions: -2}, {TotalSessions: 6, Categories: {a: {Categories: {b: {Categories: {c: {}}}}}}}]) assert.equal((await request('/api/ingest', json(payload, headers))).status, 400);
  assert.equal((await request('/api/ingest', json({playtimeSeconds: 10}, headers))).status, 422);
  const proto = JSON.parse('{"TotalSessions":6,"DeathCauses":{"__proto__":3}}');
  assert.equal((await request('/api/ingest', json(proto, headers))).status, 400);
});
test('destructive endpoints require authentication and demo cannot overwrite real data', async () => {
  assert.equal((await request('/api/wipe/request-code', json({}))).status, 401);
  assert.equal((await request('/api/demo-sample', json({}, {cookie}))).status, 403);
});
test('logout revokes the session', async () => {
  assert.equal((await request('/api/logout', json({}, {cookie}))).status, 200);
  assert.equal((await request('/api/analytics', {headers: {cookie}})).status, 401);
});
test('login guessing is rate limited', async () => {
  let response;
  for (let i = 0; i < 11; i++) response = await request('/api/login', json({code: 'wrong'}));
  assert.equal(response.status, 429);
});
