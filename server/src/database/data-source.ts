import 'reflect-metadata';
import { config as loadEnv } from 'dotenv';
import { DataSource, DataSourceOptions } from 'typeorm';

import { ALL_ENTITIES } from '../entities';

// Load server/.env first, then fall back to the repo-root .env.
loadEnv({ path: ['.env', '../.env'] });

export function buildDataSourceOptions(databaseUrl: string): DataSourceOptions {
  return {
    type: 'postgres',
    url: databaseUrl,
    entities: ALL_ENTITIES,
    // Resolves to .ts under ts-node (CLI) and .js in the compiled dist.
    migrations: [`${__dirname}/migrations/*{.ts,.js}`],
    // Schema is owned by migrations, never by synchronize.
    synchronize: false,
    migrationsRun: true,
  };
}

/** Used by the TypeORM CLI (npm run migration:*). */
export default new DataSource(
  buildDataSourceOptions(
    process.env.DATABASE_URL ??
      'postgres://mangavault:mangavault@localhost:5433/mangavault',
  ),
);
