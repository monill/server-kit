#!/usr/bin/env bash
# Messages in the chosen language. Each text lives in lang/<code>.sh as MSG[key]; t key [values...] prints it with
# the values in place of %s (printf rules).

declare -gA MSG=()
SK_LANG="en"

i18n_load() {
  local file="${SK_DIR}/lang/$1.sh"
  [[ -f "${file}" ]] || return 1
  # shellcheck source=/dev/null
  source "${file}"
  SK_LANG="$1"
}

i18n_init() {
  local wanted="$1"
  # English first: a key missing in another language still shows something readable
  i18n_load en
  if [[ -z "${wanted}" ]]; then
    case "${LANG:-}" in pt*) wanted="pt_BR" ;; *) wanted="" ;; esac
    if [[ ${UI_INTERACTIVE} -eq 1 ]]; then
      choose wanted "Language / Idioma" "${wanted:-pt_BR}" pt_BR "Português (Brasil)" en "English"
    fi
  fi
  [[ -n "${wanted}" && "${wanted}" != "en" ]] && i18n_load "${wanted}"
  return 0
}

# t key [values...]
t() {
  local key="$1"; shift
  local text="${MSG[${key}]:-${key}}"
  # shellcheck disable=SC2059
  printf -- "${text}" "$@"
}
