#!/usr/bin/env bash
# Laravel and plain PHP setup after the code is in place: .env, key, database tables, links, cache, scheduler.

# env_set FILE KEY VALUE — changes the line when it exists (commented or not), adds it otherwise
env_set() {
  local file="$1" key="$2" value="$3" escaped
  escaped="$(printf '%s' "${value}" | sed -e 's/[\/&|]/\\&/g')"
  if grep -qE "^#?[[:space:]]*${key}=" "${file}"; then
    sed -i -E "0,/^#?[[:space:]]*${key}=.*/s||${key}=${escaped}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${file}"
  fi
}

env_get() { grep -E "^$2=" "$1" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '"' || true; }

# Prepares .env from .env.example (Laravel and any project that has one). Existing .env: only keys it lacks
# are filled in, so a reinstall never overwrites the system's settings.
env_prepare() {
  local dir="$1" user="$2" type="$3" url="$4" env="$1/.env" fresh=0
  if [[ ! -f "${env}" ]]; then
    [[ -f "${dir}/.env.example" ]] || return 0
    install -o "${user}" -g www-data -m 640 "${dir}/.env.example" "${env}"
    fresh=1
  fi
  chown "${user}:www-data" "${env}"; chmod 640 "${env}"
  [[ ${fresh} -eq 1 ]] || { ok "$(t env_kept)"; return 0; }

  env_set "${env}" APP_URL "${url}"
  if [[ "${type}" == "laravel" ]]; then
    env_set "${env}" APP_ENV production
    env_set "${env}" APP_DEBUG false
    env_set "${env}" LOG_LEVEL warning
  fi
  if [[ "${DB_MODE}" != "none" ]]; then
    env_set "${env}" DB_CONNECTION mysql
    env_set "${env}" DB_HOST "${DB_HOST}"
    env_set "${env}" DB_PORT "${DB_PORT}"
    env_set "${env}" DB_DATABASE "${DB_NAME}"
    env_set "${env}" DB_USERNAME "${DB_USER}"
    env_set "${env}" DB_PASSWORD "${DB_PASS}"
    [[ -n "${DB_CA}" ]] && env_set "${env}" MYSQL_ATTR_SSL_CA "${DB_CA}"
  fi
  if [[ "${type}" == "laravel" && -n "${REDIS_PASS}" ]]; then
    env_set "${env}" REDIS_HOST 127.0.0.1
    env_set "${env}" REDIS_PASSWORD "${REDIS_PASS}"
    env_set "${env}" CACHE_STORE redis
    env_set "${env}" CACHE_DRIVER redis
    env_set "${env}" SESSION_DRIVER redis
    env_set "${env}" QUEUE_CONNECTION redis
    env_set "${env}" REDIS_PREFIX "${SITE}_"
  fi
  ok "$(t env_ready)"
}

# Plain PHP without .env: the database data goes to a file only the system's user reads, to copy into its config
php_credentials_file() {
  local user="$1" file="$2/database.txt"
  [[ "${DB_MODE}" == "none" ]] && return 0
  [[ -f "${DIR_APP}/.env" ]] && return 0
  {
    echo "# ${SITE}: database (copy into the system's configuration file, then delete this file)"
    echo "host=${DB_HOST}"
    echo "port=${DB_PORT}"
    echo "database=${DB_NAME}"
    echo "user=${DB_USER}"
    echo "password=${DB_PASS}"
  } > "${file}"
  chown "${user}:${user}" "${file}"; chmod 600 "${file}"
  warn "$(t credentials_file "${file}")"
}

# artisan DIR USER PHP args...
artisan() { local dir="$1" user="$2" v="$3"; shift 3; sudo -u "${user}" -H bash -c "cd '${dir}' && /usr/bin/php${v} artisan $*"; }

laravel_setup() {
  local dir="$1" user="$2" v="$3" first="$4"
  say "$(t laravel_title)"
  # Folders Laravel writes to: the web server (www-data) only reads the rest
  install -d -o "${user}" -g www-data -m 2775 "${dir}/storage" "${dir}/bootstrap/cache"
  find "${dir}/storage" "${dir}/bootstrap/cache" -type d -exec chmod 2775 {} +
  setfacl -R -m g:www-data:rwX -dm g:www-data:rwX "${dir}/storage" "${dir}/bootstrap/cache"

  [[ -n "$(env_get "${dir}/.env" APP_KEY)" ]] || artisan "${dir}" "${user}" "${v}" key:generate --force
  if [[ "${DB_MODE}" != "none" ]]; then
    artisan "${dir}" "${user}" "${v}" migrate --force
    if [[ "${first}" == 1 ]] && grep -rqs "class DatabaseSeeder" "${dir}/database/seeders" 2>/dev/null; then
      confirm "$(t laravel_seed)" n && artisan "${dir}" "${user}" "${v}" db:seed --force
    fi
  fi
  [[ -L "${dir}/public/storage" ]] || artisan "${dir}" "${user}" "${v}" storage:link || true
  artisan "${dir}" "${user}" "${v}" optimize || warn "$(t laravel_optimize_fail)"

  # Scheduler: every minute, as the system's user
  echo "* * * * * ${user} cd ${dir} && /usr/bin/php${v} artisan schedule:run >> /dev/null 2>&1" > "/etc/cron.d/${SITE}"
  chmod 644 "/etc/cron.d/${SITE}"
  ok "$(t laravel_ok)"
}

laravel_uses_reverb() { grep -qs '"laravel/reverb"' "$1/composer.json" && echo 1 || echo 0; }
