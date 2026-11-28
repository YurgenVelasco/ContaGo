export interface RuntimeConfig {
  readonly host: string;
  readonly port: number;
  readonly database: {
    readonly host: string;
    readonly port: number;
    readonly user: string;
    readonly password: string;
    readonly database: string;
    readonly tls: boolean;
    readonly poolMax: number;
  };
}

function invalid(name: string): never {
  throw new Error(`Configuración inválida: ${name}`);
}

function integer(raw: string, name: string, min: number, max: number): number {
  const parsed = Number(raw);
  if (!/^\d+$/.test(raw) || !Number.isInteger(parsed) || parsed < min || parsed > max) {
    invalid(name);
  }
  return parsed;
}

function parseDatabaseUrl(raw: string | undefined) {
  try {
    const url = new URL(raw ?? '');
    if (
      !['postgres:', 'postgresql:'].includes(url.protocol) ||
      !url.hostname || /[%\s]/.test(url.hostname) ||
      !url.username || !url.password || !/^\/[^/]+$/.test(url.pathname) ||
      (raw && /[?#]/.test(raw))
    ) {
      invalid('DATABASE_URL');
    }

    const user = decodeURIComponent(url.username);
    const password = decodeURIComponent(url.password);
    const database = decodeURIComponent(url.pathname.slice(1));
    if ([user, password, database].some((value) => !value || value.includes('\0'))) {
      invalid('DATABASE_URL');
    }

    return {
      host: url.hostname.replace(/^\[|\]$/g, ''),
      port: integer(url.port || '5432', 'DATABASE_URL', 1, 65535),
      user,
      password,
      database,
    };
  } catch {
    return invalid('DATABASE_URL');
  }
}

export function validateEnvironment(env: NodeJS.ProcessEnv): RuntimeConfig {
  const mode = env.NODE_ENV ?? 'development';
  const host = env.HOST ?? '127.0.0.1';
  const tls = env.DATABASE_TLS ?? 'verify-full';

  if (!['development', 'test', 'production'].includes(mode)) invalid('NODE_ENV');
  if (host.trim() !== host || !host || /[\s/\\]/.test(host)) invalid('HOST');
  if (tls !== 'verify-full' && tls !== 'disable') invalid('DATABASE_TLS');
  if (mode === 'production' && tls !== 'verify-full') invalid('DATABASE_TLS');

  return {
    host,
    port: integer(env.PORT ?? '3000', 'PORT', 1, 65535),
    database: {
      ...parseDatabaseUrl(env.DATABASE_URL),
      tls: tls === 'verify-full',
      poolMax: integer(env.DATABASE_POOL_MAX ?? '5', 'DATABASE_POOL_MAX', 1, 30),
    },
  };
}
