#!/usr/bin/env bash
#
# server-kit — installs a PHP system (Laravel or plain PHP) from a GitHub link on a fresh Ubuntu server.
# One system per server.
#
#   git clone https://github.com/monill/server-kit.git && cd server-kit && sudo ./install.sh
#
# Actions (menu, or straight from the command line):
#   sudo ./install.sh                     menu
#   sudo ./install.sh install [options]   install the system (again = same system, keeps .env, data and passwords)
#   sudo ./install.sh update              git pull, dependencies, build, migrations, restart
#   sudo ./install.sh remove              take the system off the server
#   sudo ./install.sh check               check the server and the installed system
#   sudo ./install.sh resize              size PHP, MySQL, Redis and queues for this machine (after a plan change)
#   (after the first install the same actions are also available as: sudo server-kit <action>)
#
# Options for install (anything left out is asked; update also takes --php to change the version):
#   --repo URL  --branch NAME  --domain NAME  --email EMAIL  --php 7.4…8.6  --mysql 8.4|9.7  --db local|remote|none
#   --test (VM without a domain: self-signed certificate)  --lang pt_BR|en  --plain (no menus, plain questions)
#   --yes (go on past warnings: old PHP, server checks; never answers the deletions of remove)
#
# MIT License. See README.md.

set -euo pipefail

SK_VERSION="1.0.0"
SK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SK_REPO_URL="https://github.com/monill/server-kit.git"

# Run through "curl ... | bash": the libraries are not next to the script; fetch the project and start it from there
if [[ ! -f "${SK_DIR}/lib/ui.sh" ]]; then
  [[ ${EUID} -eq 0 ]] || { echo "Run as root: sudo bash install.sh" >&2; exit 1; }
  command -v git >/dev/null || { apt-get update -y && apt-get install -y git; }
  rm -rf /opt/server-kit
  git clone --depth 1 "${SK_REPO_URL}" /opt/server-kit
  exec bash /opt/server-kit/install.sh "$@" </dev/tty
fi

# shellcheck source=lib/loader.sh
source "${SK_DIR}/lib/loader.sh"
sk_main "$@"
