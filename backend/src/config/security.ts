import { parseDatabaseUrl } from './environment';
import type { RuntimeConfig } from './environment';

export interface SecurityConfig {
  readonly production: boolean;
  readonly origins: readonly string[];
  readonly authDatabase?: RuntimeConfig['database'];
  readonly adminDatabase?: RuntimeConfig['database'];
}

export function validateSecurity(env: NodeJS.ProcessEnv, runtime: RuntimeConfig): SecurityConfig {
  const production = env.NODE_ENV === 'production';
  const configured = env.AUTH_ALLOWED_ORIGINS;
  const origins = configured === undefined
    ? (production ? [] : ['http://localhost:3000', 'http://127.0.0.1:3000'])
    : configured.split(',').map((origin) => origin.trim());

  for (const origin of origins) {
    try {
      const parsed = new URL(origin);
      if (parsed.origin !== origin || !['http:', 'https:'].includes(parsed.protocol) ||
          (production && parsed.protocol !== 'https:')) throw new Error();
    } catch {
      throw new Error('Configuración inválida: AUTH_ALLOWED_ORIGINS');
    }
  }

  function separateDatabase(name: 'AUTH_DATABASE_URL' | 'ADMIN_DATABASE_URL') {
    if (env[name] === undefined) return undefined;
    const connection = parseDatabaseUrl(env[name], name);
    const business = runtime.database;
    if (connection.user === business.user || connection.host !== business.host ||
        connection.port !== business.port || connection.database !== business.database) {
      throw new Error(`Configuración inválida: ${name}`);
    }
    return { ...connection, tls: business.tls, poolMax: business.poolMax };
  }

  const authDatabase = separateDatabase('AUTH_DATABASE_URL');
  const adminDatabase = separateDatabase('ADMIN_DATABASE_URL');
  if (authDatabase && origins.length === 0) throw new Error('Configuración inválida: AUTH_ALLOWED_ORIGINS');
  if (adminDatabase && (!authDatabase || adminDatabase.user === authDatabase.user)) {
    throw new Error('Configuración inválida: ADMIN_DATABASE_URL');
  }
  return { production, origins, authDatabase, adminDatabase };
}
