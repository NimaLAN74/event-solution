#!/usr/bin/env bash
set -euo pipefail

mkdir -p /opt/airflow/dags /opt/airflow/logs /opt/airflow/plugins

# Read admin creds from files if present; otherwise use safe defaults.
ADMIN_USER="$( [ -s /run/airflow-secrets/admin_user ] && tr -d '\n' < /run/airflow-secrets/admin_user || printf %s 'admin' )"
ADMIN_PASS="$( [ -s /run/airflow-secrets/admin_password ] && tr -d '\n' < /run/airflow-secrets/admin_password || printf %s 'A8uE$4pQ!c9Lz3hN^2sW7@vB1yR6mKdT' )"

# Log what we detected (lengths only)
printf 'Simple auth manager | user len=%s pass len=%s\n' "${#ADMIN_USER}" "${#ADMIN_PASS}"

# Always (re)write the JSON (single-line)
printf '{"%s":"%s"}' "$ADMIN_USER" "$ADMIN_PASS" > /opt/airflow/simple_auth_manager_passwords.json
chmod 600 /opt/airflow/simple_auth_manager_passwords.json || true

# Init/upgrade DB and run components
airflow db migrate
airflow scheduler &
airflow triggerer &

exec airflow api-server --port 8080