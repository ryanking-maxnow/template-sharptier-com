import * as migration_20260221_115858_initial_schema from './20260221_115858_initial_schema';
import * as migration_20260221_133407_add_redirects_plugin_tables from './20260221_133407_add_redirects_plugin_tables';

export const migrations = [
  {
    up: migration_20260221_115858_initial_schema.up,
    down: migration_20260221_115858_initial_schema.down,
    name: '20260221_115858_initial_schema',
  },
  {
    up: migration_20260221_133407_add_redirects_plugin_tables.up,
    down: migration_20260221_133407_add_redirects_plugin_tables.down,
    name: '20260221_133407_add_redirects_plugin_tables'
  },
];
