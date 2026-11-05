# obsidian-headless-mcp

Give Claude (web, mobile, scheduled tasks), ChatGPT and other MCP clients access to your Obsidian vault, from a container on your own NAS or server. No desktop app has to be running.

One container runs:

- **[Obsidian Headless](https://obsidian.md/help/headless)**: Obsidian's official command-line Sync client. It keeps a copy of your vault current through Obsidian Sync.
- **[obsidian-remote-mcp](https://github.com/nweii/obsidian-remote-mcp)**: a remote MCP server for that vault, with OAuth sign-in, read-only mode and `.mcpignore`.

Pair it with a Cloudflare Tunnel (included in the compose file) to give it a public HTTPS address without opening ports on your router. Cloud-hosted MCP clients such as claude.ai need a public address. A VPN or LAN address won't work.

```
Claude / ChatGPT ──HTTPS──► Cloudflare Tunnel ──► obsidian-headless-mcp ──► /vault ◄──► Obsidian Sync ◄──► your devices
```

## Requirements

- An [Obsidian Sync](https://obsidian.md/sync) subscription
- Docker with Compose, on an always-on machine (Synology Plus models, other NAS boxes, a home server or a VPS). Images are built for `amd64` and `arm64`.
- A domain on Cloudflare (free plan) for the tunnel. Tailscale Funnel or a reverse proxy also work.

## About the image

The image contains Node, Bun and a small startup script only. **It does not include Obsidian Headless or obsidian-remote-mcp.** Obsidian Headless is proprietary and obsidian-remote-mcp has no license, so neither can be redistributed. On first start, the container downloads the pinned versions from their official sources (npm and GitHub) into `/config/app`. Later starts reuse that copy. The first start takes 1–2 minutes and needs internet access.

## Setup

### 1. Folders and settings

Create a folder (for example `/volume1/docker/obsidian` on Synology) containing:

```
docker-compose.yml   (from this repo)
.env                 (copy of .env.example, filled in)
vault/               (empty)
config/              (empty)
```

Back up your vault before you start.

### 2. Cloudflare Tunnel

In the Cloudflare dashboard, go to **Networking → Tunnels → Create tunnel → Docker**. Copy the token into `.env` as `CLOUDFLARE_TUNNEL_TOKEN`.

Add a public hostname such as `vault.example.com` with service **HTTP** and URL **`obsidian:3456`**. Set `MCP_BASE_URL` in `.env` to `https://vault.example.com`.

> [!NOTE]
> Cloudflare might not let you progress to the place where you can actually add a public hostname until you start the container up and let it connect to the tunnel for the first time. If this is the case, just specify your anticipated public hostname in the `.env` file.

### 3. Start it

**Command line:**

```bash
docker compose up -d
docker compose logs -f obsidian
```

**Synology Container Manager:** go to **Project → Create**, set the path to your folder, use the existing `docker-compose.yml`, then click through to **Done**.

Wait for `obsidian-remote-mcp listening on port 3456` in the logs. It will warn that Sync isn't set up yet. That's expected.

### 4. Connect Obsidian Sync (once)

Open a shell in the container. On the command line, use `docker exec -it obsidian-headless-mcp bash`. In Synology Container Manager, use **Container → obsidian-headless-mcp → Terminal → Create**. Then run:

```bash
ob login
ob sync-list-remote
ob sync-setup --vault "Your Vault Name" --path /vault --device-name NAS
ob sync --path /vault
```

The last command downloads the vault. Then restart the container. The logs should show `starting Obsidian Headless sync`. Your login is stored in `config/` and survives restarts and upgrades.

### 5. Connect Claude

claude.ai → **Customize → Connectors → + → Add custom connector**

- URL: `https://vault.example.com/mcp`
- Advanced settings: OAuth Client ID is your `MCP_CLIENT_ID`. Leave the secret blank.
- Approve the connection with your `APPROVAL_PASSWORD`.

The connector then works in claude.ai, the mobile apps and scheduled tasks. For scheduled tasks, set the vault tools to "Always allow" so unattended runs don't stall.

**Claude Code:** set `MCP_STATIC_BEARER_TOKEN` in `.env`, then run:

```bash
claude mcp add --transport http obsidian https://vault.example.com/mcp --header "Authorization: Bearer <token>"
```

For other clients, see obsidian-remote-mcp's [client guide](https://github.com/nweii/obsidian-remote-mcp/blob/main/clients.md).

## Configuration

Set these in `.env`. The full list of server options is in obsidian-remote-mcp's [server reference](https://github.com/nweii/obsidian-remote-mcp/blob/main/docs/server.md). All of them can go in `.env`.

| Variable | Default | Description |
|---|---|---|
| `MCP_CLIENT_ID` | (required) | OAuth client ID you choose; enter the same value in the client |
| `APPROVAL_PASSWORD` | (required) | Password for the OAuth approval page |
| `MCP_BASE_URL` | (required) | Public HTTPS address, without `/mcp` |
| `CLOUDFLARE_TUNNEL_TOKEN` | (required for the tunnel) | Cloudflare Tunnel token |
| `VAULT_READ_ONLY` | `true` | Set to `false` to allow edits |
| `VAULT_DISPLAY_NAME` | folder name | Name shown on the approval page |
| `VAULT_CONTEXT_PATH` | `AGENTS.md`, then `CLAUDE.md` | Vault-relative path of the guidance note agents read at the start of a session. Filenames are case-sensitive on Linux. |
| `MCP_STATIC_BEARER_TOKEN` | unset | Never-expiring API key for header-based clients |
| `OB_VERSION` | pinned in image | Obsidian Headless version to download |
| `MCP_REF` | pinned in image | obsidian-remote-mcp commit or tag to download |

After changing `.env`, recreate the container with `docker compose up -d`. In Container Manager, use **Project → Action → Build**.

## Updating

Releases are tagged (`v0.1.0`, …) and published as `ghcr.io/lukehollenback/obsidian-headless-mcp:<version>`. To upgrade, change the version in `docker-compose.yml` and run `docker compose up -d`, or **Build** the project in Container Manager.

Use version tags rather than `latest`. Container Manager often won't download a newer `latest`, but it always downloads a tag it hasn't seen.

Changing `OB_VERSION` or `MCP_REF` makes the container download those versions on its next start. Your vault, Sync login and OAuth sign-ins are kept.

## Good to know

- **Sign-ins last 30 days.** obsidian-remote-mcp doesn't issue refresh tokens, so OAuth clients like claude.ai must reconnect monthly. Header-based API keys don't expire.
- **Start read-only.** With write access, a prompt injection in something an AI reads could edit or delete notes. Leave `VAULT_READ_ONLY=true` until you trust your setup.
- **Hide folders** by adding a `.mcpignore` file to the vault root, for example `Private/` or `**/Journal`.
- **Use one sync method per device.** Don't also run the Obsidian desktop app's Sync on the same machine.
- **Obsidian Headless is in open beta.** If its login stops persisting after an upgrade, check its [docs](https://obsidian.md/help/headless) for changes.
- **Optional extra protection:** put Cloudflare Access in front of `/authorize` only. See obsidian-remote-mcp's [HTTPS guide](https://github.com/nweii/obsidian-remote-mcp/blob/main/docs/setup.md#add-cloudflare-access-login-protection).

## Development

```bash
docker build -t obsidian-headless-mcp:dev .
```

Pushing to `main` publishes `:edge`. Pushing a `v*` tag publishes `:<version>`, `:<major>.<minor>` and `:latest` for amd64 and arm64.

## Credits

- [obsidian-remote-mcp](https://github.com/nweii/obsidian-remote-mcp) by nweii. It does the actual MCP work.
- [Obsidian Headless](https://obsidian.md/help/headless) by Obsidian.

This project is not affiliated with Obsidian.

## License

MIT for the files in this repository. See [LICENSE](LICENSE). The tools the container downloads remain under their owners' terms.
