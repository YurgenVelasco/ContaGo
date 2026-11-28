import { createHash, randomBytes } from 'node:crypto';
import { ForbiddenException, Inject, Injectable, HttpException, SetMetadata } from '@nestjs/common';
import type { CanActivate, ExecutionContext, INestApplication } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { IncomingHttpHeaders } from 'node:http';
import { SECURITY_CONFIG } from '../config/config.module';
import type { SecurityConfig } from '../config/security';

export interface Identity {
  id: string;
  correo: string;
  es_sa: boolean;
}

export interface Session {
  identity: Identity;
  tokenHash: Buffer;
}

export interface SecurityRequest {
  headers: IncomingHttpHeaders;
  method: string;
  socket: { remoteAddress?: string };
  params?: { businessId?: string };
  session?: Session;
}

export const PUBLIC_ROUTE = Symbol('PUBLIC_ROUTE');
export const SENSITIVE_ROUTE = Symbol('SENSITIVE_ROUTE');
export const PublicRoute = () => SetMetadata(PUBLIC_ROUTE, true);
export const SensitiveRoute = () => SetMetadata(SENSITIVE_ROUTE, true);
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS']);

export function sessionCookieName(production: boolean): string {
  return production ? '__Host-contago_session' : 'contago_session';
}

export function hashToken(token: string): Buffer {
  return createHash('sha256').update(token).digest();
}

export function newSessionToken() {
  const token = randomBytes(32).toString('base64url');
  return { token, tokenHash: hashToken(token) };
}

export function readSessionHash(headers: IncomingHttpHeaders, production: boolean): Buffer | undefined {
  const name = sessionCookieName(production) + '=';
  const matches = headers.cookie?.split(';').map((part) => part.trim()).filter((part) => part.startsWith(name));
  if (matches?.length !== 1) return undefined;
  const token = matches[0]?.slice(name.length) ?? '';
  return /^[A-Za-z0-9_-]{43}$/.test(token) ? hashToken(token) : undefined;
}

export function sessionCookie(production: boolean, token?: string, expiry?: Date): string {
  const expiration = expiry ?? new Date(0);
  return `${sessionCookieName(production)}=${token ?? ''}; Path=/; HttpOnly; SameSite=Strict; Expires=${expiration.toUTCString()}${production ? '; Secure' : ''}`;
}

export function configureHttp(app: INestApplication): void {
  const { origins } = app.get<SecurityConfig>(SECURITY_CONFIG);
  app.enableCors({
    origin: [...origins],
    credentials: true,
    methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'X-Contago-CSRF'],
  });
}

@Injectable()
export class CsrfGuard implements CanActivate {
  constructor(@Inject(SECURITY_CONFIG) private readonly config: SecurityConfig) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest<SecurityRequest>();
    if (SAFE_METHODS.has(request.method)) return true;
    if (!request.headers.origin || !this.config.origins.includes(request.headers.origin) ||
        request.headers['x-contago-csrf'] !== '1') {
      throw new ForbiddenException('Solicitud de origen no autorizado');
    }
    return true;
  }
}

@Injectable()
export class SensitiveRateGuard implements CanActivate {
  private readonly hits = new Map<string, number>();
  private resetsAt = 0;
  private total = 0;

  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    if (!this.reflector.get<boolean>(SENSITIVE_ROUTE, context.getHandler())) return true;
    const request = context.switchToHttp().getRequest<SecurityRequest>();
    // Usar la dirección TCP. Las cabeceras de proxy no son una identidad confiable.
    const ip = request.socket.remoteAddress ?? 'unknown';
    const now = Date.now();
    if (now >= this.resetsAt) {
      this.hits.clear();
      this.total = 0;
      this.resetsAt = now + 60_000;
    }
    const count = this.hits.get(ip) ?? 0;
    if (count >= 20 || this.total >= 120) {
      throw new HttpException('Demasiadas solicitudes', 429);
    }
    this.hits.set(ip, count + 1);
    this.total += 1;
    return true;
  }
}
