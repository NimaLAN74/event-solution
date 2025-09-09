#!/usr/bin/env bash
set -euo pipefail

# Read Postgres password from Docker secret
export PGPASSWORD="$(cat /run/secrets/postgres_password)"

# Match Compose service + env
PGHOST="${PGHOST:-postgres}"
PGUSER="${PGUSER:-airflow}"
PGDATABASE="${PGDATABASE:-airflow}"

# Admin creds (defaults; can be overridden via env)
DEFAULT_ADMIN_PASS='A8uE$4pQ!c9Lz3hN^2sW7@vB1yR6mKdT'  # single-quoted so $4 is not expanded
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-$DEFAULT_ADMIN_PASS}"

# Explicit connstring so psql never falls back to 'postgres' user
PSQL_URI="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:5432/${PGDATABASE}"

# Ensure pgcrypto and bootstrap KV table
psql "${PSQL_URI}" -v ON_ERROR_STOP=1 <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS bootstrap;
CREATE TABLE IF NOT EXISTS bootstrap.kv (
  k text PRIMARY KEY,
  v text NOT NULL
);
SQL

# Upsert admin creds (properly quoted via psql variables)
psql "${PSQL_URI}" -v ON_ERROR_STOP=1 \
  -v admin_user="${ADMIN_USER}" \
  -v admin_pw="${ADMIN_PASS}" <<'SQL'
INSERT INTO bootstrap.kv (k, v) VALUES
  ('admin_user',    :'admin_user'),
  ('admin_password',:'admin_pw')
ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v;
SQL

# Insert keys if missing
psql "${PSQL_URI}" -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO bootstrap.kv (k, v) VALUES
  ('fernet_key', gen_random_uuid()::text)
ON CONFLICT (k) DO NOTHING;

INSERT INTO bootstrap.kv (k, v) VALUES
  ('webserver_secret_key', gen_random_uuid()::text)
ON CONFLICT (k) DO NOTHING;
SQL

# Export to shared volume for Airflow container
mkdir -p /secrets_out
psql -At "${PSQL_URI}" -c "SELECT v FROM bootstrap.kv WHERE k='fernet_key' LIMIT 1;"           > /secrets_out/fernet_key
psql -At "${PSQL_URI}" -c "SELECT v FROM bootstrap.kv WHERE k='webserver_secret_key' LIMIT 1;" > /secrets_out/webserver_secret_key
psql -At "${PSQL_URI}" -c "SELECT v FROM bootstrap.kv WHERE k='admin_user' LIMIT 1;"           > /secrets_out/admin_user
psql -At "${PSQL_URI}" -c "SELECT v FROM bootstrap.kv WHERE k='admin_password' LIMIT 1;"       > /secrets_out/admin_password

# Trim trailing newlines so bash reads cleanly later
for f in /secrets_out/fernet_key /secrets_out/webserver_secret_key /secrets_out/admin_user /secrets_out/admin_password; do
  tr -d '\n' < "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
done

echo "init-secrets: wrote fernet_key, webserver_secret_key, admin_user, admin_password to /secrets_out"