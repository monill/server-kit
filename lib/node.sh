#!/usr/bin/env bash
# Node.js, only to build the screens of systems that have a "build" script in package.json (Vite, Mix...).

NODE_MAJOR=22

node_needed() { [[ -f "$1/package.json" ]] && grep -qE '"build"[[:space:]]*:' "$1/package.json"; }

node_install() {
  if command -v node >/dev/null && (( $(node -v | tr -d v | cut -d. -f1) >= NODE_MAJOR )); then return 0; fi
  say "$(t node_title "${NODE_MAJOR}")"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - >/dev/null
  apt-get install -y nodejs >/dev/null
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
