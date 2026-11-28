import { Injectable, UnauthorizedException } from '@nestjs/common';
import { Algorithm, hash, verify } from '@node-rs/argon2';
import { randomBytes } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import type { ChangePasswordDto, CredentialsDto } from './auth.dto';
import { newSessionToken } from './http-security';
import type { Identity, Session } from './http-security';

const HASH_OPTIONS = { algorithm: Algorithm.Argon2id, memoryCost: 19456, timeCost: 2, parallelism: 1 };

type Credential = Omit<Identity, 'correo'> & { hash_contrasena: string };

@Injectable()
export class AuthService {
  private dummyHash?: Promise<string>;

  constructor(private readonly db: DatabaseService) {}

  async register(input: CredentialsDto) {
    const digest = await hash(input.contrasena, HASH_OPTIONS);
    const [result] = await this.db.query<{id: string}>('contago_auth',
      'SELECT contago.registrar_usuario($1::text, $2::text) AS id', [input.correo, digest]);
    return { id: result?.id, correo: input.correo };
  }

  private async credential(email: string): Promise<Credential | undefined> {
    const [credential] = await this.db.query<Credential>('contago_auth',
      'SELECT * FROM contago.buscar_credencial($1::text)', [email]);
    return credential;
  }

  private async matches(credential: Credential | undefined, password: string): Promise<boolean> {
    if (credential?.hash_contrasena.startsWith('$argon2id$')) {
      try { return await verify(credential.hash_contrasena, password); } catch { /* Tratar hashes inválidos como ausencia. */ }
    }
    const dummy = await (this.dummyHash ??= hash(randomBytes(32), HASH_OPTIONS));
    await verify(dummy, password);
    return false;
  }

  async login(input: CredentialsDto) {
    const credential = await this.credential(input.correo);
    if (!(await this.matches(credential, input.contrasena)) || !credential) {
      throw new UnauthorizedException('Credenciales no válidas');
    }
    const { token, tokenHash } = newSessionToken();
    const [row] = await this.db.query<{expires: Date | null}>('contago_auth',
      'SELECT contago.auth_crear_sesion($1::uuid, $2::text, $3::bytea) AS expires',
      [credential.id, credential.hash_contrasena, tokenHash]);
    if (!row?.expires) throw new UnauthorizedException('Credenciales no válidas');
    return { token, expires: row.expires, identity: { id: credential.id, correo: input.correo, es_sa: credential.es_sa } };
  }

  async identity(tokenHash: Buffer): Promise<Identity | undefined> {
    const [identity] = await this.db.query<Identity>('contago_auth',
      'SELECT * FROM contago.auth_identidad($1::bytea)', [tokenHash]);
    return identity;
  }

  async revoke(session: Session, all: boolean): Promise<void> {
    const [row] = await this.db.query<{revoked: boolean}>('contago_auth',
      'SELECT contago.auth_revocar($1::bytea, $2::boolean) AS revoked', [session.tokenHash, all]);
    if (!row?.revoked) throw new UnauthorizedException('Sesión no válida');
  }

  async password(session: Session, input: ChangePasswordDto) {
    const credential = await this.credential(session.identity.correo);
    if (!(await this.matches(credential, input.contrasenaActual)) || !credential) {
      throw new UnauthorizedException('Credenciales no válidas');
    }
    const replacement = await hash(input.contrasenaNueva, HASH_OPTIONS);
    const { token, tokenHash } = newSessionToken();
    const [row] = await this.db.query<{expires: Date | null}>('contago_auth',
      'SELECT contago.auth_cambiar_contrasena($1::bytea, $2::text, $3::text, $4::bytea) AS expires',
      [session.tokenHash, credential.hash_contrasena, replacement, tokenHash]);
    if (!row?.expires) throw new UnauthorizedException('Sesión no válida');
    return { token, expires: row.expires };
  }
}
