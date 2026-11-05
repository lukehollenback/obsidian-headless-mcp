# obsidian-headless-mcp
#
# Runs Obsidian Headless (Obsidian Sync without the desktop app) and obsidian-remote-mcp
# (a remote MCP server for the vault) in one container.
#
# This image does NOT contain either tool. Obsidian Headless is proprietary and
# obsidian-remote-mcp has no license, so neither can be redistributed. Instead, the
# container downloads the pinned versions below from their official sources on first
# start and caches them in /config. Bump the versions to upgrade.

FROM oven/bun:1 AS bun

FROM node:22-bookworm-slim

LABEL org.opencontainers.image.title="obsidian-headless-mcp" \
      org.opencontainers.image.description="Obsidian Headless sync + obsidian-remote-mcp in one container, for Claude/ChatGPT custom connectors" \
      org.opencontainers.image.source="https://github.com/lukehollenback/obsidian-headless-mcp" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates tini \
 && rm -rf /var/lib/apt/lists/*

COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun

# Versions installed on first start (override with environment variables)
ENV OB_VERSION=0.0.14 \
    MCP_REPO=https://github.com/nweii/obsidian-remote-mcp.git \
    MCP_REF=474346f054982c0ce80f3b158336666351656586

# Runtime defaults
ENV HOME=/config/headless \
    VAULT_PATH=/vault \
    PORT=3456 \
    TOKEN_STORE_PATH=/config/mcp/tokens.json \
    LOG_DIR=/config/mcp/logs \
    VAULT_READ_ONLY=true \
    PATH=/config/app/obsidian-headless/node_modules/.bin:$PATH

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/vault", "/config"]
EXPOSE 3456

# Healthy once the MCP server answers OAuth discovery. The long start period covers
# the first-start download.
HEALTHCHECK --interval=60s --timeout=10s --start-period=300s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3456)+'/.well-known/oauth-authorization-server').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
