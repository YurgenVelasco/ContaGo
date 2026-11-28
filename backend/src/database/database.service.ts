import { Inject, Injectable, Logger } from '@nestjs/common';
import type { OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Pool } from 'pg';
import { RUNTIME_CONFIG } from '../config/config.module';
import type { RuntimeConfig } from '../config/environment';
import { CHECK_RUNTIME_PRIVILEGES } from './runtime-privileges';

@Injectable()
export class DatabaseService implements OnModuleInit, OnModuleDestroy {
  private readonly pool: Pool;
  private readonly logger = new Logger(DatabaseService.name);

  constructor(@Inject(RUNTIME_CONFIG) config: RuntimeConfig) {
    const { tls, poolMax, ...connection } = config.database;
    this.pool = new Pool({
      ...connection,
      ssl: tls ? { rejectUnauthorized: true } : false,
      max: poolMax,
      connectionTimeoutMillis: 3000,
      statement_timeout: 3000,
      query_timeout: 4000,
      idleTimeoutMillis: 10000,
      application_name: 'contago_backend',
      options: '-c search_path=pg_catalog -c default_transaction_isolation=read\\ committed',
    });
    this.pool.on('error', () => this.logger.warn('Se perdió una conexión inactiva con PostgreSQL'));
  }

  async onModuleInit(): Promise<void> {
    let valid: boolean;
    try {
      const result = await this.pool.query<{ valid: boolean }>(CHECK_RUNTIME_PRIVILEGES);
      valid = result.rows[0]?.valid === true;
    } catch {
      await this.pool.end();
      throw new Error('Falló la comprobación de conexión o del contrato PostgreSQL');
    }
    if (!valid) {
      await this.pool.end();
      throw new Error('La cuenta PostgreSQL no cumple el contrato de permisos de ContaGo');
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }

  async isReady(): Promise<boolean> {
    try {
      const result = await this.pool.query<{ ready: boolean }>(
        `SELECT EXISTS (SELECT 1 FROM pg_namespace AS n
         WHERE n.nspname = 'contago' AND has_schema_privilege(n.oid, 'USAGE')) AS ready`,
      );
      return result.rows[0]?.ready === true;
    } catch {
      return false;
    }
  }
}
