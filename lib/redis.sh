#!/usr/bin/env bash
# Redis: fast memory for cache, sessions and queues of Laravel systems. One per server, only on 127.0.0.1, with a
# password. A Redis already configured keeps its password (other systems use it).

REDIS_CONF=/etc/redis/redis.conf
REDIS_PASS=""

redis_install() {
  say "$(t redis_title)"
  apt-get install -y redis-server >/dev/null
  REDIS_PASS="$(awk '/^requirepass / {print $2}' "${REDIS_CONF}" | tail -n 1)"
  if [[ -z "${REDIS_PASS}" ]]; then
    REDIS_PASS="$(openssl rand -hex 24)"
    echo "requirepass ${REDIS_PASS}" >> "${REDIS_CONF}"
  fi
  # One bind line, only inside the server (IPv4 only: the "-::1" form needs Redis 7, Ubuntu 22.04 has 6.0)
  sed -i -E '/^#? *bind [0-9*:-]/d' "${REDIS_CONF}"
  echo "bind 127.0.0.1" >> "${REDIS_CONF}"
  sed -i -E 's/^#? *protected-mode .*/protected-mode yes/' "${REDIS_CONF}"
  redis_resize
  systemctl enable redis-server >/dev/null 2>&1
  systemctl restart redis-server
  ok "$(t redis_ok "${REDIS_MB}")"
}

# Memory ceiling: never lowered by this installer (another tool may have set a bigger one)
redis_resize() {
  [[ -f "${REDIS_CONF}" ]] || return 0
  local current raw
  raw="$(awk '/^maxmemory / {print tolower($2)}' "${REDIS_CONF}" | tail -n 1)"
  case "${raw}" in
    *gb) current=$(( ${raw%gb} * 1024 )) ;;
    *mb) current="${raw%mb}" ;;
    "") current="" ;;
    *) current=$(( $(echo "${raw}" | tr -dc '0-9') / 1048576 )) ;;
  esac
  if [[ -z "${current}" ]]; then
    echo "maxmemory ${REDIS_MB}mb" >> "${REDIS_CONF}"
  elif (( current < REDIS_MB )); then
    sed -i -E "s/^maxmemory .*/maxmemory ${REDIS_MB}mb/" "${REDIS_CONF}"
  fi
  grep -qE '^maxmemory-policy ' "${REDIS_CONF}" || echo "maxmemory-policy allkeys-lru" >> "${REDIS_CONF}"
}
