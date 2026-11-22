#!/usr/bin/env bash
# Screen output and questions. With a terminal and whiptail (it comes with Ubuntu Server), questions are menus and
# boxes; with --plain, SK_PLAIN=1 or no terminal, plain questions on the line. Everything a question asks can also
# come from the command line, and then it is not asked.

UI_INTERACTIVE=0
UI_TUI=0
CHECK_PROBLEMS=0

ui_init() {
  [[ -t 0 ]] && UI_INTERACTIVE=1
  if [[ ${UI_INTERACTIVE} -eq 1 && ${OPT_PLAIN} -eq 0 && -z "${SK_PLAIN:-}" && -e /dev/tty ]] && command -v whiptail >/dev/null; then
    UI_TUI=1
  fi
}

ui_banner() {
  echo
  echo "${C_CYAN}${C_BOLD}  server-kit ${SK_VERSION}${C_OFF}"
  echo "${C_GRAY}  Laravel / PHP · Nginx · PHP-FPM · MySQL · Redis · HTTPS${C_OFF}"
}

say() { echo; echo "${C_BLUE}==> $*${C_OFF}"; }
info() { echo "    $*"; }
ok() { echo "   ${C_GREEN}✓${C_OFF} $*"; }
warn() { echo "   ${C_YELLOW}!${C_OFF} $*"; }
# A problem found while checking: counted, and confirmed once at the end of the check
problem() { echo "   ${C_YELLOW}!${C_OFF} $*"; CHECK_PROBLEMS=$((CHECK_PROBLEMS + 1)); }
die() { echo; echo "${C_RED}$(t error): $*${C_OFF}" >&2; exit 1; }

# ask VAR "question" [default] — keeps VAR when it already has a value (command line)
ask() {
  local -n _ask_var="$1"; local question="$2" default="${3:-}" answer=""
  [[ -n "${_ask_var}" ]] && return 0
  if [[ ${UI_INTERACTIVE} -eq 0 ]]; then
    [[ -n "${default}" ]] || die "$(t needs_answer "${question}")"
    _ask_var="${default}"; return 0
  fi
  if [[ ${UI_TUI} -eq 1 ]]; then
    answer="$(whiptail --title "server-kit" --inputbox "${question}" 10 72 "${default}" 2>&1 >/dev/tty)" || die "$(t cancelled)"
  else
    read -rp "${question}${default:+ [${default}]}: " answer </dev/tty
  fi
  _ask_var="${answer:-${default}}"
}

# ask_secret VAR "question" — nothing shown on the screen nor written to the log
ask_secret() {
  local -n _secret_var="$1"; local question="$2" answer=""
  [[ -n "${_secret_var}" ]] && return 0
  [[ ${UI_INTERACTIVE} -eq 1 ]] || die "$(t needs_answer "${question}")"
  if [[ ${UI_TUI} -eq 1 ]]; then
    answer="$(whiptail --title "server-kit" --passwordbox "${question}" 10 72 2>&1 >/dev/tty)" || die "$(t cancelled)"
  else
    read -rsp "${question}: " answer </dev/tty; echo >/dev/tty
  fi
  _secret_var="${answer}"
}

# choose VAR "title" default tag "description" [tag "description"...]
choose() {
  local -n _choose_var="$1"; local title="$2" default="$3"; shift 3
  local tags=() descriptions=() answer="" i
  while [[ $# -gt 0 ]]; do tags+=("$1"); descriptions+=("$2"); shift 2; done
  if [[ -n "${_choose_var}" ]]; then
    for i in "${tags[@]}"; do [[ "${i}" == "${_choose_var}" ]] && return 0; done
    die "$(t invalid_choice "${_choose_var}" "${tags[*]}")"
  fi
  if [[ ${UI_INTERACTIVE} -eq 0 ]]; then _choose_var="${default}"; return 0; fi
  if [[ ${UI_TUI} -eq 1 ]]; then
    local items=()
    for i in "${!tags[@]}"; do items+=("${tags[$i]}" "${descriptions[$i]}"); done
    answer="$(whiptail --title "server-kit" --default-item "${default}" --menu "${title}" 22 78 12 "${items[@]}" 2>&1 >/dev/tty)" || die "$(t cancelled)"
  else
    echo >/dev/tty
    echo "${title}" >/dev/tty
    for i in "${!tags[@]}"; do
      printf '  %2d) %-10s %s\n' $((i + 1)) "${tags[$i]}" "${descriptions[$i]}" >/dev/tty
    done
    local number=""
    while true; do
      read -rp "$(t choose_number) [${default}]: " number </dev/tty
      [[ -z "${number}" ]] && { answer="${default}"; break; }
      if [[ "${number}" =~ ^[0-9]+$ ]] && (( number >= 1 && number <= ${#tags[@]} )); then answer="${tags[$((number - 1))]}"; break; fi
      for i in "${tags[@]}"; do [[ "${i}" == "${number}" ]] && answer="${i}"; done
      [[ -n "${answer}" ]] && break
    done
  fi
  _choose_var="${answer}"
}

# confirm_warning "question" — like confirm, but --yes answers yes (warnings, never deletions)
confirm_warning() {
  [[ ${OPT_YES} -eq 1 ]] && { warn "$1 → $(t yes_by_option)"; return 0; }
  # Without a terminal the answer is "no": the question is shown, so the reason to stop is on the screen
  [[ ${UI_INTERACTIVE} -eq 1 ]] || { warn "$1 → $(t no_without_terminal)"; return 1; }
  confirm "$1" n
}

# confirm "question" [y|n] — returns 0 for yes. Without a terminal, the default answer
confirm() {
  local question="$1" default="${2:-n}" answer=""
  if [[ ${UI_INTERACTIVE} -eq 0 ]]; then [[ "${default}" == "y" ]]; return; fi
  if [[ ${UI_TUI} -eq 1 ]]; then
    local flag=(); [[ "${default}" == "n" ]] && flag=(--defaultno)
    whiptail --title "server-kit" "${flag[@]}" --yesno "${question}" 12 72 >/dev/tty 2>&1
    return
  fi
  local hint; [[ "${default}" == "y" ]] && hint="S/n" || hint="s/N"; [[ "${SK_LANG}" == "en" ]] && hint="${hint/S/Y}" && hint="${hint/s/y}"
  read -rp "${question} [${hint}] " answer </dev/tty
  answer="${answer:-${default}}"
  [[ "${answer}" =~ ^[sSyY] ]]
}

# pause "message" — waits for Enter (deploy key, DNS...)
pause() {
  [[ ${UI_INTERACTIVE} -eq 1 ]] || return 0
  read -rp "$1 " _ </dev/tty
}
