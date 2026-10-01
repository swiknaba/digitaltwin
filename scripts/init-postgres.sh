#!/bin/sh
set -eu

# PostgreSQL runs this only when initializing a new local data volume.
: "${KIREI_DB_PASSWORD:?KIREI_DB_PASSWORD is required}"
: "${MATTERMOST_DB_PASSWORD:?MATTERMOST_DB_PASSWORD is required}"

psql --set ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
\getenv kirei_password KIREI_DB_PASSWORD
\getenv mattermost_password MATTERMOST_DB_PASSWORD
CREATE ROLE kirei LOGIN PASSWORD :'kirei_password';
CREATE DATABASE digitaltwin_development OWNER kirei;
REVOKE CONNECT ON DATABASE digitaltwin_development FROM PUBLIC;
GRANT CONNECT ON DATABASE digitaltwin_development TO kirei;
CREATE ROLE mattermost LOGIN PASSWORD :'mattermost_password';
CREATE DATABASE mattermost OWNER mattermost;
REVOKE CONNECT ON DATABASE mattermost FROM PUBLIC;
GRANT CONNECT ON DATABASE mattermost TO mattermost;
SQL
