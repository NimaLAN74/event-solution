# Event Solution – Airflow + Nginx Proxy

This repository provides a **production-leaning stack** with **Apache Airflow (LocalExecutor)** and **Postgres**, fronted by an **Nginx reverse proxy**.  
Secrets are **not** stored in environment variables. Instead, they are seeded into Postgres and mounted from secure files.

---

## Features

- **Airflow (LocalExecutor)**
  - Postgres metadata DB
  - SimpleAuth Manager with a static admin user (stored in DB, not env)
  - Fernet & API secret keys stored securely
- **Nginx proxy** for routing and TLS termination
- **No plaintext secrets in `docker-compose.yml`**
- **DAGs auto-discovery** via `/airflow-home/dags`

---

## Container structure

### `airflow-service/docker-compose.yml`
```
services:
  postgres        # Postgres 17 — metadata DB (with healthcheck)
  init-secrets    # One-time container — seeds bootstrap.kv with app secrets
  airflow         # Airflow — scheduler, triggerer, dag-processor, api-server

volumes:
  pg_data         # Persisted Postgres data
  secrets_cache   # Shared volume for init-secrets → airflow

networks:
  airflow_net (external)
  infra_net   (external)  # shared with Nginx proxy
```

### `infra-service/docker-compose.yml`
```
services:
  nginx           # Nginx — TLS terminator & proxy → airflow:8080

networks:
  infra_net   (external)
  airflow_net (external)
```

---

## Repository layout

```
event-solution/
├─ airflow-service/
│  ├─ docker-compose.yml
│  ├─ scripts/
│  │  ├─ init-secrets.sh
│  │  └─ airflow-start.sh
│  ├─ secrets/
│  │  └─ postgres_password.txt       # <-- you create this
│  └─ airflow-home/
│     ├─ dags/                       # your DAGs go here
│     ├─ logs/
│     ├─ plugins/
│     └─ airflow.cfg
└─ infra-service/
   ├─ docker-compose.yml
   └─ nginx.conf
```

---

## Setup

### 1. Create external networks
```bash
docker network create airflow_net || true
docker network create infra_net || true
```

### 2. Create DB secret file
```bash
mkdir -p airflow-service/secrets
openssl rand -hex 24 > airflow-service/secrets/postgres_password.txt
```

### 3. Start Airflow
```bash
cd airflow-service
docker compose up -d
```

This will:
- Start Postgres with a file-based password.
- Run `init-secrets` (seeds keys + admin credentials into DB).
- Launch Airflow (scheduler, triggerer, dag-processor, api-server).

### 4. Start the proxy
```bash
cd ../infra-service
docker compose up -d
```

Nginx will serve Airflow on **https://localhost/** (or your configured domain).

---

## Access

- **URL**: `https://<your-host>/`
- **Admin login (SimpleAuth)**:  
  - User: `****`  
  - Password: `****`  

*(actual values are seeded in DB at bootstrap and written into `secrets_cache` volume – see `/run/airflow-secrets/admin_user` and `admin_password` inside the `airflow` container)*

---

## Add DAGs

Place `.py` DAG files into:

```
airflow-service/airflow-home/dags/
```

Airflow auto-detects new DAGs.

Check with:
```bash
docker compose -f airflow-service/docker-compose.yml exec airflow \
  bash -lc 'airflow dags list --local -o table'
```

---

## Common commands

```bash
# Status
docker compose -f airflow-service/docker-compose.yml ps
docker compose -f infra-service/docker-compose.yml ps

# Logs
docker compose -f airflow-service/docker-compose.yml logs -f airflow
docker compose -f infra-service/docker-compose.yml logs -f nginx

# Restart Airflow
docker compose -f airflow-service/docker-compose.yml restart airflow
```

---

## Security notes

- Database password is loaded from `secrets/postgres_password.txt`
- Airflow Fernet key, API secret, and admin credentials are seeded into Postgres (`bootstrap.kv`)
- Airflow Connections and Variables are stored in its metadata DB
- TLS termination handled by Nginx; mount your real certificates in `infra-service/nginx.conf`
- Sensitive files (`postgres_password.txt`, `simple_auth_manager_passwords.json`, etc.) should be excluded from version control with `.gitignore`

---

## Cleanup

```bash
docker compose -f airflow-service/docker-compose.yml down -v
docker compose -f infra-service/docker-compose.yml down -v
docker network rm airflow_net infra_net
```

---

## Notes

- Admin credentials are **static** once seeded. You can rotate them by updating `bootstrap.kv` directly in Postgres and restarting Airflow.
- This setup is intended as a **secure local/dev baseline**. For production, integrate with a managed secret store (Vault, AWS Secrets Manager, etc.) and replace the SimpleAuth manager.
