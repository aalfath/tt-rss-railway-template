# Tiny Tiny RSS for Railway: the official tt-rss image (php-fpm), its update
# daemon and a small Caddy web server, all in one service so they share one volume.
FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy
# plain copy (no file capabilities), so the binary also runs as an unprivileged user
RUN cp /usr/bin/caddy /caddy

# tt-rss publishes one image per main commit; 20261121-201339 = commit 7240fb5
FROM ghcr.io/tt-rss/tt-rss:20261121-201339@sha256:d53e1f4f7bb93f7d468d1cfb0d4a409895db2416f61d0cf034bc5da96aa082ee

COPY --from=caddy /caddy /usr/local/bin/caddy
COPY Caddyfile /etc/caddy/Caddyfile
COPY railway-start.sh /usr/local/bin/railway-start.sh

# keep PHP-FPM on loopback: only Caddy talks to it
RUN chmod 0755 /usr/local/bin/railway-start.sh /usr/local/bin/caddy \
 && sed -i -e 's/^listen = .*/listen = 127.0.0.1:9000/' \
           -e 's/^pm.status_listen = .*/pm.status_listen = 127.0.0.1:9001/' \
        /etc/php${PHP_SUFFIX}/php-fpm.d/www.conf \
 && grep -q '^listen = 127.0.0.1:9000' /etc/php${PHP_SUFFIX}/php-fpm.d/www.conf \
 && caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile

# nginx_xaccel only works behind nginx; Caddy serves cached files through PHP instead.
ENV TTRSS_PLUGINS="auth_internal, note" \
    TTRSS_NO_STARTUP_PLUGIN_UPDATES=true \
    PORT=8080

EXPOSE 8080
CMD ["/usr/local/bin/railway-start.sh"]
