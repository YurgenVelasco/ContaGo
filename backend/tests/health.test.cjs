require('reflect-metadata');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { Module } = require('@nestjs/common');
const { NestFactory } = require('@nestjs/core');
const { DatabaseService } = require('../dist/database/database.service');
const { HealthController } = require('../dist/health/health.controller');

test('liveness stays up when readiness fails and the response is generic', async () => {
  let available = true;
  class HealthTestModule {}
  Module({
    controllers: [HealthController],
    providers: [{ provide: DatabaseService, useValue: { isReady: async () => available } }],
  })(HealthTestModule);

  const app = await NestFactory.create(HealthTestModule, { logger: false, abortOnError: false });
  try {
    await app.listen(0, '127.0.0.1');
    const base = await app.getUrl();
    const healthy = await fetch(base + '/health/ready');
    assert.equal(healthy.status, 200);
    assert.equal(healthy.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await healthy.json(), { status: 'ok' });

    available = false;
    const unavailable = await fetch(base + '/health/ready');
    assert.equal(unavailable.status, 503);
    assert.equal(unavailable.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await unavailable.json(), { status: 'unavailable' });

    const live = await fetch(base + '/health');
    assert.equal(live.status, 200);
    assert.deepEqual(await live.json(), { status: 'ok' });
  } finally {
    await app.close();
  }
});
