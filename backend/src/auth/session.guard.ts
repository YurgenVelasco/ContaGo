import { createParamDecorator, Inject, Injectable, ForbiddenException, SetMetadata, UnauthorizedException } from '@nestjs/common';
import type { CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { SECURITY_CONFIG } from '../config/config.module';
import type { SecurityConfig } from '../config/security';
import { AuthService } from './auth.service';
import { PUBLIC_ROUTE, readSessionHash } from './http-security';
import type { SecurityRequest, Session } from './http-security';

export const SESSION_ROUTE = Symbol('SESSION_ROUTE');
export const RequireSession = () => SetMetadata(SESSION_ROUTE, true);

export function requireSession(context: ExecutionContext): Session {
  const { session } = context.switchToHttp().getRequest<SecurityRequest>();
  if (!session) throw new UnauthorizedException('Sesión no válida');
  return session;
}

export const CurrentSession = createParamDecorator((_data: unknown, context: ExecutionContext) => requireSession(context));

@Injectable()
export class SessionGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly auth: AuthService,
    @Inject(SECURITY_CONFIG) private readonly config: SecurityConfig,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(PUBLIC_ROUTE, targets)) return true;
    if (!this.reflector.getAllAndOverride<boolean>(SESSION_ROUTE, targets)) {
      throw new ForbiddenException('Acceso denegado');
    }
    const request = context.switchToHttp().getRequest<SecurityRequest>();
    const tokenHash = readSessionHash(request.headers, this.config.production);
    if (!tokenHash) throw new UnauthorizedException('Sesión no válida');
    const identity = await this.auth.identity(tokenHash);
    if (!identity) throw new UnauthorizedException('Sesión no válida');
    request.session = { identity, tokenHash };
    return true;
  }
}
