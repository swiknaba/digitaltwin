#!/bin/sh
set -eu

# PostgreSQL runs this only when initializing a new local data volume.
: "${KIREI_DB_PASSWORD:?KIREI_DB_PASSWORD is required}"

psql --set ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
\getenv kirei_password KIREI_DB_PASSWORD
CREATE ROLE kirei LOGIN PASSWORD :'kirei_password';
CREATE DATABASE digitaltwin_development OWNER kirei;
REVOKE CONNECT ON DATABASE digitaltwin_development FROM PUBLIC;
GRANT CONNECT ON DATABASE digitaltwin_development TO kirei;
SQL
