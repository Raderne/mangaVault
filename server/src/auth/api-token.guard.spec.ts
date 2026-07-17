import { UnauthorizedException } from '@nestjs/common';
import type { ExecutionContext } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';

import { ApiTokenGuard } from './api-token.guard';

function contextWithAuth(authorization?: string): ExecutionContext {
  return {
    getHandler: () => ({}),
    getClass: () => ({}),
    switchToHttp: () => ({
      getRequest: () => ({ headers: { authorization } }),
    }),
  } as unknown as ExecutionContext;
}

describe('ApiTokenGuard', () => {
  const config = { get: () => 'secret-token' } as unknown as ConfigService;

  function guardWithPublic(isPublic: boolean) {
    const reflector = {
      getAllAndOverride: () => isPublic,
    } as unknown as Reflector;
    return new ApiTokenGuard(config, reflector);
  }

  it('allows public routes without a token', () => {
    expect(guardWithPublic(true).canActivate(contextWithAuth())).toBe(true);
  });

  it('accepts the correct bearer token', () => {
    const ctx = contextWithAuth('Bearer secret-token');
    expect(guardWithPublic(false).canActivate(ctx)).toBe(true);
  });

  it('rejects a wrong token', () => {
    const ctx = contextWithAuth('Bearer wrong');
    expect(() => guardWithPublic(false).canActivate(ctx)).toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a missing header', () => {
    expect(() => guardWithPublic(false).canActivate(contextWithAuth())).toThrow(
      UnauthorizedException,
    );
  });
});
