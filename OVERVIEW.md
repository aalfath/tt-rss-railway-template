# Deploy and Host Tiny Tiny RSS on Railway

Tiny Tiny RSS (tt-rss) is a free, open-source (GPL-3.0), web-based news feed reader and aggregator for RSS and Atom. It fetches your feeds in the background and gives you a fast reading UI with categories, labels, filters, search, OPML import and export, keyboard shortcuts, several users and an API used by mobile apps.

## About Hosting Tiny Tiny RSS

This template runs the official `ghcr.io/tt-rss/tt-rss` image, pinned by date tag and digest, plus a PostgreSQL database. Upstream's Docker setup uses three containers that share one volume (PHP-FPM, the feed update daemon and nginx). Railway can't share a volume between services, so this template runs all three in one service: PHP-FPM, the update daemon and a small Caddy web server, with the app files, feed icons and plugins on a Railway volume. On each start the app updates its database schema, and the built-in `admin` user gets the generated password from `ADMIN_PASSWORD`. If any of the three processes stops, the container exits with an error so Railway restarts it.

## Common Use Cases

* A private, ad-free reader for news sites, blogs, release notes and podcasts, open in any browser
* One feed server for mobile apps that speak the tt-rss API, with read state kept in sync
* A shared reading server for a small team or family, each person with their own account

## Dependencies for Tiny Tiny RSS Hosting

* PostgreSQL (Railway's Postgres, included) for feeds, articles, users and settings
* A Railway volume on the app service for the app files, feed icons, cache and local plugins (included)

### Deployment Dependencies

* Tiny Tiny RSS source: https://github.com/tt-rss/tt-rss
* Installation guide: https://tt-rss.org/docs/Installation-Guide.html
* Template repo: https://github.com/aalfath/tt-rss-railway-template

### Implementation Details

**Services**

* `Tiny Tiny RSS`: the public web app (Caddy + PHP-FPM) and the feed update daemon. Health check `/healthz`, volume `/var/www/html`.
* `Postgres`: Railway's PostgreSQL with its own volume. The app connects over the private network with reference variables.

**After deploy**

1. Open the Railway URL and sign in as `admin` with the password in the app service's `ADMIN_PASSWORD` variable (Variables tab).
2. Subscribe to feeds with the "+" button or import an OPML file under Preferences > Feeds. The daemon checks feeds every 2 minutes, and each feed's own interval is set in Preferences.
3. To add users, go to Preferences > Users. To use a mobile app, turn on "Enable API" under Preferences > Preferences.

If you change `ADMIN_PASSWORD` in Railway, the new value is set on the next start. If you change the admin password in the app and leave the variable alone, your change stays.

**Optional settings:** any tt-rss `TTRSS_*` setting can be added as a variable on the app service, for example SMTP for digests and password resets (`TTRSS_SMTP_SERVER`, `TTRSS_SMTP_FROM_ADDRESS`, ...) or `TTRSS_SESSION_COOKIE_LIFETIME`. With a custom domain, set `TTRSS_SELF_URL_PATH` to `https://YOUR-DOMAIN`. Otherwise it defaults to the Railway domain.

**Not included:** upstream's nginx container (Caddy serves the app instead) and its weekly backup cron job (Railway backs up the Postgres volume, and you can export feeds as OPML).

**Memory:** about 60 MB idle for the app service. PHP and daemon workers are sized from the service's memory limit, so it runs on 0.5 GB per service.

**Updates:** the app service builds from the GitHub repo above, which pins the upstream image by tag and digest. When we test and merge a newer tt-rss build, Railway shows an "update available" notice on your project, and you choose when to apply it. Read `CHANGELOG.md` in the repo first. The database schema updates on its own when the new version starts.

## Why Deploy Tiny Tiny RSS on Railway?

<!-- Recommended: Keep this section as shown below -->
Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Tiny Tiny RSS on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
