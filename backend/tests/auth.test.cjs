const assert = require('node:assert/strict');
const { test } = require('node:test');
const { credentials, changePassword } = require('../dist/auth/auth.dto');
const { newSessionToken, readSessionHash, sessionCookie } = require('../dist/auth/http-security');
const { validateEnvironment } = require('../dist/config/environment');
const { validateSecurity } = require('../dist/config/security');

test('credentials normalize email and reject additional identity and malformed password fields', () => {
  assert.deepEqual(credentials({ correo: "  L'ALBA@EXAMPLE.INVALID  ", contrasena: 'Clave-Larga-123!' }, true),
    { correo: "l'alba@example.invalid", contrasena: 'Clave-Larga-123!' });
  for (const body of [
    { correo: 'person@example.invalid', contrasena: 'Clave-Larga-123!', rol: 'SA' },
    { correo: 'person@example.invalid', contrasena: 'corta' },
    { correo: 'person@example.invalid', contrasena: '🙂'.repeat(129) },
    { correo: 'person@example.invalid', contrasena: 'invalida\uD800-superior' },
    { correo: 'invalid', contrasena: 'Clave-Larga-123!' },
  ]) assert.throws(() => credentials(body, true), { message: 'Cuerpo de solicitud no válido' });
  assert.throws(() => changePassword({ contrasenaActual: 'Clave-Larga-123!', contrasenaNueva: 'Clave-Larga-123!' }));
});

test('session cookie hashes opaque tokens, rejects duplicates and has production flags', () => {
  const { token, tokenHash } = newSessionToken();
  const cookie = sessionCookie(true, token, new Date('2030-01-01'));
  const pair = cookie.split(';')[0];
  assert.ok(cookie.startsWith('__Host-contago_session='));
  for (const flag of ['Secure', 'HttpOnly', 'SameSite=Strict', 'Path=/']) assert.ok(cookie.includes(flag));
  assert.ok(readSessionHash({ cookie: pair }, true)?.equals(tokenHash));
  assert.equal(readSessionHash({ cookie: pair + '; ' + pair }, true), undefined);
  assert.equal(readSessionHash({ cookie: 'contago_session=short' }, false), undefined);
  assert.ok(!newSessionToken().tokenHash.equals(tokenHash));
});

test('auth configuration has separate identities and explicit HTTPS origins in production', () => {
  const url = 'postgresql://app:fixture@localhost/contago_test';
  const auth = 'postgresql://auth:fixture@localhost/contago_test';
  const admin = 'postgresql://sa:fixture@localhost/contago_test';
  const env = { NODE_ENV: 'production', DATABASE_URL: url };
  const runtime = validateEnvironment(env);
  assert.throws(() => validateSecurity({ ...env, AUTH_DATABASE_URL: auth }, runtime), /AUTH_ALLOWED_ORIGINS/);
  for (const origin of ['*', 'null', 'http://example.invalid', 'https://example.invalid/path']) {
    assert.throws(() => validateSecurity({ ...env, AUTH_DATABASE_URL: auth, AUTH_ALLOWED_ORIGINS: origin }, runtime),
      /AUTH_ALLOWED_ORIGINS/);
  }
  const origin = { ...env, AUTH_ALLOWED_ORIGINS: 'https://example.invalid' };
  assert.throws(() => validateSecurity({ ...origin, AUTH_DATABASE_URL: url }, runtime), /AUTH_DATABASE_URL/);
  assert.throws(() => validateSecurity({ ...origin, ADMIN_DATABASE_URL: admin }, runtime), /ADMIN_DATABASE_URL/);
  assert.equal(validateSecurity({ ...origin, AUTH_DATABASE_URL: auth, ADMIN_DATABASE_URL: admin }, runtime).production, true);
});

test('the session guard denies a route without an explicit policy', async () => {
  const { Reflector } = require('@nestjs/core');
  const { SessionGuard } = require('../dist/auth/session.guard');
  const guard = new SessionGuard(new Reflector(), {}, { production: false });
  const context = { getHandler: () => () => {}, getClass: () => class Unprotected {} };
  await assert.rejects(guard.canActivate(context), { message: 'Acceso denegado' });
});
