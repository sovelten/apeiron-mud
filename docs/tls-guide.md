# TLS Guide

Enabling TLS for the telnet connection allows clients to connect securely
using encrypted communication. The MUD server supports **two complementary
TLS mechanisms** following MUD community standards:

1. **Direct TLS (dedicated port)** — the client connects on a separate
   port and the server immediately performs a TLS handshake (`SSL_accept`)
   before any telnet negotiation.

2. **START_TLS (in-band upgrade)** — the client connects on the standard
   plain-text port.  The server advertises the `START_TLS` telnet option
   (option 46).  If the client responds with `DO START_TLS`, the
   connection is upgraded to TLS in-place, preserving all previously
   negotiated options (NAWS window size, terminal type, etc.).

Both mechanisms can be used simultaneously.

---

## Prerequisites

- OpenSSL development libraries (for `cl+ssl`).
  - **Debian/Ubuntu:** `apt install libssl-dev`
  - **Fedora:** `dnf install openssl-devel`
  - **macOS (Homebrew):** `brew install openssl`

- A TLS certificate and private key (PEM format).

---

## Generating a self-signed certificate (for testing)

```bash
openssl req -x509 -newkey rsa:2048 \
  -keyout /etc/ssl/private/mud-server.key \
  -out /etc/ssl/certs/mud-server.pem \
  -days 365 -nodes \
  -subj "/CN=your-server-hostname/O=MUD Server"
```

For production you should obtain a certificate from a trusted certificate
authority (Let's Encrypt, etc.).

---

## Configuration

The following parameters are defined in `src/constants.lisp` (in the
`mud` package) and can be set before starting the server:

| Parameter                     | Default | Description                                    |
|-------------------------------|---------|------------------------------------------------|
| `*server-tls-port*`           | `8889`  | Port for the dedicated TLS listener.           |
| `*server-ssl-certificate*`    | `nil`   | Path to the PEM-encoded TLS certificate.       |
| `*server-ssl-key*`            | `nil`   | Path to the PEM-encoded TLS private key.       |
| `*server-ssl-password*`       | `nil`   | Password for the private key (if encrypted).   |
| `*server-tls-prefer-start-tls*` | `t`   | Offer START_TLS on the plain-text port.         |

---

## Starting the server with TLS

### Via keyword arguments to `start-mud-server`

```lisp
(mud:start-mud-server
  :tls-certificate "/etc/ssl/certs/mud-server.pem"
  :tls-key "/etc/ssl/private/mud-server.key")
```

This starts:

- A plain-text listener on port `8888` (default `*server-port*`) with the
  `START_TLS` option offered.
- A dedicated TLS listener on port `992` (default `*server-tls-port*`) with
  immediate TLS encryption.

### Via global variables

Set the globals before calling `start-mud-server`:

```lisp
(setf mud:*server-ssl-certificate* "/etc/ssl/certs/mud-server.pem"
      mud:*server-ssl-key* "/etc/ssl/private/mud-server.key"
      mud:*server-ssl-password* nil)

(mud:start-mud-server)
```

### Specifying the TLS port

```lisp
(mud:start-mud-server
  :tls-port 443
  :tls-certificate "/etc/ssl/certs/mud-server.pem"
  :tls-key "/etc/ssl/private/mud-server.key")
```

### Disabling START_TLS on the plain-text port

```lisp
(setf mud:*server-tls-prefer-start-tls* nil)
(mud:start-mud-server
  :tls-certificate "/etc/ssl/certs/mud-server.pem"
  :tls-key "/etc/ssl/private/mud-server.key")
```

With this setting, TLS is only available via the dedicated TLS port.

---

## Client connection

### Direct TLS (port 992)

```bash
# Using a TLS-aware telnet client (e.g., TinTin++, Mudlet):
# Connect to port 992 with TLS/SSL enabled.

# Using OpenSSL as a test client:
openssl s_client -connect your-server:992 -crlf
```

### START_TLS (port 8888)

Clients that support the `START_TLS` telnet option (option 46) can
connect to the standard telnet port and negotiate TLS after the initial
telnet option exchange. Most modern MUD clients (Mudlet, TinTin++,
MUSHclient) support this.

```bash
# Using telnet to see the START_TLS advertisement:
telnet your-server 8888
# The server sends IAC WILL 46 (START_TLS) during initial negotiation.
```

---

## How it works

### Connection flow — Direct TLS

```
Client                    Server
  |                         |
  |--- TCP connect -------->|
  |                         |--- SSL_accept (TLS handshake)
  |<-- ClientHello ---------|
  |--- ServerHello -------->|
  |     ...                 |
  |<-- TLS established ---- |
  |                         |--- Initial telnet negotiation (encrypted)
  |<-- IAC WILL SGA -------- |
  |<-- IAC DO SGA ---------- |
  |<-- IAC DO NAWS --------- |
  |<-- IAC DO TTYPE -------- |
  |--- IAC DO SGA ---------> |
  |     ...                 |
```

### Connection flow — START_TLS

```
Client                    Server
  |                         |
  |--- TCP connect -------->|
  |                         |--- Initial telnet negotiation (plain)
  |<-- IAC WILL SGA -------- |
  |<-- IAC DO SGA ---------- |
  |<-- IAC DO NAWS --------- |
  |<-- IAC DO TTYPE -------- |
  |<-- IAC WILL 46 ----------|  ← START_TLS offer
  |--- IAC DO 46 ---------->|
  |                         |--- SSL_accept (TLS handshake)
  |<-- ClientHello --------- |
  |--- ServerHello -------->|
  |     ...                 |
  |<-- TLS established ---- |
  |     ... continued ...   |
```

---

## Architecture

```
Application (character I/O)     ← mud-read-line / mud-write
        ↑ ↓
flexi-streams (UTF-8)           ← telnet-read-char / telnet-write-string
        ↑ ↓
Telnet IAC processor            ← IAC escaping, option negotiation
        ↑ ↓
Binary stream                   ← raw-stream / out-stream
        ↑ ↓           ╔══════════════════╗
        |            ║  Optional: TLS   ║  ← cl+ssl:make-ssl-server-stream
        |            ║  (SSL_accept)    ║
        |             ╚══════════════════╝
        ↑ ↓
Socket FD / usocket              ← usocket:socket-accept
```

When TLS is active, the binary stream is replaced by an SSL stream
that handles encryption/decryption transparently. The telnet protocol
layer above it is unaware of the change.

---

## Configuration reference

### `run-mud.lisp` example

```lisp
(push #p"./" asdf:*central-registry*)
(ql:quickload :mud)

(setf mud:*server-ssl-certificate* "/etc/ssl/certs/mud-server.pem"
      mud:*server-ssl-key* "/etc/ssl/private/mud-server.key")

(let ((force-new (member "--force-new-world" sb-ext:*posix-argv*
                         :test #'string-equal)))
  (mud:start-mud-server :force-new force-new))

(loop while mud:*server-running* do (sleep 1))
```

### Checking TLS status

```lisp
;; Check if a specific connection has TLS active:
(telnet:telnet-tls-connection-p conn)
;; → T / NIL

;; Check server status:
(mud:get-server-status)
```

---

## Troubleshooting

| Problem                          | Likely cause                              |
|----------------------------------|-------------------------------------------|
| `TLS handshake failed`           | Certificate or key path incorrect.        |
| `SSL_ERROR_SYSCALL`              | Client disconnected during handshake.     |
| `Connection reset by peer`       | Client closed before server finished.     |
| Client sees "unknown option 46"  | Old client that doesn't support START_TLS.|
| START_TLS not offered            | `*server-tls-prefer-start-tls*` is `nil`  |
|                                  | or no certificate is configured.          |

The server only advertises `START_TLS` when both
`*server-tls-prefer-start-tls*` and valid certificate/key paths are
configured.
