# Aegis Remote Gateway

The gateway accepts authenticated natural-language commands and forwards them to the
loopback AegisDesktop command bridge. It never exposes AgentAction, Mac Agent, Server
Agent, Ollama, or coding-provider endpoints.

```env
AEGIS_REMOTE_ENABLED=false
AEGIS_REMOTE_HOST=100.x.y.z
AEGIS_REMOTE_PORT=8790
AEGIS_REMOTE_TOKEN=<at-least-32-random-characters>
AEGIS_REMOTE_REGISTRATION_RATE_LIMIT_PER_MINUTE=5
# Optional; defaults to ~/Library/Application Support/Aegis/remote-devices.json
AEGIS_REMOTE_DEVICE_STORE_PATH=
AEGIS_REMOTE_MAX_COMMAND_CHARS=4000
AEGIS_REMOTE_APPROVAL_TTL_SECONDS=300
AEGIS_DESKTOP_COMMAND_URL=http://127.0.0.1:8791
AEGIS_DESKTOP_BRIDGE_HOST=127.0.0.1
AEGIS_DESKTOP_BRIDGE_PORT=8791
AEGIS_DESKTOP_BRIDGE_TOKEN=<separate-internal-secret>
```

The master `AEGIS_REMOTE_TOKEN` is used only to bootstrap a browser device. The
gateway issues a separate 256-bit credential and persists only its salted
scrypt hash. The mobile UI stores that revocable device credential under
`aegis.remote.deviceCredential`; it never stores the master token. Plain HTTP
remains supported on the private Tailscale address, but Tailscale HTTPS
certificates are recommended to protect browser credentials in transit.

Only use a loopback, RFC1918 private, or Tailscale `100.64.0.0/10` bind address. The
gateway intentionally rejects wildcard and public binds. Start it with
`npm run remote-gateway`, then open `http://<configured-host>:8790/` from a trusted
Tailscale-connected phone. The token is kept only in the page's memory.

Remote control works only while the Mac is awake, AegisDesktop and its command bridge
are running, and Tailscale is connected. Phase 11 does not alter firewall/router state
and does not return screenshots.

AegisDesktop creates a mode-0600 internal bridge secret at
`~/Library/Application Support/Aegis/desktop-bridge.token` when an explicit
`AEGIS_DESKTOP_BRIDGE_TOKEN` is not configured. The gateway reads the same local file;
the secret never goes to the mobile browser. Explicit values may instead be placed in
`~/Library/Application Support/Aegis/config.env`, which is available to a signed GUI app
without relying on shell startup files.
