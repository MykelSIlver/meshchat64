# Relay setup

MeshChat64 is a **client**. It talks to a standard MeshChat relay — the
WebSocket signalling server from the upstream project,
[`saint-cc/meshchat`](https://github.com/saint-cc/meshchat) (`server.py`).
The relay only forwards encrypted frames between peers; it never sees
plaintext and holds no keys. MeshChat64 does **not** ship its own relay —
run (or connect to) saint-cc's.

## The one thing the C64 needs: a plain `ws://` path to the relay

saint-cc's `server.py` serves the WebSocket signal server as **plain `ws://`**
on `0.0.0.0:8888` by default (`WS_PORT`). That matters because a 6502 cannot
do TLS — the C64 speaks plain `ws://` only. So:

- **If the relay's plain-`ws://` port is reachable by the C64** (you run
  `server.py` yourself on the LAN, or the relay host exposes `:8888`
  directly), the C64 **dials it directly**. No nginx, no extra moving parts.
- **If the relay is only reachable via `wss://`** (TLS — e.g. a public relay
  behind nginx/Caddy, which browsers require), a remote C64 cannot reach it,
  because it can't do TLS. In that case put a thin **plain-`ws://` door** in
  front that proxies to the relay's `:8888` — see `nginx-c64.conf`. The door
  is the only nginx the C64 needs; it proxies to `server.py`, not to anything
  in this repo.

```
  direct (relay reachable as plain ws):

     C64 / U64  -- ws:// -->  server.py  (relay, :8888 plain ws)

  behind TLS (public relay is wss-only, C64 remote):

     C64 / U64  -- ws:// -->  nginx <LAN-IP>:8889  -- proxy -->  server.py :8888
     (no TLS)                 (plain-ws door, this dir)          (the relay)
```

## 1. Run / reach the relay

Follow the upstream instructions to run the relay:
<https://github.com/saint-cc/meshchat>. The signal server listens on plain
`ws://` `0.0.0.0:8888` by default. If you only want to chat on someone else's
relay, you just need a plain-`ws://` host:port you can dial (ask whoever runs
it, or use the optional door in step 2).

## 2. (Optional) plain-ws door — only if the relay is wss-only

Use `nginx-c64.conf`. Replace `192.168.1.100` with your Pi's LAN IP and point
`proxy_pass` at wherever `server.py`'s WS port lives (default
`127.0.0.1:8888`), then reload nginx. The three WebSocket-critical lines are
`proxy_http_version 1.1` and the two `Upgrade`/`Connection "upgrade"` headers —
without them the handshake fails. Skip this whole step if the C64 can already
reach the relay as plain `ws://`.

## 3. Point the C64 at the relay (rebuild required)

The relay address is compiled into the C64 binary, so set it in
`src/meshchat64.asm` and rebuild (see the main README). Two places, both
clearly marked `RELAY CONFIG`:

| Label           | What it is                                                                                       | Default placeholder                       |
|-----------------|--------------------------------------------------------------------------------------------------|-------------------------------------------|
| `STR_ATDT`      | what the C64 *dials* — the relay's plain-`ws://` `host:port` (or your nginx door, if you use one) | `ATDT192.168.1.100:8889`                  |
| `STR_RELAY_B64` | base64 of the `wss://` URL put in your *shareable key* (so browser peers know which relay to use) | `btoa(wss://your-meshchat-relay.net/ws/)` |

`STR_ATDT` is whatever plain-`ws://` endpoint the C64 should dial: the relay's
`:8888` directly, or your door's `listen <ip>:8889` from `nginx-c64.conf`.
`STR_RELAY_B64` should be the **public** `wss://` URL browsers reach.

Both strings are kept the same length as a normal relay address so editing
them does not shift the binary layout — but always rebuild and test after a
change.

## 4. Connectivity check

```bash
# does the endpoint upgrade? (expect HTTP/1.1 101 Switching Protocols)
# point it at whatever the C64 dials: the relay :8888, or your door :8889
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
     -H "Sec-WebSocket-Version: 13" \
     http://192.168.1.100:8889/
```

## Notes

- **VICE (emulator):** turn warp **off** while chatting. Warp speeds up the
  C64's jiffy clock ~11x, which makes the connection watchdog fire ~11x too
  early relative to the real-time relay pings. Warp is fine during the slow
  login computation; switch it off once the chat screen appears.
- **Slow sending is normal** on a stock 1 MHz C64: Ed25519 signing of an
  outgoing message takes minutes. The C64 keeps the connection alive during
  that time by sending WebSocket pongs woven into the signing loop, so the
  relay's keepalive will not time out.
