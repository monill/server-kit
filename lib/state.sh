#!/usr/bin/env bash
# What was installed, in /etc/server-kit/site.conf (no passwords): used to update, remove and resize later.
# One system per server.

SITE_FILE="${SK_CONF_DIR}/site.conf"
STATE_KEYS=(SITE REPO BRANCH DOMAIN PHP_VERSION APP_TYPE APP_DIR DOCROOT APP_USER DB_MODE DB_NAME DB_USER DB_HOST DB_PORT DB_CA NODE_VERSION TEST_MODE REVERB INSTALLED_AT)

state_exists() { [[ -f "${SITE_FILE}" ]]; }

state_save() {
  local key
  {
    echo "# server-kit: ${SITE} (written $(date -Iseconds))"
    for key in "${STATE_KEYS[@]}"; do printf '%s=%q\n' "${key}" "${!key:-}"; done
  } > "${SITE_FILE}"
  chmod 600 "${SITE_FILE}"
}

state_load() {
  state_exists || die "$(t site_none)"
  # shellcheck source=/dev/null
  source "${SITE_FILE}"
}
