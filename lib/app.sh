#!/usr/bin/env bash
# The system itself: name, user, code from GitHub (public or private), type (Laravel or plain PHP) and public folder.

# Site name from the repository: "https://github.com/monill/travianT4.4.git" → "traviant4-4"
app_name_from_repo() {
  local name="${1%/}"; name="${name##*/}"; name="${name%.git}"
  name="$(echo "${name}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  echo "${name:0:28}"
}

# https or git@ address → the ssh one (private repositories are read with a deploy key)
app_ssh_url() {
  local url="$1"
  if [[ "${url}" =~ ^https://github\.com/([^/]+)/([^/]+)$ ]]; then
    echo "git@github.com:${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}.git"
  else
    echo "${url}"
  fi
}

app_user_create() {
  local user="$1" dir="$2"
  if ! id "${user}" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "${user}"
  fi
  usermod -aG www-data "${user}"
  APP_HOME="$(getent passwd "${user}" | cut -d: -f6)"
  install -d -o "${user}" -g www-data -m 750 "${dir}"
}

# Clones the code. Public: straight away. Private: shows a deploy key (read only) to add on GitHub and waits.
app_clone() {
  local repo="$1" branch="$2" dir="$3" user="$4" url="$1" branch_opt=()
  [[ -n "${branch}" ]] && branch_opt=(--branch "${branch}")
  if [[ -d "${dir}/.git" ]]; then
    ok "$(t clone_exists "${dir}")"
    return 0
  fi
  say "$(t clone_title "${repo}")"
  if ! sudo -u "${user}" -H env GIT_TERMINAL_PROMPT=0 git ls-remote "${url}" >/dev/null 2>&1; then
    # Private (or an ssh address): deploy key of this system's user
    url="$(app_ssh_url "${repo}")"
    local key="${APP_HOME}/.ssh/id_ed25519"
    github_known_host "${APP_HOME}" "${user}"
    [[ -f "${key}" ]] || sudo -u "${user}" ssh-keygen -q -t ed25519 -N "" -C "${user}@$(hostname)" -f "${key}"
    if ! sudo -u "${user}" -H git ls-remote "${url}" >/dev/null 2>&1; then
      echo
      info "$(t deploy_key_info)"
      echo
      cat "${key}.pub"
      echo
      pause "$(t deploy_key_wait)"
      sudo -u "${user}" -H git ls-remote "${url}" >/dev/null 2>&1 || die "$(t clone_fail "${repo}")"
    fi
  fi
  # The folder was created empty for the user; git wants it empty
  rmdir "${dir}" 2>/dev/null || true
  install -d -o "${user}" -g www-data -m 750 "$(dirname "${dir}")" 2>/dev/null || true
  sudo -u "${user}" -H git clone "${branch_opt[@]}" "${url}" "${dir}" || die "$(t clone_fail "${repo}")"
  chown -R "${user}:www-data" "${dir}"
  chmod 750 "${dir}"
  ok "$(t clone_ok "$(sudo -u "${user}" git -C "${dir}" log -1 --format='%h %cs %s' | cut -c1-70)")"
}

app_detect_type() {
  local dir="$1"
  if [[ -f "${dir}/artisan" ]] && grep -qs '"laravel/framework"' "${dir}/composer.json"; then echo laravel
  else echo php; fi
}

# Public folder: Laravel = public; plain PHP = public/, public_html/, web/ or www/ when it has an index.php, otherwise
# the root of the project (then hidden files and the usual private files are blocked in Nginx)
app_detect_docroot() {
  local dir="$1" type="$2" candidate
  if [[ "${type}" == "laravel" ]]; then echo "${dir}/public"; return; fi
  for candidate in public public_html web www htdocs; do
    [[ -f "${dir}/${candidate}/index.php" ]] && { echo "${dir}/${candidate}"; return; }
  done
  echo "${dir}"
}

# Extensions required in composer.json ("ext-gd": "*") → names of PHP packages
app_required_extensions() {
  local dir="$1"
  [[ -f "${dir}/composer.json" ]] || return 0
  grep -oE '"ext-[a-z0-9_]+"' "${dir}/composer.json" | tr -d '"' | sed 's/^ext-//' | sort -u \
    | grep -vxE 'json|pdo|pdo_mysql|mysqli|mysqlnd|ctype|fileinfo|tokenizer|openssl|session|filter|hash|pcre|spl|standard|dom|simplexml|xmlwriter|xmlreader|iconv|phar|posix|sockets|exif|calendar|ftp|gettext|shmop|sysvmsg|sysvsem|sysvshm' || true
}
