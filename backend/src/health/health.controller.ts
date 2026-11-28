import { Controller, Get, Header, ServiceUnavailableException } from '@nestjs/common';
import { PublicRoute } from '../auth/http-security';
import { DatabaseService } from '../database/database.service';

@PublicRoute()
@Controller('health')
export class HealthController {
  constructor(private readonly database: DatabaseService) {}

  @Get()
  @Header('Cache-Control', 'no-store')
  live() {
    return { status: 'ok' };
  }

  @Get('ready')
  @Header('Cache-Control', 'no-store')
  async ready() {
    if (!(await this.database.isReady())) {
      throw new ServiceUnavailableException({ status: 'unavailable' });
    }
    return { status: 'ok' };
  }
}
