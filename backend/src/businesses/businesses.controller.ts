import { Body, Controller, ForbiddenException, Get, Header, HttpCode, Patch, Post } from '@nestjs/common';
import { CurrentSession, RequireSession } from '../auth/session.guard';
import type { Session } from '../auth/http-security';
import { StrictBodyPipe, invalidBody, strictObject } from '../common/body-validation';
import { DatabaseService } from '../database/database.service';
import { BusinessAccess, CurrentBusiness, RequireBusinessRoles } from './business-access';
import type { BusinessContext } from './business-access';

function parseName(value: unknown): { nombre: string } {
  const { nombre } = strictObject(value, ['nombre']);
  if (typeof nombre !== 'string' || !nombre.trim() || nombre.length > 120 || nombre.includes('\0')) return invalidBody();
  return { nombre: nombre.trim() };
}

@RequireSession()
@Controller('businesses')
export class BusinessesController {
  constructor(private readonly db: DatabaseService, private readonly access: BusinessAccess) {}

  @Get()
  @Header('Cache-Control', 'no-store')
  list(@CurrentSession() { identity }: Session) {
    if (identity.es_sa) throw new ForbiddenException('Acceso denegado');
    return this.access.list(identity.id);
  }

  @Post()
  @Header('Cache-Control', 'no-store')
  async create(@CurrentSession() { identity }: Session, @Body(new StrictBodyPipe(parseName)) { nombre }: {nombre: string}) {
    if (identity.es_sa) throw new ForbiddenException('Acceso denegado');
    const [result] = await this.db.query<{id: string}>('contago_app',
      'SELECT contago.crear_negocio($1::uuid, $2::text) AS id', [identity.id, nombre]);
    return { id: result?.id };
  }

  @Get(':businessId')
  @RequireBusinessRoles('ADMINISTRADOR', 'MIEMBRO')
  @Header('Cache-Control', 'no-store')
  detail(@CurrentBusiness() business: BusinessContext) {
    return business;
  }

  @Patch(':businessId')
  @RequireBusinessRoles('ADMINISTRADOR')
  @HttpCode(204)
  async rename(
    @CurrentSession() { identity }: Session, @CurrentBusiness() business: BusinessContext,
    @Body(new StrictBodyPipe(parseName)) { nombre }: {nombre: string},
  ) {
    await this.db.query('contago_app', 'SELECT contago.renombrar_negocio($1::uuid, $2::uuid, $3::text)',
      [identity.id, business.id, nombre]);
  }
}
