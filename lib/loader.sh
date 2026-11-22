#!/usr/bin/env bash
# Loads every library and runs the chosen action.

SK_CONF_DIR="/etc/server-kit"
SK_LOG_DIR="/var/log/server-kit"

for sk_lib in colors i18n ui system sizing state php database redis node composer app laravel nginx supervisor actions; do
  # shellcheck source=/dev/null
  source "${SK_DIR}/lib/${sk_lib}.sh"
done
unset sk_lib

# Options from the command line (empty = ask)
OPT_REPO=""; OPT_BRANCH=""; OPT_DOMAIN=""; OPT_EMAIL=""; OPT_PHP=""; OPT_NODE=""; OPT_DB=""; OPT_TEST=0; OPT_LANG=""; OPT_PLAIN=0; OPT_YES=0
ACTION=""; RESIZE_IF_CHANGED=0

sk_parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      install|update|remove|check|resize) ACTION="$1" ;;
      --if-changed) RESIZE_IF_CHANGED=1 ;;
      --mysql) OPT_MYSQL="${2:-}"; shift ;;
      --repo) OPT_REPO="${2:-}"; shift ;;
      --branch) OPT_BRANCH="${2:-}"; shift ;;
      --domain) OPT_DOMAIN="${2:-}"; shift ;;
      --email) OPT_EMAIL="${2:-}"; shift ;;
      --php) OPT_PHP="${2:-}"; shift ;;
      --node) OPT_NODE="${2:-}"; shift ;;
      --db) OPT_DB="${2:-}"; shift ;;
      --test) OPT_TEST=1 ;;
      --lang) OPT_LANG="${2:-}"; shift ;;
      --plain) OPT_PLAIN=1 ;;
      --yes) OPT_YES=1 ;;
      -h|--help) sed -n '2,23p' "${SK_DIR}/install.sh" | sed 's/^# \{0,1\}//'; exit 0 ;;
      -v|--version) echo "server-kit ${SK_VERSION}"; exit 0 ;;
      -*) echo "Unknown option: $1 (see --help)" >&2; exit 1 ;;
      *) echo "Unknown argument: $1 (see --help)" >&2; exit 1 ;;
    esac
    shift
  done
}

sk_on_error() {
  trap - ERR
  echo "${C_RED:-}$(t error 2>/dev/null || echo Error): ${4}() line ${2}: ${3} (exit ${1})${C_OFF:-}" >&2
  echo "Log: ${SK_LOG:-}" >&2
  exit "${1}"
}

sk_main() {
  sk_parse_args "$@"
  [[ ${EUID} -eq 0 ]] || { echo "Run as root: sudo ./install.sh" >&2; exit 1; }
  # Commands run as the system's user must not start inside a folder that user cannot read
  cd /
  # Any unexpected failure stops with the line and the command, never silently
  set -E
  trap 'sk_on_error $? ${LINENO} "${BASH_COMMAND}" "${FUNCNAME[0]:-main}"' ERR

  install -d -m 700 "${SK_CONF_DIR}"
  install -d -m 750 "${SK_LOG_DIR}"
  # Everything shown on the screen also goes to a log (passwords are never printed)
  SK_LOG="${SK_LOG_DIR}/$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "${SK_LOG}") 2>&1

  ui_init
  i18n_init "${OPT_LANG}"
  ui_banner

  if [[ -z "${ACTION}" ]]; then
    choose ACTION "$(t menu_title)" install \
      install "$(t menu_install)" \
      update "$(t menu_update)" \
      remove "$(t menu_remove)" \
      check "$(t menu_check)" \
      resize "$(t menu_resize)" \
      quit "$(t menu_quit)"
  fi

  case "${ACTION}" in
    install) action_install ;;
    update) action_update ;;
    remove) action_remove ;;
    check) action_check ;;
    resize) action_resize ;;
    *) exit 0 ;;
  esac
}
