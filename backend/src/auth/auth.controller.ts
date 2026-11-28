import { Body, Controller, Get, Header, HttpCode, Inject, Post, Res } from '@nestjs/common';
import type { ServerResponse } from 'node:http';
import { StrictBodyPipe } from '../common/body-validation';
import { SECURITY_CONFIG } from '../config/config.module';
import type { SecurityConfig } from '../config/security';
import { credentials, changePassword } from './auth.dto';
import type { CredentialsDto, ChangePasswordDto } from './auth.dto';
import { AuthService } from './auth.service';
import { PublicRoute, SensitiveRoute, sessionCookie } from './http-security';
import type { Session } from './http-security';
import { CurrentSession, RequireSession } from './session.guard';

@RequireSession()
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService, @Inject(SECURITY_CONFIG) private readonly config: SecurityConfig) {}

  @PublicRoute()
  @SensitiveRoute()
  @Post('register')
  @Header('Cache-Control', 'no-store')
  register(@Body(new StrictBodyPipe((body) => credentials(body, true))) input: CredentialsDto) {
    return this.auth.register(input);
  }

  @PublicRoute()
  @SensitiveRoute()
  @Post('login')
  @HttpCode(200)
  @Header('Cache-Control', 'no-store')
  async login(@Body(new StrictBodyPipe(credentials)) input: CredentialsDto, @Res({ passthrough: true }) response: ServerResponse) {
    const result = await this.auth.login(input);
    response.setHeader('Set-Cookie', sessionCookie(this.config.production, result.token, result.expires));
    return result.identity;
  }

  @Get('me')
  @Header('Cache-Control', 'no-store')
  me(@CurrentSession() session: Session) {
    return session.identity;
  }

  @Post('logout')
  @HttpCode(204)
  @Header('Cache-Control', 'no-store')
  async logout(@CurrentSession() session: Session, @Res({ passthrough: true }) response: ServerResponse) {
    await this.auth.revoke(session, false);
    response.setHeader('Set-Cookie', sessionCookie(this.config.production));
  }

  @Post('logout-all')
  @HttpCode(204)
  @Header('Cache-Control', 'no-store')
  async logoutAll(@CurrentSession() session: Session, @Res({ passthrough: true }) response: ServerResponse) {
    await this.auth.revoke(session, true);
    response.setHeader('Set-Cookie', sessionCookie(this.config.production));
  }

  @SensitiveRoute()
  @Post('change-password')
  @HttpCode(204)
  @Header('Cache-Control', 'no-store')
  async changePassword(
    @CurrentSession() session: Session,
    @Body(new StrictBodyPipe(changePassword)) input: ChangePasswordDto,
    @Res({ passthrough: true }) response: ServerResponse,
  ) {
    const result = await this.auth.password(session, input);
    response.setHeader('Set-Cookie', sessionCookie(this.config.production, result.token, result.expires));
  }
}
