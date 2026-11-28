import { Module } from '@nestjs/common';
import { validateEnvironment } from './environment';
import type { RuntimeConfig } from './environment';
import { validateSecurity } from './security';

export const RUNTIME_CONFIG = Symbol('RUNTIME_CONFIG');
export const SECURITY_CONFIG = Symbol('SECURITY_CONFIG');

@Module({
  providers: [
    { provide: RUNTIME_CONFIG, useFactory: () => validateEnvironment(process.env) },
    {
      provide: SECURITY_CONFIG,
      inject: [RUNTIME_CONFIG],
      useFactory: (runtime: RuntimeConfig) => validateSecurity(process.env, runtime),
    },
  ],
  exports: [RUNTIME_CONFIG, SECURITY_CONFIG],
})
export class ConfigModule {}
