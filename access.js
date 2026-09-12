const crypto = require('node:crypto');

module.exports = function createAccess() {
  const code = process.env.ROOMS_DASHBOARD_CODE || '';
  const sessions = new Map();
  const attempts = new Map();
  const ttl = 8 * 60 * 60 * 1000;
  function sweep(map) {
    for (const [key, value] of map) if (value.expires <= Date.now()) map.delete(key);
  }
  function cookie(req, value, age) {
    const secure = process.env.NODE_ENV === 'production' || req.socket.encrypted;
    return `rooms_session=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${age}${secure ? '; Secure' : ''}`;
  }
  return async function access(req, res, url, readJson, sendJson) {
    sweep(sessions); sweep(attempts);
    const id = (req.headers.cookie || '').match(/(?:^|;\s*)rooms_session=([a-f0-9]{64})(?:;|$)/)?.[1];
    if (url.pathname === '/health' || url.pathname === '/api/ingest') return true;
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    if (req.method === 'POST' && url.pathname === '/api/login') {
      if (!code) { sendJson(res, 503, { error: 'Dashboard access is not configured.' }); return false; }
      // Use the socket address, never an untrusted forwarding header.
      const ip = req.socket.remoteAddress || 'unknown';
      let bucket = attempts.get(ip);
      if (!bucket) {
        if (attempts.size >= 10000) { sendJson(res, 429, {error: 'Try again later.'}); return false; }
        bucket = { count: 0, expires: Date.now() + 15 * 60 * 1000 }; attempts.set(ip, bucket);
      }
      if (++bucket.count > 10) { sendJson(res, 429, {error: 'Too many attempts. Try again in 15 minutes.'}); return false; }
      try {
        const body = await readJson(req);
        const actual = crypto.createHash('sha256').update(typeof body?.code === 'string' ? body.code : '').digest();
        const expected = crypto.createHash('sha256').update(code).digest();
        if (!crypto.timingSafeEqual(actual, expected)) { sendJson(res, 401, {error: 'Incorrect access code.'}); return false; }
        if (sessions.size >= 10000) { sendJson(res, 503, {error: 'Try again later.'}); return false; }
        const token = crypto.randomBytes(32).toString('hex');
        sessions.set(token, { expires: Date.now() + ttl });
        if (id) sessions.delete(id);
        res.setHeader('Set-Cookie', cookie(req, token, ttl / 1000));
        sendJson(res, 200, {ok: true});
      } catch { sendJson(res, 400, {error: 'Invalid request.'}); }
      return false;
    }
    if (req.method === 'POST' && url.pathname === '/api/logout') {
      sessions.delete(id);
      res.setHeader('Set-Cookie', cookie(req, '', 0));
      sendJson(res, 200, {ok: true}); return false;
    }
    if (req.method === 'GET' && ['/login', '/login.js', '/styles.css'].includes(url.pathname)) return true;
    if (code && sessions.has(id)) return true;
    if (url.pathname.startsWith('/api/') || url.pathname === '/analytics') sendJson(res, 401, {error: 'Sign in to view analytics.'});
    else { res.writeHead(303, {Location: '/login'}); res.end(); }
    return false;
  };
};
