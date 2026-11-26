// Local stand-in for Supabase (logins + REST API), used only to test the
// screens end to end against a real Postgres with the real 01_core_users.sql.
// Run: NODE_PATH=<dir with pg> node tests/mock-supabase.js   (serves the app on :8787)
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const ROOT = path.resolve(__dirname, '..');
const PORT = Number(process.env.PORT || 8787);
const pool = new Pool({ host: process.env.PGHOST || '/var/tmp/pg', port: Number(process.env.PGPORT || 5433), user: 'postgres', database: process.env.PGDATABASE || 'rbtest' });

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
const jwt = (claims) => b64({ alg: 'HS256', typ: 'JWT' }) + '.' + b64(claims) + '.mock';
const claimsOf = (req) => {
  const h = req.headers.authorization || '';
  const t = h.replace(/^Bearer\s+/i, '');
  try { return JSON.parse(Buffer.from(t.split('.')[1], 'base64url').toString()); } catch (e) { return { role: 'anon' }; }
};
const send = (res, code, body, headers) => {
  res.writeHead(code, Object.assign({ 'content-type': 'application/json', 'access-control-allow-origin': '*' }, headers || {}));
  res.end(body === undefined ? '' : JSON.stringify(body));
};
const readBody = (req) => new Promise((r) => { let d = ''; req.on('data', (c) => (d += c)); req.on('end', () => r(d ? JSON.parse(d) : {})); });

function session(user) {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  return {
    access_token: jwt({ sub: user.id, role: 'authenticated', email: user.email, exp, aud: 'authenticated' }),
    token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'r-' + user.id,
    user: { id: user.id, email: user.email, aud: 'authenticated', role: 'authenticated', app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() },
  };
}

async function asRole(claims, fn) {
  const c = await pool.connect();
  try {
    await c.query('begin');
    const role = ['authenticated', 'service_role'].includes(claims.role) ? claims.role : 'anon';
    await c.query('set local role ' + role);
    await c.query("select set_config('request.jwt.claim.sub', $1, true), set_config('request.jwt.claim.role', $2, true)", [claims.sub || '', role]);
    const out = await fn(c);
    await c.query('commit');
    return out;
  } catch (e) { await c.query('rollback'); throw e; } finally { c.release(); }
}

async function auth(req, res, url) {
  const body = req.method === 'GET' ? {} : await readBody(req);
  const p = url.pathname.replace('/auth/v1', '');
  if (p === '/token' && url.searchParams.get('grant_type') === 'password') {
    const r = await pool.query('select id, email from auth.users where lower(email)=lower($1) and encrypted_password = extensions.crypt($2, encrypted_password)', [body.email, body.password]);
    if (!r.rows[0]) return send(res, 400, { code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials' });
    return send(res, 200, session(r.rows[0]));
  }
  if (p === '/token' && url.searchParams.get('grant_type') === 'refresh_token') {
    const id = String(body.refresh_token || '').replace(/^r-/, '');
    const r = await pool.query('select id, email from auth.users where id::text=$1', [id]);
    if (!r.rows[0]) return send(res, 400, { code: 400, msg: 'Invalid Refresh Token' });
    return send(res, 200, session(r.rows[0]));
  }
  if (p === '/signup') {
    try {
      const r = await pool.query("insert into auth.users(email, encrypted_password) values (lower($1), extensions.crypt($2, extensions.gen_salt('bf'))) returning id, email", [body.email, body.password]);
      return send(res, 200, session(r.rows[0]));
    } catch (e) {
      if (/duplicate key/.test(e.message)) return send(res, 422, { code: 422, error_code: 'user_already_exists', msg: 'User already registered' });
      return send(res, 500, { code: 500, error_code: 'unexpected_failure', msg: 'Database error saving new user' });
    }
  }
  const cl = claimsOf(req);
  if (p === '/user' && req.method === 'GET') {
    const r = await pool.query('select id, email from auth.users where id::text=$1', [cl.sub || '']);
    return r.rows[0] ? send(res, 200, session(r.rows[0]).user) : send(res, 401, { msg: 'invalid JWT' });
  }
  if (p === '/user' && req.method === 'PUT') {
    if (body.password) await pool.query("update auth.users set encrypted_password = extensions.crypt($2, extensions.gen_salt('bf')) where id::text=$1", [cl.sub, body.password]);
    const r = await pool.query('select id, email from auth.users where id::text=$1', [cl.sub]);
    return send(res, 200, session(r.rows[0]).user);
  }
  if (p === '/logout') return send(res, 204);
  return send(res, 404, { msg: 'not mocked: ' + p });
}

const ident = (s) => { if (!/^[a-z_][a-z0-9_]*$/.test(s)) throw new Error('bad identifier ' + s); return '"' + s + '"'; };

async function rest(req, res, url) {
  const cl = claimsOf(req);
  const parts = url.pathname.replace('/rest/v1/', '').split('/');
  try {
    if (parts[0] === 'rpc') {
      const fn = parts[1], args = req.method === 'GET' ? {} : await readBody(req);
      const meta = await pool.query("select proretset, prorettype::regtype::text as rt from pg_proc where proname=$1 and pronamespace='public'::regnamespace", [fn]);
      if (!meta.rows[0]) return send(res, 404, { message: 'function not found' });
      const keys = Object.keys(args);
      const sql = 'select * from public.' + ident(fn) + '(' + keys.map((k, i) => ident(k) + ' => $' + (i + 1)).join(', ') + ') as r';
      const vals = keys.map((k) => (args[k] !== null && typeof args[k] === 'object' ? JSON.stringify(args[k]) : args[k]));
      const rows = await asRole(cl, (c) => c.query(sql, vals).then((r) => r.rows));
      const col = (r) => r[Object.keys(r)[0]];
      if (meta.rows[0].proretset) return send(res, 200, rows.map(col));
      if (meta.rows[0].rt === 'void') return send(res, 200, null);
      return send(res, 200, rows[0] ? col(rows[0]) : null);
    }
    const table = ident(parts[0]);
    let cols = '*', where = [], vals = [], order = '', limit = '', offset = '';
    for (const [k, v] of url.searchParams) {
      if (k === 'select') cols = v === '*' ? '*' : v.split(',').map((c) => ident(c.trim())).join(',');
      else if (k === 'order') order = ' order by ' + v.split(',').map((o) => { const [c, d] = o.split('.'); return ident(c) + (d === 'desc' ? ' desc' : ' asc'); }).join(',');
      else if (k === 'limit') limit = ' limit ' + Number(v);
      else if (k === 'offset') offset = ' offset ' + Number(v);
      else {
        const m = /^(eq|neq|gte|lte|gt|lt|in|is)\.(.*)$/.exec(v);
        const ops = { eq: '=', neq: '<>', gte: '>=', lte: '<=', gt: '>', lt: '<' };
        if (m[1] === 'in') { const list = m[2].replace(/^\(|\)$/g, '').split(','); where.push(ident(k) + '::text = any($' + (vals.length + 1) + ')'); vals.push(list); }
        else if (m[1] === 'is') where.push(ident(k) + ' is ' + (m[2] === 'null' ? 'null' : m[2]));
        else { where.push(ident(k) + ops[m[1]] + '$' + (vals.length + 1)); vals.push(m[2]); }
      }
    }
    if (req.method !== 'GET') return send(res, 405, { message: 'writes are not mocked' });
    const sql = 'select ' + cols + ' from public.' + table + (where.length ? ' where ' + where.join(' and ') : '') + order + limit + offset;
    const rows = await asRole(cl, (c) => c.query(sql, vals).then((r) => r.rows));
    if ((req.headers.accept || '').includes('vnd.pgrst.object')) {
      if (rows.length !== 1) return send(res, 406, { message: 'JSON object requested, multiple (or no) rows returned' });
      return send(res, 200, rows[0]);
    }
    return send(res, 200, rows);
  } catch (e) {
    const code = /permission denied/.test(e.message) ? 401 : 400;
    return send(res, code, { message: e.message, code: e.code });
  }
}

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png', '.webmanifest': 'application/manifest+json', '.json': 'application/json' };
http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (req.method === 'OPTIONS') return send(res, 204, undefined, { 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' });
  try {
    if (url.pathname.startsWith('/auth/v1')) return await auth(req, res, url);
    if (url.pathname.startsWith('/rest/v1')) return await rest(req, res, url);
    if (url.pathname === '/config.js') {
      res.writeHead(200, { 'content-type': 'text/javascript' });
      return res.end("window.RB_CONFIG={SUPABASE_URL:'http://localhost:" + PORT + "',SUPABASE_ANON_KEY:'" + jwt({ role: 'anon' }) + "'};");
    }
    const f = path.join(ROOT, url.pathname === '/' ? 'index.html' : decodeURIComponent(url.pathname));
    if (!f.startsWith(ROOT) || !fs.existsSync(f)) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'content-type': TYPES[path.extname(f)] || 'application/octet-stream' });
    fs.createReadStream(f).pipe(res);
  } catch (e) { send(res, 500, { message: e.message }); }
}).listen(PORT, () => console.log('mock supabase + app on http://localhost:' + PORT));
