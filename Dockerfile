# Yantra frontend: static pages served by nginx (runs as non-root on port 8080).

# Stage 1: syntax-check the browser JavaScript (ES modules) before shipping it.
FROM node:22-alpine AS check
WORKDIR /src
COPY *.js ./
RUN for f in auth.js brand.js ui.js firebase-config.js; do \
      cp "$f" /tmp/check.mjs && node --check /tmp/check.mjs || exit 1; \
    done

# Stage 2: serve the site.
FROM nginxinc/nginx-unprivileged:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=check /src/*.js /usr/share/nginx/html/
COPY *.html *.css /usr/share/nginx/html/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
