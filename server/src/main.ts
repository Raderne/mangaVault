import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';

import { AppModule } from './app.module';

async function bootstrap() {
  // DEBUG emits one line per cover fetched, which is thousands per import and
  // the reason the container log was the largest on the VM. Keep it in dev.
  // Typed as NestExpressApplication so `disable()` below is checked rather than
  // reached through an `any` from getHttpAdapter().getInstance().
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    logger:
      process.env.NODE_ENV === 'production'
        ? ['log', 'warn', 'error']
        : ['log', 'warn', 'error', 'debug', 'verbose'],
  });
  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  // Express advertises itself in every response header. Nothing needs it and it
  // hands a scanner the stack for free.
  app.disable('x-powered-by');
  await app.listen(process.env.PORT ?? 3000, '0.0.0.0');
}
void bootstrap();
