#!/usr/bin/env bash
# Sizes by the memory and processors of the machine. Running the installer again (bigger plan) recalculates.
#
#   PHP-FPM  35% of the memory for PHP (55% when MySQL is not on this server), ~64 MB per process.
#            pm = ondemand: without visits it uses no memory.
#   MySQL    25% of the memory for the data it keeps at hand (innodb_buffer_pool_size), in 128 MB steps.
#   Redis    fixed ceiling; the least used items leave when it fills up.
#   Queue    1 worker up to 3 GB, 2 up to 7 GB, then 4 (never more than the processors).
#   memory_limit stays 512M: it is the ceiling of EACH PHP process (a brake for a runaway page), not a reserve.

clamp() { local v=$1 lo=$2 hi=$3; echo $(( v < lo ? lo : (v > hi ? hi : v) )); }

sizing_compute() {
  local local_db="$1" share
  share=$([[ "${local_db}" == 1 ]] && echo 35 || echo 55)
  FPM_TOTAL="$(clamp $(( RAM_MB * share / 100 / 64 )) 5 200)"
  MYSQL_POOL_MB="$(clamp $(( RAM_MB / 4 / 128 * 128 )) 128 1048576)"
  if (( RAM_MB < 2500 )); then REDIS_MB=128; elif (( RAM_MB < 6000 )); then REDIS_MB=256; elif (( RAM_MB < 12000 )); then REDIS_MB=512; else REDIS_MB=1024; fi
  if (( RAM_MB < 3000 )); then WORKERS=1; elif (( RAM_MB < 7000 )); then WORKERS=2; else WORKERS=4; fi
  WORKERS="$(clamp "${WORKERS}" 1 "${CPUS}")"
}
