require('reflect-metadata');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { test } = require('node:test');
const { NestFactory } = require('@nestjs/core');
const { Client } = require('pg');
const { AppModule } = require('../dist/app.module');
const { validateEnvironment } = require('../dist/config/environment');
const { DatabaseService } = require('../dist/database/database.service');
const { CHECK_RUNTIME_PRIVILEGES, PRIVILEGE_SIGNATURES } = require('../dist/database/runtime-privileges');

test('real PostgreSQL serves readiness and prevents financial DML and administrative access', async () => {
  if (process.env.NODE_ENV !== 'test') {
    throw new Error('Use NODE_ENV=test y una base desechable aprovisionada para estas pruebas');
  }

  const config = validateEnvironment(process.env);
  const app = await NestFactory.create(AppModule, { logger: false, abortOnError: false });
  try {
    await app.listen(0, '127.0.0.1');
    const response = await fetch((await app.getUrl()) + '/health/ready');
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  } finally {
    await app.close();
  }

  const { tls, poolMax: _poolMax, ...connection } = config.database;
  const client = new Client({
    ...connection,
    ssl: tls ? { rejectUnauthorized: true } : false,
    connectionTimeoutMillis: 3000,
    statement_timeout: 3000,
  });
  await client.connect();
  try {
    const { rows } = await client.query(CHECK_RUNTIME_PRIVILEGES, ['contago_app', PRIVILEGE_SIGNATURES.contago_app]);
    assert.equal(rows[0]?.valid, true);
    const probe = randomUUID();
    await assert.rejects(client.query(
      'SELECT * FROM contago.listar_negocios($1::uuid)', [probe],
    ), { code: '42501', message: 'Usuario sin acceso' });

    for (const [sql, parameters] of [
      ['INSERT INTO contago.operaciones_financieras DEFAULT VALUES', []],
      ['UPDATE contago.apuntes_cuenta SET variacion = 1 WHERE false', []],
      ['DELETE FROM contago.aplicaciones_pago WHERE false', []],
      ['SELECT * FROM contago.buscar_credencial($1::text)', ['test@example.invalid']],
      ['SELECT * FROM contago.sa_listar_usuarios($1::uuid)', [probe]],
      ['SET ROLE contago_sa', []],
    ]) {
      await client.query('BEGIN');
      try {
        await assert.rejects(client.query(sql, parameters), { code: '42501' });
      } finally {
        await client.query('ROLLBACK');
      }
    }
  } finally {
    await client.end();
  }
});

test('startup refuses an overprivileged PostgreSQL login when supplied for the disposable database', {
  skip: !process.env.TEST_PRIVILEGED_DATABASE_URL,
}, async () => {
  assert.equal(process.env.NODE_ENV, 'test');
  const config = validateEnvironment({
    ...process.env, DATABASE_URL: process.env.TEST_PRIVILEGED_DATABASE_URL,
  });
  const database = new DatabaseService(config);
  await assert.rejects(database.onModuleInit(), {
    message: 'La cuenta PostgreSQL no cumple el contrato de permisos de ContaGo',
  });
});
