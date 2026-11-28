const assert = require('node:assert/strict');
const { test } = require('node:test');
const { validateEnvironment } = require('../dist/config/environment');

const env = {
  DATABASE_URL: 'postgresql://app:p%40ss@[::1]:5440/contago_test',
  DATABASE_TLS: 'disable',
  NODE_ENV: 'test',
};

test('validates defaults and decodes the database URL', () => {
  assert.deepEqual(validateEnvironment(env), {
    host: '127.0.0.1',
    port: 3000,
    database: {
      host: '::1', port: 5440, user: 'app', password: 'p@ss',
      database: 'contago_test', tls: false, poolMax: 5,
    },
  });
});

test('rejects missing and malformed database settings without exposing secrets', () => {
  for (const url of [
    undefined, 'postgresql://app:synthetic_secret@localhost/',
    'postgresql://app:synthetic_secret@localhost/test?sslmode=disable',
    'postgresql://app:%ZZ@localhost/test',
    'https://app:synthetic_secret@localhost/test',
    'postgresql://app@localhost/test',
  ]) {
    assert.throws(
      () => validateEnvironment({ ...env, DATABASE_URL: url }),
      { message: 'Configuración inválida: DATABASE_URL' },
    );
  }
});

test('enforces integer bounds, valid modes, and TLS in production', () => {
  for (const settings of [
    { PORT: '0' }, { PORT: '1e3' }, { DATABASE_POOL_MAX: '31' },
    { NODE_ENV: 'staging' }, { NODE_ENV: 'production' }, { DATABASE_TLS: 'prefer' },
    { HOST: 'invalid host' },
  ]) {
    assert.throws(() => validateEnvironment({ ...env, ...settings }), /^Error: Configuración inválida:/);
  }
  assert.equal(validateEnvironment({
    ...env, NODE_ENV: 'production', DATABASE_TLS: undefined,
  }).database.tls, true);
});
