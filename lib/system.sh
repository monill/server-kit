#!/usr/bin/env bash
# The machine: system version, checks before installing, base packages, firewall, swap and automatic updates.

OS_ID=""; OS_VERSION=""; OS_CODENAME=""
RAM_MB=0; CPUS=1; DISK_FREE_GB=0

system_detect() {
  # shellcheck source=/dev/null
  . /etc/os-release
  OS_ID="${ID:-}"; OS_VERSION="${VERSION_ID:-}"; OS_CODENAME="${VERSION_CODENAME:-}"
  [[ "${OS_ID}" == "ubuntu" ]] || die "$(t os_not_ubuntu)"
  case "${OS_VERSION}" in
    22.04|24.04|26.04) ;;
    *) warn "$(t os_untested "${OS_VERSION}")" ;;
  esac
  RAM_MB="$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
  CPUS="$(nproc)"
  DISK_FREE_GB="$(df -BG --output=avail / | tail -n 1 | tr -dc '0-9')"
}

# The checks before anything is installed. Hard limits stop; the rest are counted and confirmed once.
system_check() {
  local domain="${1:-}" test_mode="${2:-0}" swap_mb
  say "$(t check_title)"
  CHECK_PROBLEMS=0
  info "Ubuntu ${OS_VERSION} (${OS_CODENAME}) · $(uname -m)"

  (( RAM_MB >= 900 )) || die "$(t ram_too_low "${RAM_MB}")"
  if (( RAM_MB >= 1800 )); then ok "$(t ram_ok "${RAM_MB}")"; else problem "$(t ram_low "${RAM_MB}")"; fi
  if (( CPUS >= 2 )); then ok "$(t cpu_ok "${CPUS}")"; else problem "$(t cpu_low "${CPUS}")"; fi
  (( DISK_FREE_GB >= 5 )) || die "$(t disk_too_low "${DISK_FREE_GB}")"
  if (( DISK_FREE_GB >= 15 )); then ok "$(t disk_ok "${DISK_FREE_GB}")"; else problem "$(t disk_low "${DISK_FREE_GB}")"; fi
  case "$(uname -m)" in x86_64|aarch64) ;; *) die "$(t arch_unsupported "$(uname -m)")" ;; esac

  # Clock: HTTPS certificates, login codes and queues depend on the right time
  # (a server that just booted may take a few seconds to sync)
  local tries=0
  until [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]] || (( tries >= 15 )); do
    (( tries == 0 )) && { timedatectl set-ntp true 2>/dev/null || true; }
    sleep 2; tries=$((tries + 1))
  done
  if (( tries < 15 )); then ok "$(t clock_ok)"; else problem "$(t clock_fixed)"; fi

  # Another web server (Apache comes with some images) holds ports 80 and 443
  if systemctl is-active --quiet apache2 2>/dev/null; then
    problem "$(t apache_off)"
    systemctl disable --now apache2 >/dev/null 2>&1 || true
  fi
  local busy
  busy="$(ss -ltnpH '( sport = :80 or sport = :443 )' 2>/dev/null | grep -v nginx || true)"
  [[ -z "${busy}" ]] || die "$(t ports_busy "${busy}")"
  ok "$(t ports_ok)"

  command -v curl >/dev/null || { apt-get update -y >/dev/null && apt-get install -y curl >/dev/null; }
  local host
  for host in github.com ppa.launchpadcontent.net repo.mysql.com acme-v02.api.letsencrypt.org; do
    if curl -sS -o /dev/null --max-time 10 "https://${host}" 2>/dev/null; then ok "$(t net_ok "${host}")"
    else problem "$(t net_fail "${host}")"; fi
  done

  # The domain must point here before Let's Encrypt (Cloudflare: grey cloud until HTTPS is done)
  if [[ -n "${domain}" && "${test_mode}" -eq 0 ]]; then
    local public_ip domain_ips
    public_ip="$(curl -4 -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
    domain_ips="$(getent ahostsv4 "${domain}" 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ' ' || true)"
    if [[ -z "${domain_ips}" ]]; then problem "$(t dns_missing "${domain}" "${public_ip:-?}")"
    elif [[ -n "${public_ip}" && " ${domain_ips}" == *" ${public_ip} "* ]]; then ok "$(t dns_ok "${domain}" "${public_ip}")"
    else problem "$(t dns_other "${domain}" "${domain_ips}" "${public_ip:-?}")"; fi
  fi

  swap_mb="$(awk '/^SwapTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
  ok "$(t swap_now "${swap_mb}")"

  if (( CHECK_PROBLEMS > 0 )); then
    confirm_warning "$(t check_continue "${CHECK_PROBLEMS}")" || die "$(t check_cancelled)"
  fi
}

# Base packages, time zone untouched (UTC is the safe default for servers)
system_base() {
  say "$(t base_title)"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get upgrade -y
  apt-get install -y software-properties-common ca-certificates curl git unzip acl gnupg openssl cron ufw fail2ban \
    unattended-upgrades whiptail
}

system_firewall() {
  say "$(t firewall_title)"
  ufw allow OpenSSH >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null
  systemctl enable --now fail2ban >/dev/null 2>&1
  ok "$(t firewall_ok)"
}

# Swap: a reserve on the disk for peaks (builds, imports). Without it, when memory runs out Linux kills a process,
# usually MySQL. Tops it up to 2 GB (4 GB above 4.5 GB of RAM); swappiness 10 = only when really needed.
system_swap() {
  local swap_mb want add
  swap_mb="$(awk '/^SwapTotal:/ {print int($2 / 1024)}' /proc/meminfo)"
  want=$(( RAM_MB > 4500 ? 4096 : 2048 ))
  if (( swap_mb + 256 < want )) && [[ ! -f /swapfile ]] && (( DISK_FREE_GB * 1024 > (want - swap_mb) * 4 )); then
    add=$(( want - swap_mb ))
    fallocate -l "${add}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="${add}" status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -qF '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "$(t swap_added "${add}")"
  fi
  echo "vm.swappiness = 10" > /etc/sysctl.d/90-server-kit.conf
  sysctl -q -p /etc/sysctl.d/90-server-kit.conf || true
}

# Security updates on their own: Ubuntu, plus the PHP and MySQL repositories this installer adds
system_auto_updates() {
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  cat > /etc/apt/apt.conf.d/52server-kit <<'EOF'
// server-kit: fixes from the PHP (ondrej/php) and MySQL (repo.mysql.com) repositories install on their own
Unattended-Upgrade::Allowed-Origins:: "LP-PPA-ondrej-php:${distro_codename}";
Unattended-Upgrade::Origins-Pattern:: "origin=MySQL,codename=${distro_codename}";
EOF
  systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
}

# GitHub's SSH key, checked against the fingerprint GitHub publishes (docs.github.com › GitHub's SSH key fingerprints)
github_known_host() {
  local home="$1" user="$2" key
  key="$(ssh-keyscan -t ed25519 github.com 2>/dev/null)"
  [[ "$(echo "${key}" | ssh-keygen -lf - | awk '{print $2}')" == "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU" ]] \
    || die "$(t github_key_bad)"
  install -d -m 700 -o "${user}" -g "${user}" "${home}/.ssh"
  grep -qF "${key}" "${home}/.ssh/known_hosts" 2>/dev/null || echo "${key}" >> "${home}/.ssh/known_hosts"
  chown "${user}:${user}" "${home}/.ssh/known_hosts"
}
