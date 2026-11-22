#!/usr/bin/env bash
# PHP: any version from 7.4 to 8.6 from the ondrej/php repository (Ondřej Surý keeps the official releases, usually on
# the same day). When that repository has nothing yet for this Ubuntu (a brand-new release, like 26.04 at first),
# only Ubuntu's own PHP is offered. The system gets its own PHP-FPM pool, running as its own user.

PHP_VERSIONS=(8.6 8.5 8.4 8.3 8.2 8.1 8.0 7.4)
PHP_AVAILABLE=()

# End of security fixes for each branch (php.net/supported-versions, php.net/eol)
php_eol_date() {
  case "$1" in
    7.4) echo 2022-11-28 ;; 8.0) echo 2023-11-26 ;; 8.1) echo 2025-12-31 ;;
    8.2) echo 2026-12-31 ;; 8.3) echo 2027-12-31 ;; 8.4) echo 2028-12-31 ;; 8.5) echo 2029-12-31 ;;
    8.6) echo 2030-12-31 ;; *) echo 1970-01-01 ;;
  esac
}

php_is_eol() { [[ "$(date +%F)" > "$(php_eol_date "$1")" ]]; }

# Code written for PHP 5 (the mysql_* functions, removed in PHP 7) does not run on any version offered here
php_check_legacy() {
  local dir="$1" count
  count="$(grep -rlsE '\bmysql_(connect|query|fetch_(array|assoc|row))[[:space:]]*\(' --include='*.php' "${dir}" 2>/dev/null | wc -l || true)"
  (( count == 0 )) || die "$(t php_legacy_code "${count}")"
}

# Does the project accept PHP X.Y? Reads the "php" requirement of composer.json and, when there is a composer.lock,
# the one of every locked package (composer install refuses a PHP any of them does not accept). Python comes with
# every Ubuntu Server; constraints are checked on major.minor, which is how PHP versions are chosen here.
php_project_accepts() {
  local dir="$1" version="$2"
  python3 - "${dir}" "${version}" <<'PY'
import json, re, sys

directory, wanted = sys.argv[1], tuple(int(p) for p in sys.argv[2].split("."))

def parts(text):
    numbers = [int(n) for n in re.findall(r"\d+", text)][:3]
    return numbers + [0] * (3 - len(numbers)), len(numbers)

def single(c):
    c = c.strip().lstrip("v")
    if c in ("", "*"):
        return True
    m = re.match(r"^([<>]=?|==?|!=)\s*(.+)$", c)
    if m:
        op, (v, _) = m.group(1), parts(m.group(2))
        w, low = list(wanted) + [0], list(wanted) + [99]
        return {"<": tuple(w) < tuple(v), "<=": tuple(w) <= tuple(v), ">": tuple(low) > tuple(v),
                ">=": tuple(low) >= tuple(v), "=": tuple(wanted) == tuple(v[:2]), "==": tuple(wanted) == tuple(v[:2]),
                "!=": tuple(wanted) != tuple(v[:2])}[op]
    if c.startswith("^"):
        (a, b, _), _ = parts(c[1:])
        return wanted[0] == a and wanted >= (a, b)
    if c.startswith("~"):
        (a, b, _), n = parts(c[1:])
        return wanted == (a, b) if n >= 3 else (wanted[0] == a and wanted >= (a, b))
    if "*" in c or "x" in c.lower():
        (a, b, _), n = parts(c)
        return wanted[0] == a and (n < 2 or wanted[1] == b)
    (a, b, _), n = parts(c)
    return wanted == (a, b) if n >= 2 else wanted[0] == a

def accepts(constraint):
    for branch in re.split(r"\s*\|\|?\s*", constraint):
        if " - " in branch:
            low, high = branch.split(" - ", 1)
            (a, b, _), _ = parts(low)
            (c, d, _), _ = parts(high)
            if (a, b) <= wanted <= (c, d):
                return True
            continue
        branch = re.sub(r"([<>=!]=?)\s+", r"\1", branch.strip())
        if all(single(p) for p in re.split(r"\s*,\s*|\s+", branch) if p):
            return True
    return False

constraints = []
try:
    constraints.append(json.load(open(f"{directory}/composer.json")).get("require", {}).get("php", ""))
except (OSError, ValueError):
    pass
try:
    lock = json.load(open(f"{directory}/composer.lock"))
    for package in lock.get("packages", []):
        constraints.append(package.get("require", {}).get("php", ""))
except (OSError, ValueError):
    pass
sys.exit(0 if all(accepts(c) for c in constraints if c) else 1)
PY
}

# Suggested version: the newest available the project accepts (composer.json and composer.lock), leaving out a
# brand-new branch while the extensions catch up; without any match, the newest available.
php_suggest() {
  local dir="$1" v
  for v in "${PHP_AVAILABLE[@]}"; do
    [[ "${v}" == "8.6" && ${#PHP_AVAILABLE[@]} -gt 1 ]] && continue
    php_project_accepts "${dir}" "${v}" && { echo "${v}"; return; }
  done
  if [[ " ${PHP_AVAILABLE[*]} " == *" 8.6 "* ]] && php_project_accepts "${dir}" 8.6; then echo 8.6; return; fi
  for v in "${PHP_AVAILABLE[@]}"; do [[ "${v}" != "8.6" ]] && { echo "${v}"; return; }; done
  echo "${PHP_AVAILABLE[0]}"
}

php_package_exists() { [[ -n "$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" {print $2}')" ]]; }

# Adds ondrej/php when it has packages for this Ubuntu, then fills PHP_AVAILABLE with the versions apt can install
php_repository() {
  local packages_url
  packages_url="https://ppa.launchpadcontent.net/ondrej/php/ubuntu/dists/${OS_CODENAME}/main/binary-$(dpkg --print-architecture)/Packages.gz"
  if ! grep -rqs "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/; then
    # (the whole list is read: stopping at the first match would break the pipe and count as a failure)
    if [[ "$(curl -fsSL "${packages_url}" 2>/dev/null | gunzip 2>/dev/null | grep -c '^Package: php' || true)" -gt 0 ]]; then
      LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >/dev/null
      apt-get update -y >/dev/null
    else
      warn "$(t php_ppa_empty "${OS_VERSION}")"
    fi
  fi
  PHP_AVAILABLE=()
  local v
  for v in "${PHP_VERSIONS[@]}"; do php_package_exists "php${v}-fpm" && PHP_AVAILABLE+=("${v}"); done
  [[ ${#PHP_AVAILABLE[@]} -gt 0 ]] || die "$(t php_none_available "${OS_VERSION}")"
}

# php_install VERSION [extra extensions...]
php_install() {
  local v="$1"; shift
  say "$(t php_title "${v}")"
  php_package_exists "php${v}-fpm" || die "$(t php_version_missing "${v}" "${OS_VERSION}")"

  local wanted=(fpm cli common mysql mbstring xml curl zip gd intl bcmath readline opcache redis "$@")
  # Before 8.0 json was a separate package
  dpkg --compare-versions "${v}" lt 8.0 && wanted+=(json)
  local packages=() missing=() ext
  for ext in "${wanted[@]}"; do
    if php_package_exists "php${v}-${ext}"; then packages+=("php${v}-${ext}")
    else missing+=("${ext}"); fi
  done
  apt-get install -y "${packages[@]}"
  # Extensions compiled inside PHP (opcache in 8.5+) have no package: only warn about the ones really missing
  for ext in "${missing[@]}"; do
    grep -qiw "${ext}" <<< "$("/usr/bin/php${v}" -m 2>/dev/null)" || warn "$(t php_ext_missing "${ext}" "${v}")"
  done

  local cli fpm
  cli="$("/usr/bin/php${v}" -r 'echo PHP_VERSION;')"
  fpm="$("/usr/sbin/php-fpm${v}" -v | head -n 1 | awk '{print $2}')"
  ok "PHP ${cli} (CLI) · ${fpm} (FPM)"
  php_is_eol "${v}" && warn "$(t php_eol_warning "${v}" "$(php_eol_date "${v}")")"
  php_ini "${v}"
}

# Same safety and limits for every version; options a version does not know are left out
php_ini() {
  local v="$1" sapi file
  for sapi in fpm cli; do
    file="/etc/php/${v}/${sapi}/conf.d/98-server-kit.ini"
    {
      echo "; server-kit: safety and limits"
      echo "expose_php = Off"
      echo "cgi.fix_pathinfo = 0"
      echo "upload_max_filesize = 20M"
      echo "post_max_size = 25M"
      echo "memory_limit = 512M"
      echo "max_execution_time = 60"
      echo "session.upload_progress.enabled = Off"
      echo "zend.exception_ignore_args = On"
      dpkg --compare-versions "${v}" ge 8.5 && echo "fatal_error_backtraces = Off"
      if [[ "${sapi}" == "fpm" ]]; then
        echo "opcache.enable = 1"
        echo "opcache.memory_consumption = 192"
        echo "opcache.interned_strings_buffer = 16"
        echo "opcache.max_accelerated_files = 20000"
        echo "opcache.validate_timestamps = 1"
        echo "opcache.revalidate_freq = 2"
      fi
    } > "${file}"
  done
}

# PHP-FPM pool of a system: its own user, its own socket, sized by the machine (see sizing.sh)
php_pool() {
  local v="$1" site="$2" user="$3" children="$4"
  # One system per server: Ubuntu's sample pool ("www") and PHP versions used before (changed version) only take
  # memory, so they are switched off (the packages stay; changing back turns them on again)
  rm -f "/etc/php/${v}/fpm/pool.d/www.conf" "/etc/php/"*/fpm/pool.d/"${site}".conf
  local dir old
  for dir in /etc/php/*/fpm; do
    old="$(basename "$(dirname "${dir}")")"
    [[ "${old}" == "${v}" ]] && continue
    systemctl disable --now "php${old}-fpm" >/dev/null 2>&1 || true
  done
  cat > "/etc/php/${v}/fpm/pool.d/${site}.conf" <<EOF
; server-kit: ${site}
[${site}]
user = ${user}
group = ${user}
listen = /run/php/${site}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660
; Only .php files run (not .phar or others someone manages to put in the folder)
security.limit_extensions = .php
; Sized by the server memory; ondemand = no visits, no memory used
pm = ondemand
pm.max_children = ${children}
pm.process_idle_timeout = 20s
pm.max_requests = 500
EOF
  systemctl enable "php${v}-fpm" >/dev/null 2>&1
  systemctl restart "php${v}-fpm"
}

# Points every pool of the server to the size of today's machine (after a bigger plan or a new system)
php_resize_all() {
  local per_site="$1" pool
  for pool in /etc/php/*/fpm/pool.d/*.conf; do
    grep -q "server-kit" "${pool}" 2>/dev/null || continue
    sed -i -E "s/^pm\.max_children = .*/pm.max_children = ${per_site}/" "${pool}"
  done
  local v
  for v in /etc/php/*/fpm; do
    v="$(echo "${v}" | cut -d/ -f4)"
    systemctl is-enabled --quiet "php${v}-fpm" 2>/dev/null && systemctl reload "php${v}-fpm" 2>/dev/null || true
  done
}
