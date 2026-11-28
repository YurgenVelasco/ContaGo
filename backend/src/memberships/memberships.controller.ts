import { Body, Controller, Get, Header, HttpCode, Param, ParseUUIDPipe, Put } from '@nestjs/common';
import type { Session } from '../auth/http-security';
import { CurrentSession, RequireSession } from '../auth/session.guard';
import { CurrentBusiness, RequireBusinessRoles } from '../businesses/business-access';
import type { BusinessContext, BusinessRole } from '../businesses/business-access';
import { invalidBody, strictObject, StrictBodyPipe } from '../common/body-validation';
import { DatabaseService } from '../database/database.service';

interface MembershipInput { rol: BusinessRole; activa: boolean }

function parseMembership(value: unknown): MembershipInput {
  const { rol, activa } = strictObject(value, ['rol', 'activa']);
  if ((rol !== 'ADMINISTRADOR' && rol !== 'MIEMBRO') || typeof activa !== 'boolean') return invalidBody();
  return { rol, activa };
}

@RequireSession()
@Controller('businesses/:businessId/memberships')
export class MembershipsController {
  constructor(private readonly db: DatabaseService) {}

  @Get()
  @RequireBusinessRoles('ADMINISTRADOR')
  @Header('Cache-Control', 'no-store')
  list(@CurrentSession() {identity}: Session, @CurrentBusiness() business: BusinessContext) {
    return this.db.query('contago_app',
      'SELECT * FROM contago.listar_membresias($1::uuid, $2::uuid)', [identity.id, business.id]);
  }

  @Put(':userId')
  @RequireBusinessRoles('ADMINISTRADOR')
  @HttpCode(204)
  async upsert(
    @CurrentSession() {identity}: Session, @CurrentBusiness() business: BusinessContext,
    @Param('userId', ParseUUIDPipe) user: string, @Body(new StrictBodyPipe(parseMembership)) input: MembershipInput,
  ) {
    await this.db.query('contago_app',
      'SELECT contago.gestionar_membresia($1::uuid, $2::uuid, $3::uuid, $4::contago.rol_negocio, $5::boolean)',
      [identity.id, business.id, user, input.rol, input.activa]);
  }
}
