#!/bin/sh
set -eu

create_role_and_database() {
    role_name="$1"
    database_name="$2"
    password="$3"

    if ! psql --username "$POSTGRES_USER" --dbname postgres --tuples-only --no-align \
        --set role_name="$role_name" <<'SQL' | grep -q 1; then
SELECT 1 FROM pg_roles WHERE rolname = :'role_name';
SQL
        psql --username "$POSTGRES_USER" --dbname postgres \
            --set role_name="$role_name" --set password="$password" <<'SQL'
CREATE ROLE :"role_name" LOGIN PASSWORD :'password';
SQL
    fi

    if ! psql --username "$POSTGRES_USER" --dbname postgres --tuples-only --no-align \
        --set database_name="$database_name" <<'SQL' | grep -q 1; then
SELECT 1 FROM pg_database WHERE datname = :'database_name';
SQL
        psql --username "$POSTGRES_USER" --dbname postgres \
            --set role_name="$role_name" --set database_name="$database_name" <<'SQL'
CREATE DATABASE :"database_name" OWNER :"role_name";
SQL
    fi
}

create_role_and_database keycloak keycloak "$KEYCLOAK_DB_PASSWORD"
create_role_and_database forge-campus forge-campus "$FORGE_CAMPUS_POSTGRES_PASSWORD"
