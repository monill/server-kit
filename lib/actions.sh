#!/usr/bin/env bash
# The actions: install, update, remove, check and resize. One system per server.

SK_HOME="/opt/server-kit"
MACHINE_FILE="${SK_CONF_DIR}/machine.conf"
REVERB_PORT=8080

# Every variable a question may fill starts empty (set -u)
SITE=""; REPO=""; BRANCH=""; DOMAIN=""; EMAIL=""; PHP_VERSION=""; APP_TYPE=""; APP_DIR=""; DOCROOT=""; APP_USER=""
APP_HOME=""; DIR_APP=""; DB_MODE=""; DB_NAME=""; DB_USER=""; DB_PASS=""; DB_HOST=""; DB_PORT=""; DB_CA=""
DB_HOST_REMOTE=""; DB_PORT_REMOTE=""; DB_CA_SOURCE=""; MYSQL_SERIES=""; OPT_MYSQL=""; TEST_MODE=0; REVERB=0
INSTALLED_AT=""; FPM_TOTAL=0; MYSQL_POOL_MB=0; REDIS_MB=0; WORKERS=1

# Keeps a copy in /opt/server-kit and the "server-kit" command, so update/remove/resize work after the clone is gone
self_install() {
  if [[ "${SK_DIR}" != "${SK_HOME}" ]]; then
    rm -rf "${SK_HOME}.new"
    cp -a "${SK_DIR}" "${SK_HOME}.new"
    rm -rf "${SK_HOME}"
    mv "${SK_HOME}.new" "${SK_HOME}"
  fi
  cat > /usr/local/bin/server-kit <<EOF
#!/usr/bin/env bash
exec bash ${SK_HOME}/install.sh "\$@"
EOF
  chmod 755 /usr/local/bin/server-kit
  # At boot: when the plan changed (more memory or processors), PHP, MySQL, Redis and queues follow it
  cat > /etc/systemd/system/server-kit-resize.service <<EOF
[Unit]
Description=server-kit: follow the server size after a plan change
After=network-online.target mysql.service
Before=nginx.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/server-kit resize --if-changed --plain

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable server-kit-resize.service >/dev/null 2>&1 || true
}

machine_save() { printf 'RAM_MB=%s\nCPUS=%s\n' "${RAM_MB}" "${CPUS}" > "${MACHINE_FILE}"; }

has_local_mysql() { [[ -n "$(mysql_installed_series)" ]] && echo 1 || echo 0; }

php_menu() {
  local suggested="$1" v label args=()
  for v in "${PHP_AVAILABLE[@]}"; do
    if php_is_eol "${v}"; then label="$(t php_label_eol "$(php_eol_date "${v}")")"
    else label="$(t php_label_ok "$(php_eol_date "${v}")")"; fi
    [[ "${v}" == "${suggested}" ]] && label="${label} · $(t php_label_suggested)"
    args+=("${v}" "${label}")
  done
  PHP_VERSION="${OPT_PHP}"
  choose PHP_VERSION "$(t php_choose)" "${suggested}" "${args[@]}"
  if php_is_eol "${PHP_VERSION}"; then
    confirm_warning "$(t php_eol_confirm "${PHP_VERSION}")" || die "$(t check_cancelled)"
  fi
  # The dependencies locked in composer.lock decide too: composer install refuses a PHP they do not accept
  if ! php_project_accepts "${APP_DIR}" "${PHP_VERSION}"; then
    confirm_warning "$(t php_not_accepted "${PHP_VERSION}")" || die "$(t check_cancelled)"
  fi
}

# Applies today's machine size to PHP, MySQL, Redis and the queue
resize_all() {
  sizing_compute "$(has_local_mysql)"
  php_resize_all "${FPM_TOTAL}"
  mysql_configure
  redis_resize
  if [[ -f "${REDIS_CONF}" ]]; then systemctl restart redis-server 2>/dev/null || true; fi
  if [[ -n "${SITE}" && -f "/etc/supervisor/conf.d/${SITE}.conf" ]]; then
    sed -i -E "0,/^numprocs=/s/^numprocs=.*/numprocs=${WORKERS}/" "/etc/supervisor/conf.d/${SITE}.conf"
    supervisorctl reread >/dev/null; supervisorctl update >/dev/null
  fi
  machine_save
}

# Only what is installed on this server
summary_sizing() {
  local line
  line="PHP-FPM: ${FPM_TOTAL} $(t sizing_processes)"
  [[ "$(has_local_mysql)" == 1 ]] && line+=" · MySQL: ${MYSQL_POOL_MB} MB"
  [[ -f "${REDIS_CONF}" ]] && line+=" · Redis: ${REDIS_MB} MB"
  [[ "${APP_TYPE}" == "laravel" ]] && line+=" · $(t sizing_queue): ${WORKERS}"
  info "$(t sizing_line "${RAM_MB}" "${CPUS}")"
  info "  ${line}"
}

action_install() {
  system_detect
  local first=1 previous_repo="" previous_domain=""

  # One system per server: installing again is only for the same system
  if state_exists; then
    previous_repo="$(grep -E '^REPO=' "${SITE_FILE}" | cut -d= -f2- || true)"
    state_load
    first=0
    previous_domain="${DOMAIN}"
    OPT_REPO="${OPT_REPO:-${REPO}}"; OPT_DOMAIN="${OPT_DOMAIN:-${DOMAIN}}"; OPT_BRANCH="${OPT_BRANCH:-${BRANCH}}"
    REPO=""; DOMAIN=""; BRANCH=""
  fi

  ask REPO "$(t ask_repo)" "${OPT_REPO}"
  [[ "${REPO}" =~ ^(https://|git@)[A-Za-z0-9._@:/~-]+$ ]] || die "$(t bad_repo "${REPO}")"
  if [[ ${first} -eq 0 && "$(printf '%q' "${REPO}")" != "${previous_repo}" ]]; then
    die "$(t one_system "${SITE}" "${previous_domain}")"
  fi
  [[ ${first} -eq 0 ]] && warn "$(t site_again "${SITE}")"
  BRANCH="${OPT_BRANCH}"
  [[ ${first} -eq 1 ]] && ask SITE "$(t ask_site)" "$(app_name_from_repo "${REPO}")"
  [[ "${SITE}" =~ ^[a-z][a-z0-9-]{1,27}$ ]] || die "$(t bad_site)"

  TEST_MODE="${OPT_TEST}"
  ask DOMAIN "$(t ask_domain)" "${OPT_DOMAIN}"
  [[ "${DOMAIN}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ && "${DOMAIN}" == *.* ]] || die "$(t bad_domain)"
  DOMAIN="$(echo "${DOMAIN}" | tr '[:upper:]' '[:lower:]')"
  if [[ ${TEST_MODE} -eq 0 ]]; then
    ask EMAIL "$(t ask_email)" "${OPT_EMAIL}"
    [[ "${EMAIL}" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]] || die "$(t bad_email)"
  fi

  system_check "${DOMAIN}" "${TEST_MODE}"
  system_base
  system_firewall
  system_swap
  system_auto_updates
  self_install

  APP_USER="${SITE}"
  APP_DIR="/var/www/${SITE}"
  DIR_APP="${APP_DIR}"
  app_user_create "${APP_USER}" "${APP_DIR}"
  app_clone "${REPO}" "${BRANCH}" "${APP_DIR}" "${APP_USER}"
  [[ -n "${BRANCH}" ]] || BRANCH="$(sudo -u "${APP_USER}" git -C "${APP_DIR}" rev-parse --abbrev-ref HEAD)"

  APP_TYPE="$(app_detect_type "${APP_DIR}")"
  DOCROOT="$(app_detect_docroot "${APP_DIR}" "${APP_TYPE}")"
  ok "$(t app_type "${APP_TYPE}" "${DOCROOT}")"
  php_check_legacy "${APP_DIR}"

  # Installing again: the database password the system already uses is kept
  if [[ -f "${APP_DIR}/.env" ]]; then DB_PASS="$(env_get "${APP_DIR}/.env" DB_PASSWORD)"
  elif [[ -f "${APP_HOME}/database.txt" ]]; then DB_PASS="$(grep -E '^password=' "${APP_HOME}/database.txt" | cut -d= -f2- || true)"; fi

  php_repository
  php_menu "$(php_suggest "${APP_DIR}")"
  # shellcheck disable=SC2046
  php_install "${PHP_VERSION}" $(app_required_extensions "${APP_DIR}")

  database_step "${PHP_VERSION}"
  if [[ "${DB_MODE}" == "local" ]]; then
    sizing_compute 1
    mysql_configure
    mysql_create "${DB_NAME}" "${DB_USER}"
  fi

  [[ "${APP_TYPE}" == "laravel" ]] && redis_install

  sizing_compute "$(has_local_mysql)"
  php_pool "${PHP_VERSION}" "${SITE}" "${APP_USER}" "${FPM_TOTAL}"

  composer_run "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}"
  env_prepare "${APP_DIR}" "${APP_USER}" "${APP_TYPE}" "https://${DOMAIN}"
  if node_needed "${APP_DIR}"; then node_install; node_build "${APP_DIR}" "${APP_USER}"; fi

  local reverb_port=""
  if [[ "${APP_TYPE}" == "laravel" ]]; then
    laravel_setup "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}" "${first}"
    REVERB="$(laravel_uses_reverb "${APP_DIR}")"
    [[ "${REVERB}" == 1 ]] && reverb_port="${REVERB_PORT}"
    supervisor_site "${SITE}" "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}" "${WORKERS}" "${reverb_port}"
  else
    php_credentials_file "${APP_USER}" "${APP_HOME}"
  fi

  nginx_install
  nginx_default_server
  nginx_site "${SITE}" "${DOMAIN}" "${DOCROOT}" "${APP_TYPE}" "${reverb_port}"
  nginx_https "${SITE}" "${DOMAIN}" "${EMAIL}" "${TEST_MODE}"

  INSTALLED_AT="$(date -Iseconds)"
  state_save
  resize_all

  say "$(t done_title)"
  info "$(t done_site "${DOMAIN}")"
  info "$(t done_folder "${APP_DIR}" "${APP_USER}")"
  info "PHP ${PHP_VERSION} · ${APP_TYPE} · $(t done_db "${DB_MODE}")"
  summary_sizing
  info "$(t done_commands)"
  info "$(t done_log "${SK_LOG}")"
}

action_update() {
  local old_php laravel=0
  state_load
  system_detect
  DIR_APP="${APP_DIR}"
  old_php="${PHP_VERSION}"
  [[ "${APP_TYPE}" == "laravel" ]] && laravel=1
  say "$(t update_title "${SITE}")"

  # Changing the PHP version: --php 8.5
  if [[ -n "${OPT_PHP}" && "${OPT_PHP}" != "${PHP_VERSION}" ]]; then
    php_repository
    [[ " ${PHP_AVAILABLE[*]} " == *" ${OPT_PHP} "* ]] || die "$(t php_version_missing "${OPT_PHP}" "${OS_VERSION}")"
    if ! php_project_accepts "${APP_DIR}" "${OPT_PHP}"; then
      confirm_warning "$(t php_not_accepted "${OPT_PHP}")" || die "$(t check_cancelled)"
    fi
    # shellcheck disable=SC2046
    php_install "${OPT_PHP}" $(app_required_extensions "${APP_DIR}")
    PHP_VERSION="${OPT_PHP}"
  fi

  if [[ ${laravel} -eq 1 ]]; then artisan "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}" down --retry=15 || true; fi
  if ! sudo -u "${APP_USER}" -H git -C "${APP_DIR}" pull --ff-only; then
    if [[ ${laravel} -eq 1 ]]; then artisan "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}" up || true; fi
    die "$(t update_pull_fail)"
  fi
  composer_run "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}"
  if node_needed "${APP_DIR}"; then node_install; node_build "${APP_DIR}" "${APP_USER}"; fi

  sizing_compute "$(has_local_mysql)"
  if [[ "${PHP_VERSION}" != "${old_php}" ]]; then
    php_pool "${PHP_VERSION}" "${SITE}" "${APP_USER}" "${FPM_TOTAL}"
  else
    systemctl reload "php${PHP_VERSION}-fpm"
  fi

  if [[ ${laravel} -eq 1 ]]; then
    [[ "${DB_MODE}" != "none" ]] && artisan "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}" migrate --force
    artisan "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}" optimize || warn "$(t laravel_optimize_fail)"
    if [[ "${PHP_VERSION}" != "${old_php}" ]]; then
      sed -i "s#/usr/bin/php${old_php} #/usr/bin/php${PHP_VERSION} #g" "/etc/supervisor/conf.d/${SITE}.conf" "/etc/cron.d/${SITE}"
      supervisorctl reread >/dev/null; supervisorctl update >/dev/null
    fi
    artisan "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}" queue:restart || true
    if [[ "${REVERB}" == 1 ]]; then supervisorctl restart "${SITE}-reverb" >/dev/null 2>&1 || true; fi
    artisan "${APP_DIR}" "${APP_USER}" "${PHP_VERSION}" up
  fi
  state_save
  ok "$(t update_ok "${SITE}" "$(sudo -u "${APP_USER}" git -C "${APP_DIR}" log -1 --format='%h %s' | cut -c1-60)")"
}

action_remove() {
  state_load
  say "$(t remove_title "${SITE}")"
  confirm "$(t remove_confirm "${SITE}" "${DOMAIN}")" n || die "$(t check_cancelled)"

  rm -f "/etc/nginx/sites-enabled/${SITE}" "/etc/nginx/sites-available/${SITE}"
  if nginx -t >/dev/null 2>&1; then systemctl reload nginx; fi
  rm -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${SITE}.conf"
  systemctl restart "php${PHP_VERSION}-fpm" 2>/dev/null || true
  if [[ -f "/etc/supervisor/conf.d/${SITE}.conf" ]]; then
    rm -f "/etc/supervisor/conf.d/${SITE}.conf"
    supervisorctl reread >/dev/null; supervisorctl update >/dev/null
  fi
  rm -f "/etc/cron.d/${SITE}"
  ok "$(t remove_off)"

  if [[ "${DB_MODE}" == "local" ]] && confirm "$(t remove_db_confirm "${DB_NAME}")" n; then
    mysql -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; DROP USER IF EXISTS '${DB_USER}'@'localhost';"
    ok "$(t remove_db_ok "${DB_NAME}")"
  fi
  if confirm "$(t remove_files_confirm "${APP_DIR}")" n; then
    rm -rf "${APP_DIR}"
    userdel -r "${APP_USER}" 2>/dev/null || true
    ok "$(t remove_files_ok "${APP_DIR}")"
  fi
  rm -f "${SITE_FILE}" "${SK_CONF_DIR}/${SITE}-db-ca.pem"
  ok "$(t remove_ok "${SITE}")"
}

action_check() {
  system_detect
  system_check "" 1
  sizing_compute "$(has_local_mysql)"
  say "$(t site_title)"
  if state_exists; then
    state_load
    (
      local status
      if systemctl is-active --quiet "php${PHP_VERSION}-fpm"; then status="${C_GREEN}$(t running)${C_OFF}"
      else status="${C_RED}$(t stopped)${C_OFF}"; fi
      info "${C_BOLD}${SITE}${C_OFF} · ${DOMAIN} · PHP ${PHP_VERSION} · ${APP_TYPE} · ${status}"
      info "${REPO} (${BRANCH}) · $(sudo -u "${APP_USER}" git -C "${APP_DIR}" log -1 --format='%h %cs' 2>/dev/null)"
    )
  else
    info "$(t site_none)"
  fi
  say "$(t services_title)"
  local svc
  for svc in nginx mysql redis-server supervisor; do
    systemctl cat "${svc}.service" >/dev/null 2>&1 || continue
    if systemctl is-active --quiet "${svc}"; then ok "${svc}"; else warn "${svc}: $(t stopped)"; fi
  done
  say "$(t sizing_title)"
  summary_sizing
}

action_resize() {
  system_detect
  if [[ "${RESIZE_IF_CHANGED}" == 1 && -f "${MACHINE_FILE}" ]]; then
    local saved_ram saved_cpus
    saved_ram="$(grep -E '^RAM_MB=' "${MACHINE_FILE}" | cut -d= -f2 || true)"
    saved_cpus="$(grep -E '^CPUS=' "${MACHINE_FILE}" | cut -d= -f2 || true)"
    # Small differences in reported memory are normal between boots: only a real change counts
    if (( saved_cpus == CPUS && (RAM_MB - saved_ram) * (RAM_MB - saved_ram) < 256 * 256 )); then
      return 0
    fi
  fi
  if state_exists; then state_load; fi
  say "$(t resize_title "${RAM_MB}" "${CPUS}")"
  resize_all
  summary_sizing
  ok "$(t resize_ok)"
}
