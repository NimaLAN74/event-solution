#!/usr/bin/env bash
set -euo pipefail

# Read password from Docker secret
export PGPASSWORD="$(cat /run/secrets/postgres_password)"

# Match the Compose service + env
PGHOST="${PGHOST:-postgres}"
PGUSER="${PGUSER:-airflow}"
PGDATABASE="${PGDATABASE:-airflow}"

# Use an explicit connstring so psql never falls back to 'postgres' user
PSQL_URI="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:5432/${PGDATABASE}"

# Example: create schema/table to stash one-time secrets (idempotent)
psql "${PSQL_URI}" <<'SQL'
CREATE SCHEMA IF NOT EXISTS bootstrap;
CREATE TABLE IF NOT EXISTS bootstrap.kv (
  k text PRIMARY KEY,
  v text NOT NULL
);
-- insert only if not exists
INSERT INTO bootstrap.kv (k, v) VALUES
  ('fernet_key', gen_random_uuid()::text),
  ('webserver_secret_key', gen_random_uuid()::text),
  ('admin_password', gen_random_uuid()::text)
ON CONFLICT (k) DO NOTHING;
SQL

# Write to a shared volume for the webserver to consume (already read-only mounted there)
mkdir -p /secrets_out
psql -At "${PSQL_URI}" -c "SELECT v FROM bootstrap.kv WHERE k='fernet_key' LIMIT 1;" > /secrets_out/fernet_key
psql -At "${PSQL_URI}" -c "SELECT v FROM bootstrap.kv WHERE k='webserver_secret_key' LIMIT 1;" > /secrets_out/webserver_secret_key
psql -At "${PSQL_URI}" -c "SELECT v FROM bootstrap.kv WHERE k='admin_password' LIMIT 1;" > /secrets_out/admin_password