import { Body, Controller, ForbiddenException, Get, Header, HttpCode, Injectable, Param, ParseUUIDPipe, Patch, UseGuards } from '@nestjs/common';
import type { CanActivate, ExecutionContext } from '@nestjs/common';
import type { Session } from '../auth/http-security';
import { CurrentSession, RequireSession, requireSession } from '../auth/session.guard';
import { parseEnabled, StrictBodyPipe } from '../common/body-validation';
import { DatabaseService } from '../database/database.service';

@Injectable()
export class PlatformAdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    if (!requireSession(context).identity.es_sa) throw new ForbiddenException('Acceso denegado');
    return true;
  }
}

@RequireSession()
@Controller('admin')
@UseGuards(PlatformAdminGuard)
export class AdminController {
  constructor(private readonly db: DatabaseService) {}

  @Get('users')
  @Header('Cache-Control', 'no-store')
  list(@CurrentSession() { identity }: Session) {
    return this.db.query('contago_sa', 'SELECT * FROM contago.sa_listar_usuarios($1::uuid)', [identity.id]);
  }

  @Patch('users/:userId/status')
  @HttpCode(204)
  async userStatus(
    @CurrentSession() { identity }: Session, @Param('userId', ParseUUIDPipe) user: string,
    @Body(new StrictBodyPipe(parseEnabled)) {habilitado}: {habilitado: boolean},
  ) {
    await this.db.query('contago_sa', 'SELECT contago.sa_estado_usuario($1::uuid, $2::uuid, $3::boolean)',
      [identity.id, user, habilitado]);
  }

  @Patch('businesses/:businessId/status')
  @HttpCode(204)
  async businessStatus(
    @CurrentSession() { identity }: Session, @Param('businessId', ParseUUIDPipe) business: string,
    @Body(new StrictBodyPipe(parseEnabled)) {habilitado}: {habilitado: boolean},
  ) {
    await this.db.query('contago_sa', 'SELECT contago.sa_estado_negocio($1::uuid, $2::uuid, $3::boolean)',
      [identity.id, business, habilitado]);
  }
}
