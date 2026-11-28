import { HttpException, Inject, Injectable, Logger, Optional, ServiceUnavailableException } from '@nestjs/common';
import type { OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Pool } from 'pg';
import type { QueryResultRow } from 'pg';
import { RUNTIME_CONFIG, SECURITY_CONFIG } from '../config/config.module';
import type { RuntimeConfig } from '../config/environment';
import type { SecurityConfig } from '../config/security';
import { CHECK_RUNTIME_PRIVILEGES, PRIVILEGE_SIGNATURES } from './runtime-privileges';
import type { DatabaseRole } from './runtime-privileges';

@Injectable()
export class DatabaseService implements OnModuleInit, OnModuleDestroy {
  private readonly pools = new Map<DatabaseRole, Pool>();
  private readonly logger = new Logger(DatabaseService.name);
  private closing?: Promise<void>;

  constructor(
    @Inject(RUNTIME_CONFIG) config: RuntimeConfig,
    @Optional() @Inject(SECURITY_CONFIG) security?: SecurityConfig,
  ) {
    this.addPool('contago_app', config.database);
    if (security?.authDatabase) this.addPool('contago_auth', security.authDatabase);
    if (security?.adminDatabase) this.addPool('contago_sa', security.adminDatabase);
  }

  private addPool(role: DatabaseRole, settings: RuntimeConfig['database']): void {
    const { tls, poolMax, ...connection } = settings;
    const pool = new Pool({
      ...connection,
      ssl: tls ? { rejectUnauthorized: true } : false,
      max: poolMax,
      connectionTimeoutMillis: 3000,
      statement_timeout: 3000,
      query_timeout: 4000,
      idleTimeoutMillis: 10000,
      application_name: `contago_backend_${role}`,
      options: '-c search_path=pg_catalog -c default_transaction_isolation=read\\ committed',
    });
    pool.on('error', () => this.logger.warn('Se perdió una conexión inactiva con PostgreSQL'));
    this.pools.set(role, pool);
  }

  async onModuleInit(): Promise<void> {
    try {
      for (const [role, pool] of this.pools) {
        const result = await pool.query<{valid: boolean}>(
          CHECK_RUNTIME_PRIVILEGES, [role, PRIVILEGE_SIGNATURES[role]],
        ).catch(() => { throw new Error('Falló la comprobación de conexión o del contrato PostgreSQL'); });
        if (result.rows[0]?.valid !== true) {
          throw new Error('La cuenta PostgreSQL no cumple el contrato de permisos de ContaGo');
        }
      }
    } catch (error) {
      await this.onModuleDestroy();
      throw error;
    }
  }

  onModuleDestroy(): Promise<void> {
    return this.closing ??= Promise.all([...this.pools.values()].map((pool) => pool.end()))
      .then(() => undefined);
  }

  async query<Row extends QueryResultRow>(role: DatabaseRole, sql: string, parameters: unknown[]): Promise<Row[]> {
    const pool = this.pools.get(role);
    if (!pool) throw new ServiceUnavailableException('Servicio sin configurar');
    try {
      return (await pool.query<Row>(sql, parameters)).rows;
    } catch (error) {
      const code = (error as {code?: unknown}).code;
      switch (code) {
        case '42501': throw new HttpException('Acceso denegado', 403);
        case '23505': throw new HttpException('El recurso ya existe', 409);
        case '23503':
        case '23514':
        case '22023': throw new HttpException('Solicitud no válida', 400);
        default: throw new ServiceUnavailableException('Servicio temporalmente no disponible');
      }
    }
  }

  async isReady(): Promise<boolean> {
    try {
      const results = await Promise.all([...this.pools.values()].map((pool) => pool.query<{ready: boolean}>(
        `SELECT EXISTS (SELECT 1 FROM pg_namespace AS n
         WHERE n.nspname = 'contago' AND has_schema_privilege(n.oid, 'USAGE')) AS ready`,
      )));
      return results.every((result) => result.rows[0]?.ready === true);
    } catch {
      return false;
    }
  }
}
