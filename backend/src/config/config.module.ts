import { Module } from '@nestjs/common';
import { validateEnvironment } from './environment';

export const RUNTIME_CONFIG = Symbol('RUNTIME_CONFIG');

@Module({
  providers: [{ provide: RUNTIME_CONFIG, useFactory: () => validateEnvironment(process.env) }],
  exports: [RUNTIME_CONFIG],
})
export class ConfigModule {}
