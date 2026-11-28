import { BadRequestException } from '@nestjs/common';
import type { PipeTransform } from '@nestjs/common';

export class StrictBodyPipe<T> implements PipeTransform<unknown, T> {
  constructor(private readonly parse: (value: unknown) => T) {}

  transform(value: unknown): T {
    return this.parse(value);
  }
}

export function invalidBody(): never {
  throw new BadRequestException('Cuerpo de solicitud no válido');
}

export function strictObject(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) return invalidBody();
  const source = value as Record<string, unknown>;
  if (Object.keys(source).length !== keys.length || keys.some((key) => !Object.hasOwn(source, key))) {
    return invalidBody();
  }
  return source;
}

export function parseEnabled(value: unknown): { habilitado: boolean } {
  const { habilitado } = strictObject(value, ['habilitado']);
  if (typeof habilitado !== 'boolean') return invalidBody();
  return { habilitado };
}
