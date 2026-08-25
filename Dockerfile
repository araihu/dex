FROM ghcr.io/dexidp/dex:master@sha256:af9469509350ff3f6ca70127175a58e5ab085b9d18740fa4a590d9f03f0a026b

COPY --chown=1001:1001 web/templates/header.html web/templates/footer.html /srv/dex/web/templates/
COPY --chown=1001:1001 web/static/araihu-* web/static/appearance.js web/static/theme-default.js web/static/favicon.svg web/static/favicon-32.png web/static/icons.svg /srv/dex/web/static/
COPY --chown=1001:1001 LICENSE NOTICE /usr/share/licenses/araihu-dex/
COPY --chown=1001:1001 .cache/sources/assets/NOTICE /usr/share/licenses/araihu-dex/assets-NOTICE
COPY --chown=1001:1001 .cache/sources/assets/licenses/Apache-2.0.txt .cache/sources/assets/licenses/heroicons-MIT.txt /usr/share/licenses/araihu-dex/
COPY --chown=1001:1001 entrypoint.sh /usr/local/bin/araihu-dex-entrypoint

ENV DEX_FRONTEND_DIR=/srv/dex/web
USER 1001:1001
ENTRYPOINT ["/usr/local/bin/araihu-dex-entrypoint"]
CMD ["dex", "serve", "/etc/dex/config.docker.yaml"]
