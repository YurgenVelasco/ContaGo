import { applyDecorators, BadRequestException, createParamDecorator, ForbiddenException, Injectable, ParseUUIDPipe, SetMetadata, UseGuards } from '@nestjs/common';
import type { CanActivate, ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { requireSession } from '../auth/session.guard';
import type { SecurityRequest } from '../auth/http-security';
import { DatabaseService } from '../database/database.service';

export type BusinessRole = 'ADMINISTRADOR' | 'MIEMBRO';
export interface BusinessContext {
  id: string;
  nombre: string;
  habilitado: boolean;
  rol: BusinessRole;
}

type BusinessRequest = SecurityRequest & { business?: BusinessContext };
const BUSINESS_ROLES = Symbol('BUSINESS_ROLES');

@Injectable()
export class BusinessAccess {
  constructor(private readonly db: DatabaseService) {}

  list(actor: string): Promise<BusinessContext[]> {
    return this.db.query<BusinessContext>('contago_app',
      'SELECT * FROM contago.listar_negocios($1::uuid)', [actor]);
  }

  async require(actor: string, business: string, roles: readonly BusinessRole[]): Promise<BusinessContext> {
    const [row] = await this.db.query<BusinessContext>('contago_app',
      'SELECT * FROM contago.listar_negocios($1::uuid) WHERE id = $2::uuid', [actor, business]);
    if (!row?.habilitado || !roles.includes(row.rol)) throw new ForbiddenException('Acceso denegado');
    return row;
  }
}

@Injectable()
export class BusinessGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, private readonly access: BusinessAccess) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const { identity } = requireSession(context);
    const request = context.switchToHttp().getRequest<BusinessRequest>();
    const roles = this.reflector.get<readonly BusinessRole[]>(BUSINESS_ROLES, context.getHandler());
    if (identity.es_sa || !roles?.length) throw new ForbiddenException('Acceso denegado');
    const target = request.params?.businessId;
    if (!target) throw new BadRequestException('Negocio no válido');
    const id = await new ParseUUIDPipe().transform(target, { type: 'param' });
    request.business = await this.access.require(identity.id, id, roles);
    return true;
  }
}

export const RequireBusinessRoles = (...roles: BusinessRole[]) =>
  applyDecorators(SetMetadata(BUSINESS_ROLES, roles), UseGuards(BusinessGuard));

export const CurrentBusiness = createParamDecorator((_data: unknown, context: ExecutionContext) => {
  const { business } = context.switchToHttp().getRequest<BusinessRequest>();
  if (!business) throw new ForbiddenException('Acceso denegado');
  return business;
});
