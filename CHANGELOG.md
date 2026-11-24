# Changelog

Breaking changes are listed first in each entry. Before you apply an update, export your feeds as OPML (Preferences > Feeds) or take a Postgres backup.

## 20261121-201339 (2026-11-24)

First release of the template.

- Tiny Tiny RSS build `20261121-201339` (upstream commit `7240fb5`), `ghcr.io/tt-rss/tt-rss:20261121-201339@sha256:d53e1f4f7bb93f7d468d1cfb0d4a409895db2416f61d0cf034bc5da96aa082ee`.
- Caddy 2.11.9 (`caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0`) serves the app in place of upstream's nginx container.
- PHP-FPM, the feed update daemon and Caddy run in one service, with app files on a Railway volume at `/var/www/html` and data in Railway Postgres.
- The built-in `admin` user gets the generated `ADMIN_PASSWORD` on the first start and whenever that variable changes.
- PHP-FPM workers, the PHP memory limit and the daemon's job count are sized from the service's memory limit, and the container exits non-zero when any of its processes stops.
