require('reflect-metadata');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { test } = require('node:test');
const { hash } = require('@node-rs/argon2');
const { Client } = require('pg');
const { NestFactory } = require('@nestjs/core');
const { AppModule } = require('../dist/app.module');
const { configureHttp, hashToken } = require('../dist/auth/http-security');
const { validateEnvironment, parseDatabaseUrl } = require('../dist/config/environment');

const ORIGIN = 'http://127.0.0.1:4101';
const PASSWORD = 'Ficticia-Fase21-Larga';
const NEW_PASSWORD = 'Ficticia-Fase21-Rotada';

function client(settings, tls) {
  return new Client({ ...settings, ssl: tls ? { rejectUnauthorized: true } : false,
    connectionTimeoutMillis: 3000, statement_timeout: 3000 });
}

async function start() {
  const app = await NestFactory.create(AppModule, { logger: false, abortOnError: false });
  configureHttp(app);
  await app.listen(0, '127.0.0.1');
  const base = await app.getUrl();
  return {
    close: () => app.close(),
    async request(path, { method = 'GET', cookie, body, origin = ORIGIN, csrf = true, headers = {} } = {}) {
      const response = await fetch(base + path, {
        method,
        headers: {
          ...(origin && { Origin: origin }),
          ...(csrf && { 'X-Contago-CSRF': '1' }),
          ...(cookie && { Cookie: cookie }),
          ...(body && { 'Content-Type': 'application/json' }),
          ...headers,
        },
        body: body && JSON.stringify(body),
      });
      const setCookie = response.headers.get('set-cookie');
      const content = await response.text();
      return { status: response.status, headers: response.headers, setCookie,
        cookie: setCookie?.split(';')[0], body: content ? JSON.parse(content) : undefined };
    },
  };
}

function verifyTarget() {
  if (process.env.NODE_ENV !== 'test' || !process.env.AUTH_TEST_OWNER_URL ||
      !process.env.AUTH_DATABASE_URL || !process.env.ADMIN_DATABASE_URL) {
    throw new Error('Configure las cuatro conexiones y NODE_ENV=test en un clúster desechable');
  }
  const { database } = validateEnvironment(process.env);
  const owner = parseDatabaseUrl(process.env.AUTH_TEST_OWNER_URL, 'AUTH_TEST_OWNER_URL');
  if (!/^contago_\w*_test$/.test(database.database) || owner.database !== database.database ||
      owner.host !== database.host || owner.port !== database.port) {
    throw new Error('La prueba requiere una base desechable contago_*_test');
  }
  return { owner, tls: database.tls };
}

test('HTTP sessions and tenant authorization against PostgreSQL', async (t) => {
  const { owner, tls } = verifyTarget();
  process.env.AUTH_ALLOWED_ORIGINS = ORIGIN;
  const db = client(owner, tls);
  await db.connect();
  t.after(async () => { await db.end(); });

  const suffix = randomUUID();
  const email = `l'alba-${suffix}@example.invalid`;
  const memberEmail = `member-${suffix}@example.invalid`;
  const saEmail = `sa-${suffix}@example.invalid`;
  const digest = await hash(PASSWORD);
  await db.query('INSERT INTO contago.usuarios(correo, hash_contrasena, es_sa) VALUES ($1,$2,true)', [saEmail, digest]);

  const app = await start();
  t.after(app.close);
  const request = app.request;
  async function expectStatus(path, status, options) {
    const result = await request(path, options);
    assert.equal(result.status, status, path);
    return result;
  }
  async function login(correo, contrasena = PASSWORD) {
    const response = await expectStatus('/auth/login', 200, { method: 'POST', body: { correo, contrasena } });
    assert.ok(response.cookie && response.setCookie?.includes('HttpOnly') && response.setCookie?.includes('SameSite=Strict'));
    assert.deepEqual(Object.keys(response.body).sort(), ['correo', 'es_sa', 'id']);
    return response;
  }

  await t.test('registration, duplicate, missing session, strict DTO and password storage', async () => {
    await expectStatus('/auth/me', 401);
    await expectStatus('/auth/register', 400, { method: 'POST', body: { correo: email, contrasena: PASSWORD, es_sa: true } });
    const input = { method: 'POST', body: { correo: email, contrasena: PASSWORD } };
    const result = await expectStatus('/auth/register', 201, input);
    assert.deepEqual(Object.keys(result.body).sort(), ['correo', 'id']);
    await expectStatus('/auth/register', 409, input);
    await expectStatus('/auth/register', 201, { method: 'POST', body: { correo: memberEmail, contrasena: PASSWORD } });
    const found = await db.query('SELECT hash_contrasena FROM contago.usuarios WHERE id=$1', [result.body.id]);
    assert.ok(found.rows[0]?.hash_contrasena.startsWith('$argon2id$'));
    await expectStatus('/auth/login', 401, { method: 'POST', body: { correo: email, contrasena: 'Incorrecta-21' } });
  });

  const admin = await login(email);
  const member = await login(memberEmail);
  const platform = await login(saEmail);
  let businessId;
  let secondId;
  await t.test('CSRF and CORS enforce explicit browser origin and header', async () => {
    await expectStatus('/auth/logout', 403, { method: 'POST', cookie: admin.cookie, csrf: false });
    await expectStatus('/auth/logout', 403, { method: 'POST', cookie: admin.cookie, origin: 'http://otro.invalid' });
    await expectStatus('/auth/logout', 403, { method: 'POST', cookie: admin.cookie, origin: '' });
    await expectStatus('/auth/me', 200, { cookie: admin.cookie });
    const preflight = await expectStatus('/auth/logout', 204, { method: 'OPTIONS',
      headers: { 'Access-Control-Request-Method': 'POST', 'Access-Control-Request-Headers': 'X-Contago-CSRF' } });
    assert.equal(preflight.headers.get('access-control-allow-origin'), ORIGIN);
    const forbidden = await expectStatus('/health', 200, { origin: 'http://otro.invalid' });
    assert.equal(forbidden.headers.get('access-control-allow-origin'), null);
  });

  await t.test('tenant isolation, rejected escalation and administrative boundaries', async () => {
    const literal = "Caja '; SELECT 1; --";
    const business = await expectStatus('/businesses', 201, { cookie: admin.cookie, method: 'POST', body: { nombre: literal } });
    businessId = business.body.id;
    const second = await expectStatus('/businesses', 201, { cookie: member.cookie, method: 'POST', body: { nombre: 'Segundo' } });
    secondId = second.body.id;
    const firstPath = '/businesses/' + businessId;
    const memberPath = firstPath + '/memberships/' + member.body.id;
    const own = await expectStatus(firstPath, 200, { cookie: admin.cookie });
    assert.equal(own.body.nombre, literal);
    await expectStatus(firstPath, 403, { cookie: member.cookie });
    await expectStatus('/businesses/' + secondId, 403, { cookie: admin.cookie });
    await expectStatus('/businesses/' + encodeURIComponent("' OR 1=1 --"), 400, { cookie: admin.cookie });
    await expectStatus(memberPath, 204, { method: 'PUT', cookie: admin.cookie, body: { rol: 'MIEMBRO', activa: true } });
    await expectStatus(firstPath, 200, { cookie: member.cookie });
    await expectStatus(memberPath, 403, { method: 'PUT', cookie: member.cookie, body: { rol: 'ADMINISTRADOR', activa: true } });
    await expectStatus(memberPath, 400, { method: 'PUT', cookie: admin.cookie, body: { rol: 'SA', activa: true } });
    await expectStatus(firstPath + '/memberships', 403, { cookie: member.cookie });
    await expectStatus(firstPath, 403, { method: 'PATCH', cookie: member.cookie, body: { nombre: 'Intento' } });
    await expectStatus(firstPath, 403, { cookie: platform.cookie });
    await expectStatus('/admin/users', 403, { cookie: member.cookie, headers: { 'X-Role': 'SA', 'X-User-Id': platform.body.id } });
    const directory = await expectStatus('/admin/users', 200, { cookie: platform.cookie });
    assert.ok(directory.body.every((item) => !Object.hasOwn(item, 'hash_contrasena')));
    await expectStatus('/admin/businesses/' + businessId + '/status', 204,
      { method: 'PATCH', cookie: platform.cookie, body: { habilitado: false } });
    await expectStatus(firstPath, 403, { cookie: admin.cookie });
    await expectStatus('/admin/businesses/' + businessId + '/status', 204,
      { method: 'PATCH', cookie: platform.cookie, body: { habilitado: true } });
    await expectStatus(firstPath, 200, { cookie: admin.cookie });
    await expectStatus(memberPath, 204, { method: 'PUT', cookie: admin.cookie, body: { rol: 'MIEMBRO', activa: false } });
    await expectStatus(firstPath, 403, { cookie: member.cookie });
  });

  await t.test('expiry, revocation, logout-all and atomic password rotation', async () => {
    const expiring = await login(email);
    const hashed = hashToken(expiring.cookie.split('=')[1]);
    const stored = await db.query('SELECT octet_length(token_hash) AS bytes FROM contago.sesiones WHERE token_hash=$1', [hashed]);
    assert.equal(stored.rows[0]?.bytes, 32);
    await db.query("UPDATE contago.sesiones SET creada_en=now()-interval '2 hours', expira_en=now()-interval '1 hour' WHERE token_hash=$1", [hashed]);
    await expectStatus('/auth/me', 401, { cookie: expiring.cookie });

    await expectStatus('/auth/logout', 204, { method: 'POST', cookie: admin.cookie });
    await expectStatus('/auth/me', 401, { cookie: admin.cookie });
    const a = await login(email);
    const b = await login(email);
    await expectStatus('/auth/logout-all', 204, { method: 'POST', cookie: a.cookie });
    await expectStatus('/auth/me', 401, { cookie: a.cookie });
    await expectStatus('/auth/me', 401, { cookie: b.cookie });

    const current = await login(email);
    const concurrent = await login(email);
    const invalid = { contrasenaActual: 'Incorrecta-21', contrasenaNueva: NEW_PASSWORD };
    await expectStatus('/auth/change-password', 401, { method: 'POST', cookie: current.cookie, body: invalid });
    const rotated = await expectStatus('/auth/change-password', 204, { method: 'POST', cookie: current.cookie,
      body: { contrasenaActual: PASSWORD, contrasenaNueva: NEW_PASSWORD } });
    assert.ok(rotated.cookie && rotated.cookie !== current.cookie);
    await expectStatus('/auth/me', 401, { cookie: current.cookie });
    await expectStatus('/auth/me', 401, { cookie: concurrent.cookie });
    await expectStatus('/auth/me', 200, { cookie: rotated.cookie });
    await expectStatus('/auth/login', 401, { method: 'POST', body: { correo: email, contrasena: PASSWORD } });
    await login(email, NEW_PASSWORD);
  });

  await t.test('disabled accounts cannot sign in and rehabilitation never restores the old cookie', async () => {
    const path = '/admin/users/' + member.body.id + '/status';
    await expectStatus(path, 204, { method: 'PATCH', cookie: platform.cookie, body: { habilitado: false } });
    await expectStatus('/auth/me', 401, { cookie: member.cookie });
    await expectStatus('/auth/login', 401, { method: 'POST', body: { correo: memberEmail, contrasena: PASSWORD } });
    await expectStatus(path, 204, { method: 'PATCH', cookie: platform.cookie, body: { habilitado: true } });
    await expectStatus('/auth/me', 401, { cookie: member.cookie });
    await login(memberEmail);
  });

  await t.test('concurrent logout-all and password rotation serialize on the account', async () => {
    const concurrentApp = await start();
    try {
      const session = await concurrentApp.request('/auth/login', { method: 'POST',
        body: { correo: email, contrasena: NEW_PASSWORD } });
      assert.equal(session.status, 200);
      const options = { method: 'POST', cookie: session.cookie };
      const [logout, rotation] = await Promise.all([
        concurrentApp.request('/auth/logout-all', options),
        concurrentApp.request('/auth/change-password', { ...options, body: {
          contrasenaActual: NEW_PASSWORD, contrasenaNueva: 'Ficticia-Fase21-Final',
        } }),
      ]);
      assert.deepEqual([logout.status, rotation.status].sort(), [204, 401]);
      assert.equal((await concurrentApp.request('/auth/me', { cookie: session.cookie })).status, 401);
      if (rotation.status === 204) {
        assert.ok(rotation.cookie);
        assert.equal((await concurrentApp.request('/auth/me', { cookie: rotation.cookie })).status, 200);
      }
    } finally { await concurrentApp.close(); }
  });

  await t.test('SQL grants protect session storage and financial movements even from SA', async () => {
    for (const name of ['DATABASE_URL', 'AUTH_DATABASE_URL', 'ADMIN_DATABASE_URL']) {
      const connection = client(parseDatabaseUrl(process.env[name], name), tls);
      await connection.connect();
      try {
        await assert.rejects(connection.query('SELECT * FROM contago.sesiones'), { code: '42501' });
        if (name === 'ADMIN_DATABASE_URL') {
          await assert.rejects(connection.query('SELECT * FROM contago.listar_movimientos($1::uuid,$2::uuid)',
            [platform.body.id, businessId]), { code: '42501' });
        }
      } finally { await connection.end(); }
    }
  });

  await t.test('rate limiting and public health endpoints', async () => {
    const limited = await start();
    try {
      for (let i = 0; i < 20; i += 1) {
        assert.equal((await limited.request('/auth/login', { method: 'POST', body: {} })).status, 400);
      }
      assert.equal((await limited.request('/auth/login', { method: 'POST', body: {} })).status, 429);
      assert.equal((await limited.request('/health')).status, 200);
      assert.equal((await limited.request('/health/ready')).status, 200);
    } finally { await limited.close(); }
  });
});
