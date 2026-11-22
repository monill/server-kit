#!/usr/bin/env bash
# Composer 2 (runs on PHP 7.2.5 and up), checked against its published signature before use.

composer_install() {
  local v="$1"
  [[ -x /usr/local/bin/composer ]] && return 0
  say "$(t composer_title "2")"
  local expected actual
  expected="$(curl -fsSL https://composer.github.io/installer.sig)"
  curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
  actual="$("/usr/bin/php${v}" -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"
  [[ "${expected}" == "${actual}" ]] || die "$(t composer_bad)"
  "/usr/bin/php${v}" /tmp/composer-setup.php --quiet --install-dir=/usr/local/bin --filename=composer
  rm -f /tmp/composer-setup.php
}

# composer_run DIR USER PHP_VERSION
composer_run() {
  local dir="$1" user="$2" v="$3"
  [[ -f "${dir}/composer.json" ]] || return 0
  composer_install "${v}"
  say "$(t composer_deps)"
  sudo -u "${user}" -H bash -c "cd '${dir}' && /usr/bin/php${v} /usr/local/bin/composer install --no-dev --optimize-autoloader --no-interaction" \
    || die "$(t composer_failed "${v}")"
}
