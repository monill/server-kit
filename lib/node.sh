#!/usr/bin/env bash
# Node.js, only to build the screens of systems that have a "build" script in package.json (Vite, Mix...).
# Only LTS versions (the ones with long support), from NodeSource. Version 20 ended in April 2026.

NODE_VERSIONS=(26 24 22)

# End of support of each LTS (github.com/nodejs/Release)
node_eol_date() {
  case "$1" in 22) echo 2027-04-30 ;; 24) echo 2028-04-30 ;; 26) echo 2029-04-30 ;; *) echo 1970-01-01 ;; esac
}

node_needed() { [[ -f "$1/package.json" ]] && grep -qE '"build"[[:space:]]*:' "$1/package.json"; }

# Suggested version: the one in .nvmrc / .node-version, else the "engines" of package.json, else 24 (the LTS that
# most projects and build tools are tested with)
node_suggest() {
  local dir="$1" wanted="" constraint="" v
  [[ -f "${dir}/.nvmrc" ]] && wanted="$(grep -oE '[0-9]+' "${dir}/.nvmrc" | head -n 1 || true)"
  [[ -z "${wanted}" && -f "${dir}/.node-version" ]] && wanted="$(grep -oE '[0-9]+' "${dir}/.node-version" | head -n 1 || true)"
  if [[ -z "${wanted}" ]]; then
    constraint="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("engines",{}).get("node",""))' "${dir}/package.json" 2>/dev/null || true)"
    wanted="$(grep -oE '[0-9]+' <<< "${constraint}" | head -n 1 || true)"
    # ">=20" or "^20 || >=22": the minimum, so the newest LTS is fine; "^22" / "22.x": that one
    [[ "${constraint}" == *">"* || "${constraint}" == *"||"* ]] && wanted=24
  fi
  for v in "${NODE_VERSIONS[@]}"; do [[ "${v}" == "${wanted}" ]] && { echo "${v}"; return; }; done
  echo 24
}

node_menu() {
  local suggested="$1" v label args=()
  for v in "${NODE_VERSIONS[@]}"; do
    label="$(t node_label "$(node_eol_date "${v}")")"
    [[ "${v}" == "${suggested}" ]] && label="${label} · $(t php_label_suggested)"
    args+=("${v}" "${label}")
  done
  NODE_VERSION="${OPT_NODE}"
  choose NODE_VERSION "$(t node_choose)" "${suggested}" "${args[@]}"
}

# node_install MAJOR — installs it, or switches to it when another version is on the server
node_install() {
  local major="$1"
  if command -v node >/dev/null && [[ "$(node -v | tr -d v | cut -d. -f1)" == "${major}" ]]; then return 0; fi
  say "$(t node_title "${major}")"
  curl -fsSL "https://deb.nodesource.com/setup_${major}.x" | bash - >/dev/null
  apt-get install -y --allow-downgrades "nodejs=${major}.*" >/dev/null
  ok "Node $(node -v)"
}

# node_build DIR USER
node_build() {
  local dir="$1" user="$2"
  say "$(t node_build)"
  if [[ -f "${dir}/package-lock.json" ]]; then
    sudo -u "${user}" -H bash -c "cd '${dir}' && npm ci --no-audit --no-fund"
  else
    sudo -u "${user}" -H bash -c "cd '${dir}' && npm install --no-audit --no-fund"
  fi
  sudo -u "${user}" -H bash -c "cd '${dir}' && npm run build"
}
