#!/usr/bin/env bash
# Supervisor keeps the background programs of Laravel systems running: queue workers and Reverb (real time).

supervisor_install() {
  command -v supervisorctl >/dev/null && return 0
  apt-get install -y supervisor >/dev/null
  systemctl enable --now supervisor >/dev/null 2>&1
}

# supervisor_site SITE DIR USER PHP WORKERS REVERB_PORT(empty = no Reverb)
supervisor_site() {
  local site="$1" dir="$2" user="$3" v="$4" workers="$5" reverb_port="$6"
  supervisor_install
  {
    echo "; server-kit: ${site}"
    echo "[program:${site}-queue]"
    echo "command=/usr/bin/php${v} ${dir}/artisan queue:work --sleep=3 --tries=3 --max-time=3600"
    echo "directory=${dir}"
    echo "user=${user}"
    echo "numprocs=${workers}"
    echo "process_name=%(program_name)s_%(process_num)02d"
    echo "autostart=true"
    echo "autorestart=true"
    echo "stopasgroup=true"
    echo "killasgroup=true"
    echo "stopwaitsecs=3600"
    echo "redirect_stderr=true"
    echo "stdout_logfile=${dir}/storage/logs/queue.log"
    echo "stdout_logfile_maxbytes=10MB"
    echo "stdout_logfile_backups=3"
    if [[ -n "${reverb_port}" ]]; then
      echo
      echo "[program:${site}-reverb]"
      echo "command=/usr/bin/php${v} ${dir}/artisan reverb:start --host=127.0.0.1 --port=${reverb_port}"
      echo "directory=${dir}"
      echo "user=${user}"
      echo "autostart=true"
      echo "autorestart=true"
      echo "stopasgroup=true"
      echo "killasgroup=true"
      echo "redirect_stderr=true"
      echo "stdout_logfile=${dir}/storage/logs/reverb.log"
      echo "stdout_logfile_maxbytes=10MB"
      echo "stdout_logfile_backups=3"
    fi
  } > "/etc/supervisor/conf.d/${site}.conf"
  supervisorctl reread >/dev/null
  supervisorctl update >/dev/null
  ok "$(t supervisor_ok "${workers}")"
}
