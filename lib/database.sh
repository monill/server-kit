#!/usr/bin/env bash
# The database: MySQL on this server (Oracle's repository, key checked), on another server, or none.
#
# The suggested MySQL follows the PHP version:
#   PHP 7.4–8.1  → MySQL 8.4 LTS (the systems of that time were written and tested against MySQL 8)
#   PHP 8.2+     → MySQL 9.7 LTS
# Both work with every PHP offered here. A MySQL already on the server is kept (a major upgrade is a planned job,
# never a side effect).

MYSQL_KEY_FPR="BCA43417C3B485DD128EC6D4B7B3B788A8D3785C"
MYSQL_LIST="/etc/apt/sources.list.d/mysql.list"
MYSQL_CNF="/etc/mysql/mysql.conf.d/99-server-kit.cnf"

mysql_series_for_php() {
  local v="$1"
  if dpkg --compare-versions "${v}" lt 8.2; then echo 8.4; else echo 9.7; fi
}

mysql_installed_series() {
  command -v mysqld >/dev/null || return 0
  mysqld --version | grep -oE 'Ver [0-9]+\.[0-9]+' | awk '{print $2}'
}

# mysql_install SERIES — from repo.mysql.com when it has packages for this Ubuntu, otherwise Ubuntu's own
mysql_install() {
  local series="$1" installed
  installed="$(mysql_installed_series)"
  if [[ -n "${installed}" ]]; then
    ok "$(t mysql_kept "${installed}")"
    return 0
  fi
  say "$(t mysql_title "${series}")"
  if curl -fsI "https://repo.mysql.com/apt/ubuntu/dists/${OS_CODENAME}/Release" >/dev/null; then
    curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2025 -o /tmp/server-kit-mysql-key.asc
    [[ "$(gpg --show-keys --with-colons /tmp/server-kit-mysql-key.asc 2>/dev/null | awk -F: '/^fpr/ && !n++ {print $10}')" == "${MYSQL_KEY_FPR}" ]] \
      || die "$(t mysql_key_bad)"
    install -d -m 755 /etc/apt/keyrings
    gpg --dearmor < /tmp/server-kit-mysql-key.asc > /etc/apt/keyrings/mysql.gpg
    rm -f /tmp/server-kit-mysql-key.asc
    echo "deb [signed-by=/etc/apt/keyrings/mysql.gpg] https://repo.mysql.com/apt/ubuntu ${OS_CODENAME} mysql-${series}-lts" > "${MYSQL_LIST}"
    apt-get update -y >/dev/null
  else
    warn "$(t mysql_no_oracle_repo "${OS_VERSION}")"
  fi
  # Empty root password = root only enters from this machine, as the system root (auth_socket)
  echo "mysql-community-server mysql-community-server/root-pass password " | debconf-set-selections
  echo "mysql-community-server mysql-community-server/re-root-pass password " | debconf-set-selections
  apt-get install -y mysql-server
  systemctl enable mysql >/dev/null 2>&1
  ok "MySQL $(mysql_installed_series)"
}

# Sized by the machine; rewritten on every run (it follows the plan)
mysql_configure() {
  [[ -n "$(mysql_installed_series)" ]] || return 0
  {
    echo "# server-kit: sized by the server memory; running \"server-kit resize\" recalculates"
    echo "[mysqld]"
    echo "innodb_buffer_pool_size = ${MYSQL_POOL_MB}M"
    (( RAM_MB < 3000 )) && echo "performance_schema = OFF"
    echo "character-set-server = utf8mb4"
  } > "${MYSQL_CNF}"
  systemctl restart mysql
}

# Creates (or keeps) the database and the user of a system. The password comes in DB_PASS (generated when empty).
mysql_create() {
  local name="$1" user="$2" method="caching_sha2_password"
  [[ -n "${DB_PASS}" ]] || DB_PASS="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"
  mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${user}'@'localhost' IDENTIFIED WITH ${method} BY '${DB_PASS}';
ALTER USER '${user}'@'localhost' IDENTIFIED WITH ${method} BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${name}\`.* TO '${user}'@'localhost';
FLUSH PRIVILEGES;
SQL
  ok "$(t db_ready "${name}" "${user}")"
}

# Database on another server: nothing is created there; checks that the user gets in
mysql_check_remote() {
  local host="$1" port="$2" name="$3" user="$4" ca="$5" opts=() version
  command -v mysql >/dev/null || apt-get install -y mysql-client >/dev/null
  [[ -n "${ca}" ]] && opts=(--ssl-mode=VERIFY_CA "--ssl-ca=${ca}")
  version="$(MYSQL_PWD="${DB_PASS}" mysql "${opts[@]}" -h "${host}" -P "${port}" -u "${user}" -Nse 'SELECT VERSION()' "${name}" 2>&1)" \
    || die "$(t db_remote_fail "${name}" "${host}:${port}" "${version}")"
  ok "$(t db_remote_ok "${host}" "${version}")"
}

# The whole database step of an install. Sets DB_MODE, DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS, DB_CA.
database_step() {
  local php="$1" default_mode=local suggested installed
  DB_MODE="${OPT_DB}"
  choose DB_MODE "$(t db_where)" "${default_mode}" \
    local "$(t db_local)" \
    remote "$(t db_remote)" \
    none "$(t db_none)"
  DB_HOST="127.0.0.1"; DB_PORT="3306"; DB_CA=""
  [[ "${DB_MODE}" == "none" ]] && return 0

  ask DB_NAME "$(t db_name)" "${SITE//-/_}"
  ask DB_USER "$(t db_user)" "${SITE//-/_}"
  [[ "${DB_NAME}" =~ ^[A-Za-z0-9_]+$ && "${DB_USER}" =~ ^[A-Za-z0-9_]{1,32}$ ]] || die "$(t db_bad_names)"

  if [[ "${DB_MODE}" == "remote" ]]; then
    ask DB_HOST_REMOTE "$(t db_host)" ""
    DB_HOST="${DB_HOST_REMOTE}"
    [[ "${DB_HOST}" =~ ^[A-Za-z0-9.:-]+$ ]] || die "$(t db_bad_host)"
    ask DB_PORT_REMOTE "$(t db_port)" "3306"; DB_PORT="${DB_PORT_REMOTE}"
    ask_secret DB_PASS "$(t db_password "${DB_USER}")"
    ask DB_CA_SOURCE "$(t db_ca)" "none"
    if [[ "${DB_CA_SOURCE}" != "none" ]]; then
      [[ -f "${DB_CA_SOURCE}" ]] || die "$(t file_missing "${DB_CA_SOURCE}")"
      DB_CA="${SK_CONF_DIR}/${SITE}-db-ca.pem"
      install -m 644 "${DB_CA_SOURCE}" "${DB_CA}"
    else
      case "${DB_HOST}" in
        10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) ;;
        *) confirm_warning "$(t db_no_ca_warning)" || die "$(t check_cancelled)" ;;
      esac
    fi
    mysql_check_remote "${DB_HOST}" "${DB_PORT}" "${DB_NAME}" "${DB_USER}" "${DB_CA}"
    return 0
  fi

  installed="$(mysql_installed_series)"
  if [[ -z "${installed}" ]]; then
    suggested="$(mysql_series_for_php "${php}")"
    MYSQL_SERIES="${OPT_MYSQL:-}"
    choose MYSQL_SERIES "$(t mysql_choose "${php}" "${suggested}")" "${suggested}" \
      8.4 "$(t mysql_84)" \
      9.7 "$(t mysql_97)"
    mysql_install "${MYSQL_SERIES}"
  else
    ok "$(t mysql_kept "${installed}")"
  fi
}
