import { invalidBody, strictObject } from '../common/body-validation';

export interface CredentialsDto {
  correo: string;
  contrasena: string;
}

export interface ChangePasswordDto {
  contrasenaActual: string;
  contrasenaNueva: string;
}

function password(value: unknown, minimum: number): string {
  if (typeof value !== 'string' || value.includes('\0') || Buffer.byteLength(value) > 512 ||
      [...value].length < minimum || !value.trim() || !value.isWellFormed()) return invalidBody();
  return value;
}

export function credentials(value: unknown, registration = false): CredentialsDto {
  const { correo, contrasena } = strictObject(value, ['correo', 'contrasena']);
  if (typeof correo !== 'string' || correo.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo.trim()) ||
      !/^[\x21-\x7e]+$/.test(correo.trim())) return invalidBody();
  return { correo: correo.trim().toLowerCase(), contrasena: password(contrasena, registration ? 12 : 1) };
}

export function changePassword(value: unknown): ChangePasswordDto {
  const { contrasenaActual, contrasenaNueva } = strictObject(value, ['contrasenaActual', 'contrasenaNueva']);
  const actual = password(contrasenaActual, 1);
  const nueva = password(contrasenaNueva, 12);
  if (actual === nueva) return invalidBody();
  return { contrasenaActual: actual, contrasenaNueva: nueva };
}
