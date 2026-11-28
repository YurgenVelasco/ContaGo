import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { RUNTIME_CONFIG } from './config/config.module';
import type { RuntimeConfig } from './config/environment';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { abortOnError: false });
  const { host, port } = app.get<RuntimeConfig>(RUNTIME_CONFIG);
  app.enableShutdownHooks();
  await app.init();
  try {
    await app.listen(port, host);
  } catch {
    await app.close();
    throw new Error('No se pudo abrir el servidor HTTP');
  }
}

void bootstrap().catch((error: unknown) => {
  Logger.error(error instanceof Error ? error.message : 'Falló el inicio', 'Bootstrap');
  process.exitCode = 1;
});
