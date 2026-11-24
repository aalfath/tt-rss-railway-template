#!/bin/sh
# Railway start script for Tiny Tiny RSS.
# Runs upstream's startup.sh (copies the app to the volume, migrates the schema,
# sets the admin password, then execs php-fpm), the feed update daemon and Caddy
# in one container. If any of the three stops, the container exits 1 so Railway
# restarts it.
set -eu

log() { echo "railway-start: $*"; }

BASE=${APP_INSTALL_BASE_DIR:-/var/www/html}
DST="$BASE/tt-rss"
MARK="$BASE/.railway-admin-password.sha256"

# ---- database (Railway Postgres reference variables) ----
: "${TTRSS_DB_HOST:?TTRSS_DB_HOST is not set}"
: "${TTRSS_DB_PASS:?TTRSS_DB_PASS is not set}"
export TTRSS_DB_PORT="${TTRSS_DB_PORT:-5432}"
export TTRSS_DB_USER="${TTRSS_DB_USER:-postgres}"
export TTRSS_DB_NAME="${TTRSS_DB_NAME:-railway}"

# ---- public URL, used by the update daemon, digests and the API ----
if [ -z "${TTRSS_SELF_URL_PATH:-}" ]; then
	if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
		export TTRSS_SELF_URL_PATH="https://$RAILWAY_PUBLIC_DOMAIN"
	else
		export TTRSS_SELF_URL_PATH="http://localhost:${PORT:-8080}"
	fi
fi
log "public URL $TTRSS_SELF_URL_PATH"

# ---- size PHP and the daemon to the container's memory and CPUs ----
mem_mb=0
if [ -r /sys/fs/cgroup/memory.max ] && [ "$(cat /sys/fs/cgroup/memory.max)" != max ]; then
	mem_mb=$(( $(cat /sys/fs/cgroup/memory.max) / 1048576 ))
fi
cpus=1
if [ -r /sys/fs/cgroup/cpu.max ]; then
	set -- $(cat /sys/fs/cgroup/cpu.max)
	if [ "$1" != max ]; then cpus=$(( ($1 + $2 - 1) / $2 )); else cpus=$(nproc); fi
fi
[ "$cpus" -ge 1 ] || cpus=1
export GOMAXPROCS="${GOMAXPROCS:-$cpus}"
# The image bakes PHP_WORKER_MAX_CHILDREN=5 and PHP_WORKER_MEMORY_LIMIT=256M:
# only replace those baked defaults, never a value the deployer set.
if [ "$mem_mb" -gt 0 ] && [ "$mem_mb" -le 1200 ]; then
	[ "${PHP_WORKER_MAX_CHILDREN:-5}" = 5 ] && export PHP_WORKER_MAX_CHILDREN=3
	[ "${PHP_WORKER_MEMORY_LIMIT:-256M}" = 256M ] && export PHP_WORKER_MEMORY_LIMIT=160M
	export TTRSS_DAEMON_MAX_JOBS="${TTRSS_DAEMON_MAX_JOBS:-1}"
fi
log "memory ${mem_mb:-?} MB, cpus $cpus: php-fpm children $PHP_WORKER_MAX_CHILDREN, PHP memory_limit $PHP_WORKER_MEMORY_LIMIT, daemon jobs ${TTRSS_DAEMON_MAX_JOBS:-2}"

# ---- wait for Postgres (private DNS can take a minute on a first deploy) ----
i=0
until pg_isready -q -h "$TTRSS_DB_HOST" -p "$TTRSS_DB_PORT" -U "$TTRSS_DB_USER"; do
	i=$((i + 1))
	if [ $i -ge 90 ]; then log "Postgres at $TTRSS_DB_HOST:$TTRSS_DB_PORT is not reachable after 3 minutes"; exit 1; fi
	[ $((i % 10)) = 1 ] && log "waiting for Postgres at $TTRSS_DB_HOST:$TTRSS_DB_PORT..."
	sleep 2
done

# ---- admin password: applied on the first boot and whenever ADMIN_PASSWORD changes,
# so a password changed later in the app's preferences survives restarts ----
export ADMIN_USER_PASS=""
want=""
if [ -n "${ADMIN_PASSWORD:-}" ]; then
	want=$(printf '%s' "$ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1)
	if [ ! -s "$MARK" ] || [ "$(cat "$MARK")" != "$want" ]; then
		log "applying ADMIN_PASSWORD to the built-in admin user"
		export ADMIN_USER_PASS="$ADMIN_PASSWORD"
	fi
else
	log "ADMIN_PASSWORD is empty: upstream sets a random admin password and prints it below"
fi
unset ADMIN_PASSWORD

# ---- 1. upstream startup (ends by exec'ing php-fpm) ----
rm -f "$DST/.app_is_ready"
/opt/tt-rss/startup.sh &
FPM=$!
unset ADMIN_USER_PASS AUTO_CREATE_USER_PASS

i=0
until [ -e "$DST/.app_is_ready" ]; do
	if ! kill -0 "$FPM" 2>/dev/null; then
		wait "$FPM" || true
		log "upstream startup failed"; exit 1
	fi
	i=$((i + 1))
	if [ $i -ge 600 ]; then log "upstream startup did not finish in 10 minutes"; exit 1; fi
	sleep 1
done
[ -n "$want" ] && printf '%s' "$want" > "$MARK" && chmod 600 "$MARK"
log "app ready"

# ---- 2. feed update daemon (upstream's "updater" container) ----
sudo -E -u app "$TTRSS_PHP_EXECUTABLE" "$DST/update_daemon2.php" &
DAEMON=$!

# ---- 3. web server on $PORT ----
sudo -E -u app env XDG_DATA_HOME=/tmp/caddy/data XDG_CONFIG_HOME=/tmp/caddy/config \
	/usr/local/bin/caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
WEB=$!

stop() { kill "$FPM" "$DAEMON" "$WEB" 2>/dev/null || true; }
trap 'log "stopping"; stop; exit 0' TERM INT

# BusyBox `wait -n` doesn't return on the first child exit, so poll.
while :; do
	for p in "$FPM:php-fpm" "$DAEMON:update daemon" "$WEB:caddy"; do
		if ! kill -0 "${p%%:*}" 2>/dev/null; then
			log "${p#*:} exited; stopping the container so Railway restarts it"
			stop; sleep 2; exit 1
		fi
	done
	sleep 5
done
