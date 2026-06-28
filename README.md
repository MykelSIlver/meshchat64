# MeshChat64

**End-to-end-encrypted WebSocket chat running entirely in 6502 assembly on a
Commodore 64.** A real C64 (or Ultimate-64) chats, fully encrypted, in the
same network as modern browsers.

MeshChat64 is a Commodore 64 client for **MeshChat** and is based on /
interoperates with [`saint-cc/meshchat`](https://github.com/saint-cc/meshchat).
It reimplements the MeshChat v1 wire protocol in hand-written 6502 assembly.
Licensed under **GNU GPL v3** (same as upstream).

> For the browser web client and the public relay, see the upstream project
> [`saint-cc/meshchat`](https://github.com/saint-cc/meshchat) — all credit for
> those goes to saint-cc. This repository is the C64 side.

---

## Highlight: real Ed25519 + AES-256-GCM on a 1 MHz 6502

Every outgoing message is **encrypted with AES-256-GCM and signed with
Ed25519**, computed entirely on the Commodore 64's 8-bit CPU. That signing
path is a full, from-scratch 6502 implementation of:

- **SHA-512** (for the Ed25519 nonce and challenge hashes),
- **Edwards25519 field arithmetic** modulo 2²⁵⁵ − 19,
- **fixed-base "comb" scalar multiplication** for `R = r·B`,
- **quarter-square multiplication** tables for fast 8-bit multiply,
- identity derivation via **PBKDF2-HMAC-SHA256** (100,000 iterations) → HKDF.

No turbo card is required to run it — only patience (see *Performance*). On an
Ultimate-64 with its turbo mode, signing takes a few seconds; on a stock 1 MHz
machine it takes minutes, but it works.

---

## What it does

- Log in with a name + passphrase; all keys are derived deterministically
  (no accounts, nothing stored server-side — same credentials = same identity).
- Add a peer via a *shareable key* (`encKey.signPublicKey.relayWss`), or leave
  it empty to chat to yourself for testing.
- Dial the relay over a SwiftLink/ACIA modem, perform the WebSocket handshake,
  then a challenge-response relay authentication.
- Exchange AES-256-GCM-encrypted, Ed25519-signed messages with the web client.
- Self-healing connection: a jiffy-clock watchdog reconnects if the relay drops.

The relay only forwards encrypted frames; it never sees plaintext and holds no
keys.

## Hardware

- **Ultimate-64** (Founders/FPGA) or a Commodore 64 with a **SwiftLink / ACIA
  6551** cartridge at `$DE00`, 38400 baud.
- Access to a **MeshChat WebSocket relay** — the upstream
  [`saint-cc/meshchat`](https://github.com/saint-cc/meshchat) `server.py`,
  reachable as plain `ws://` (a 6502 cannot do TLS — see
  [`relay/SETUP.md`](relay/SETUP.md)).
- Remove other cartridges while running (they clash with SwiftLink at `$DE00`).

Runs on the **VICE** emulator too (with tcpser as the modem) — turn warp
**off** while chatting; see `relay/SETUP.md`.

## Build

Requires [ACME](https://sourceforge.net/projects/acme-crossass/) 0.97.

```bash
cd src
acme -f cbm -o meshchat64.prg meshchat64.asm
```

`meshchat64.asm` needs **nine** include files alongside it in `src/`:
`comb_keepalive.inc`, `comb_table.inc`, `fastsha_main.inc`, `karatsuba.inc`,
`meshchat64_combsigned.inc`, `meshchat64_fastsq.inc`, `meshchat64_sendfix.inc`,
`qsq_tables.inc`, `sha512_const_ml.inc`. Eight are `!source`d directly by
`meshchat64.asm`; `comb_keepalive.inc` pulls in `comb_table.inc`. The result,
`meshchat64.prg`, loads on a C64/U64.

> **No prebuilt `.prg` is shipped.** The relay address is compiled into the
> binary, so a prebuilt one would only dial *someone else's* relay. Set your
> own relay (below) and build it yourself — it takes a couple of seconds.

## Configure your relay (required)

The relay address is compiled into the binary. Edit the two `RELAY CONFIG`
lines in `src/meshchat64.asm`, then build (see above):

- `STR_ATDT` — what the C64 dials: the relay's plain-`ws://` `host:port`
  (or your nginx door if the relay is wss-only), default
  `ATDT192.168.1.100:8889`.
- `STR_RELAY_B64` — base64 of the public `wss://` URL embedded in your
  shareable key.

Full relay walkthrough is in [`relay/SETUP.md`](relay/SETUP.md). If your relay
is reachable only via `wss://`, an optional plain-`ws://` door for the C64 is
[`relay/nginx-c64.conf`](relay/nginx-c64.conf).

## Performance

| Step                         | Ultimate-64 (turbo) | Stock C64 (1 MHz) |
|------------------------------|---------------------|-------------------|
| Login (PBKDF2 100k + keys)   | ~40 s               | ~7 min            |
| Sign + send one message      | ~ 2 s               | minutes           |
| Receive a message            | near-instant        | near-instant      |

Sending is the slow part because of Ed25519 signing; receiving does not sign.
During a long sign the C64 keeps the relay alive with woven-in WebSocket pongs,
so the connection does not time out.

## Architecture (short)

`boot → login → PBKDF2/HKDF → Ed25519 keypair → dial → WS handshake →
relay auth (challenge-response) → encrypted chat loop`.

Working buffers live in always-available RAM; the ACIA receiver is NMI-driven
into a ring buffer. See [`docs/meshchat_protocol_v1.md`](docs/meshchat_protocol_v1.md)
for the wire protocol.

See [docs/MEMORY_MAP.md](docs/MEMORY_MAP.md) for the full memory layout, the signed-comb and Karatsuba internals.

## Verification

Every cryptographic primitive was built standalone and checked **byte-exact**
against a Python reference (`hashlib` / `PyNaCl` / `pyca/cryptography`) in the
[py65](https://github.com/mnaberez/py65) simulator before integration. The
`verify/` scripts are those references and harnesses (e.g. `verify_pong.py`
proves the keepalive pong does not change the Ed25519 signature).

## Credits

- **Protocol & web client:** [saint-cc/meshchat](https://github.com/saint-cc/meshchat) (GNU GPL v3).
- **C64 client & 6502 crypto:** MykelSIlver.

## License

GNU General Public License v3 — see [LICENSE](LICENSE) and [NOTICE](NOTICE).
