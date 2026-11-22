#!/usr/bin/env bash
# Terminal colors (turned off when the output is not a terminal or NO_COLOR is set).

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_OFF=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[1;31m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'; C_BLUE=$'\033[1;34m'; C_CYAN=$'\033[1;36m'
  C_GRAY=$'\033[0;90m'
else
  C_OFF=""; C_BOLD=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_GRAY=""
fi
export C_OFF C_BOLD C_RED C_GREEN C_YELLOW C_BLUE C_CYAN C_GRAY
