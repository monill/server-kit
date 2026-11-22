#!/usr/bin/env bash
# Nginx (Ubuntu's, it receives security fixes) and HTTPS: Let's Encrypt with a real domain, a self-signed certificate
# with --test (virtual machine without a domain).

nginx_install() {
  say "$(t nginx_title)"
  if ! command -v nginx >/dev/null; then
    apt-get install -y nginx >/dev/null
    rm -f /etc/nginx/sites-enabled/default
  fi
  # Hides the version and keeps gzip on for text (the default list leaves out JSON, JS and CSS). Only what the
  # nginx.conf of this Ubuntu does not set already (26.04 sets some of them; a repeated one stops Nginx)
  local directive value
  {
    echo "# server-kit: shared by every site"
    while read -r directive value; do
      grep -qE "^[[:space:]]*${directive}[[:space:]]" /etc/nginx/nginx.conf || echo "${directive} ${value}"
    done <<'EOF_DIRECTIVES'
server_tokens off;
gzip on;
gzip_vary on;
gzip_comp_level 5;
gzip_min_length 1024;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml image/svg+xml;
EOF_DIRECTIVES
  } > /etc/nginx/conf.d/server-kit.conf
  systemctl enable nginx >/dev/null 2>&1
}

# A catch-all site that answers 444 (closes) for requests by IP or unknown names: bots scanning addresses never
# reach a real system
nginx_default_server() {
  [[ -f /etc/nginx/sites-available/000-default-deny ]] && return 0
  install -d -m 700 /etc/nginx/ssl
  [[ -f /etc/nginx/ssl/default.crt ]] || openssl req -x509 -nodes -newkey rsa:2048 -days 3650 -subj "/CN=default" \
    -keyout /etc/nginx/ssl/default.key -out /etc/nginx/ssl/default.crt >/dev/null 2>&1
  cat > /etc/nginx/sites-available/000-default-deny <<'EOF'
# server-kit: requests that match no site are closed
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    ssl_certificate /etc/nginx/ssl/default.crt;
    ssl_certificate_key /etc/nginx/ssl/default.key;
    server_name _;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 444; }
}
EOF
  ln -sf /etc/nginx/sites-available/000-default-deny /etc/nginx/sites-enabled/000-default-deny
}

# nginx_site SITE DOMAIN DOCROOT TYPE [REVERB_PORT]
nginx_site() {
  local site="$1" domain="$2" root="$3" type="$4" reverb_port="${5:-}" names="$2" front="/index.php?\$query_string"
  # www. also answers for main domains (not for subdomains like app.example.com)
  [[ "$(echo "${domain}" | tr -cd '.' | wc -c)" -eq 1 ]] && names="${domain} www.${domain}"
  # Plain PHP without an index.php at the public folder: unknown addresses are a 404, not a page
  [[ "${type}" != "laravel" && ! -f "${root}/index.php" ]] && front="=404"

  {
    echo "# server-kit: ${site}"
    echo "server {"
    echo "    listen 80;"
    echo "    listen [::]:80;"
    echo "    server_name ${names};"
    echo "    root ${root};"
    echo "    index index.php index.html;"
    echo "    charset utf-8;"
    echo "    client_max_body_size 25M;"
    echo
    echo "    add_header X-Content-Type-Options \"nosniff\" always;"
    echo "    add_header X-Frame-Options \"SAMEORIGIN\" always;"
    echo "    add_header Referrer-Policy \"strict-origin-when-cross-origin\" always;"
    echo
    echo "    access_log /var/log/nginx/${site}.access.log;"
    echo "    error_log /var/log/nginx/${site}.error.log warn;"
    echo
    echo "    # Hidden files (.env, .git...) never leave the server; Let's Encrypt's folder is the exception"
    echo "    location ~ /\\.(?!well-known) { deny all; }"
    if [[ "${type}" != "laravel" ]]; then
      echo "    # Plain PHP: files that are not pages (settings, dumps, dependencies) stay private"
      echo "    location ~* \\.(sql|sqlite|bak|old|orig|swp|log|ini|conf|dist|lock|sh|yml|yaml|md)\$ { deny all; }"
      echo "    location ~ ^/(vendor|node_modules|storage|logs?|cache|tmp|temp|tests?)/.*\\.php\$ { deny all; }"
      echo "    location ~ ^/(composer\\.(json|lock)|package(-lock)?\\.json|phpunit\\.xml) { deny all; }"
    fi
    echo
    echo "    location / {"
    echo "        try_files \$uri \$uri/ ${front};"
    echo "    }"
    echo
    echo "    location = /favicon.ico { access_log off; log_not_found off; }"
    echo "    location = /robots.txt { access_log off; log_not_found off; }"
    echo "    location ~* \\.(?:css|js|mjs|woff2?|ttf|svg|png|jpe?g|gif|webp|avif|ico)\$ {"
    echo "        expires 30d;"
    echo "        access_log off;"
    echo "        try_files \$uri =404;"
    echo "    }"
    echo
    echo "    location ~ \\.php\$ {"
    echo "        try_files \$fastcgi_script_name =404;"
    echo "        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;"
    echo "        fastcgi_pass unix:/run/php/${site}.sock;"
    echo "        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;"
    echo "        fastcgi_param DOCUMENT_ROOT \$realpath_root;"
    echo "        include fastcgi_params;"
    echo "        fastcgi_hide_header X-Powered-By;"
    echo "        fastcgi_read_timeout 60s;"
    echo "    }"
    if [[ -n "${reverb_port}" ]]; then
      echo
      echo "    # Laravel Reverb (real time): the apps connect here and Nginx passes it on inside the server"
      echo "    location ~ ^/(app|apps)/ {"
      echo "        proxy_http_version 1.1;"
      echo "        proxy_set_header Host \$http_host;"
      echo "        proxy_set_header Scheme \$scheme;"
      echo "        proxy_set_header SERVER_PORT \$server_port;"
      echo "        proxy_set_header REMOTE_ADDR \$remote_addr;"
      echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
      echo "        proxy_set_header Upgrade \$http_upgrade;"
      echo "        proxy_set_header Connection \"Upgrade\";"
      echo "        proxy_read_timeout 120s;"
      echo "        proxy_pass http://127.0.0.1:${reverb_port};"
      echo "    }"
    fi
    echo "}"
  } > "/etc/nginx/sites-available/${site}"
  ln -sf "/etc/nginx/sites-available/${site}" "/etc/nginx/sites-enabled/${site}"
  nginx -t 2>&1 | tail -n 2 || die "$(t nginx_bad)"
  systemctl reload nginx
}

# HTTPS. Real domain: Let's Encrypt (renews on its own) with redirect from http. Test: self-signed, same redirect.
nginx_https() {
  local site="$1" domain="$2" email="$3" test_mode="$4" names=(-d "$2")
  [[ "$(echo "${domain}" | tr -cd '.' | wc -c)" -eq 1 ]] && names+=(-d "www.${domain}")
  say "$(t https_title)"
  if [[ "${test_mode}" -eq 1 ]]; then
    install -d -m 700 /etc/nginx/ssl
    openssl req -x509 -nodes -newkey rsa:2048 -days 825 -subj "/CN=${domain}" -addext "subjectAltName=DNS:${domain}" \
      -keyout "/etc/nginx/ssl/${site}.key" -out "/etc/nginx/ssl/${site}.crt" >/dev/null 2>&1
    local conf="/etc/nginx/sites-available/${site}"
    # http → https, and the same site on 443 with the self-signed certificate
    sed -i -E "0,/listen \[::\]:80;/s//listen [::]:80;\n    listen 443 ssl;\n    listen [::]:443 ssl;\n    ssl_certificate \/etc\/nginx\/ssl\/${site}.crt;\n    ssl_certificate_key \/etc\/nginx\/ssl\/${site}.key;\n    if (\$scheme = http) { return 301 https:\/\/\$host\$request_uri; }/" "${conf}"
    nginx -t >/dev/null 2>&1 || die "$(t nginx_bad)"
    systemctl reload nginx
    warn "$(t https_test)"
    return 0
  fi
  command -v certbot >/dev/null || apt-get install -y certbot python3-certbot-nginx >/dev/null
  if certbot --nginx --non-interactive --agree-tos --redirect -m "${email}" "${names[@]}"; then
    ok "$(t https_ok "${domain}")"
  else
    warn "$(t https_fail "${domain}")"
  fi
}
