# FTP vs SFTP — Protocol Security Analysis

This document summarises the protocol research conducted for Scope 2 of the project: capturing and analysing network traffic generated during the automated reconnaissance run, with a focus on **File Transfer Protocol (FTP)** as the insecure protocol under study, and **SFTP** as its secure replacement.

---

## 1. Why FTP

FTP (RFC 959, 1985) is one of the oldest file transfer protocols still in active use. It was selected for analysis because it was the protocol used by the automation script (`remote_recon_automation.sh`) to retrieve evidence files from the remote server — making it possible to capture a live FTP session with `tcpdump` and inspect it in Wireshark.

FTP uses a **two-channel architecture**:

- **Control connection (port 21)** — a persistent channel carrying commands (`USER`, `PASS`, `LIST`, `RETR`, etc.) and server responses, in plain text
- **Data connection (port 20 or an ephemeral port)** — a temporary channel opened per file transfer or directory listing

It supports two connection modes — **Active (PORT)**, where the server connects back to the client (frequently blocked by firewalls/NAT), and **Passive (PASV)**, where the client initiates both connections, which has become the de facto standard.

---

## 2. A captured FTP session, step by step

A full session looks like this:

```
Client → Server : TCP SYN (port 21)
Server → Client : TCP SYN-ACK
Client → Server : TCP ACK
Server → Client : 220 FTP Server Ready
Client → Server : USER ubuntu
Server → Client : 331 Password required
Client → Server : PASS ********        <-- sent in PLAIN TEXT
Server → Client : 230 Login successful
Client → Server : TYPE I                (binary mode)
Client → Server : PASV
Server → Client : 227 Entering Passive Mode (ip,port)
Client → Server : RETR filename.txt
Server → Client : 150 Opening data connection
                   [file data transferred]
Server → Client : 226 Transfer complete
Client → Server : QUIT
```

When this traffic was captured during the automation run and opened in Wireshark, the **username and password were both visible in cleartext** in the packet data — directly demonstrating the protocol's core weakness.

---

## 3. Impact on the CIA Triad

### Confidentiality — critical failure
FTP transmits everything in plain text: usernames, passwords, commands, file contents, and directory listings. Anyone capturing traffic on the same network segment (via `tcpdump`/Wireshark, exactly as done in this project) can recover credentials and file contents directly. This also enables man-in-the-middle attacks where traffic is read or altered in transit.

### Integrity — moderate failure
FTP relies only on TCP's basic checksum, which catches accidental transmission errors but cannot detect deliberate tampering. There is no cryptographic verification that a downloaded file matches what the server sent, or that the server is who it claims to be.

### Availability — moderate, with caveats
TCP gives FTP reliable delivery and the `REST` command allows resuming interrupted transfers, which is a genuine strength. However, FTP is comparatively easy to disrupt: anonymous access and the lack of an authentication delay make brute-force and connection-exhaustion attacks straightforward, and the dual-connection model plus Active mode's firewall/NAT problems create additional reliability issues in modern networks.

---

## 4. The secure alternative — SFTP

SFTP (SSH File Transfer Protocol) is not "FTP over SSH" — it's a different protocol built on SSH from the ground up, running entirely over a single encrypted channel on port 22.

| | FTP | SFTP |
|---|---|---|
| Channels | Two (control + data) | One (multiplexed over SSH) |
| Ports required | 21, 20, plus ephemeral range | 22 only |
| Encryption | None | AES-128/192/256 or ChaCha20-Poly1305 |
| Integrity | TCP checksum only | Per-packet MAC (e.g. HMAC-SHA2-256) |
| Authentication | Username/password in plaintext | Password (encrypted in-tunnel), public key, certificate-based, GSSAPI/Kerberos |
| Firewall/NAT friendliness | Poor (Active mode often blocked) | Good (single outbound port) |

**How SFTP resolves each CIA failure:**

- **Confidentiality** — the entire session, including authentication, runs inside an encrypted SSH tunnel. Even an attacker capturing every packet sees only ciphertext.
- **Integrity** — every packet carries a Message Authentication Code. Any tampering, accidental or deliberate, causes verification to fail and the packet to be rejected.
- **Availability** — a single-connection architecture reduces per-client resource usage, SSH's built-in rate limiting mitigates brute-force attempts, and requiring only port 22 removes the firewall/NAT complications that plague FTP.

---

## 5. Conclusion

Capturing the automation script's own FTP traffic made the theoretical risk concrete — the credentials used by the script were visible in the packet capture exactly as the research predicted. This is the practical argument for SFTP (or FTPS/HTTPS as alternatives): the choice isn't a matter of preference but a baseline security requirement once any credential or sensitive data crosses a network that isn't fully trusted.

---

## References

- RFC 959 — File Transfer Protocol
- RFC 4251–4254 — SSH Protocol Architecture, Authentication, Transport, and Connection Protocols
- RFC 2228 — FTP Security Extensions
- NIST SP 800-52 Rev. 2 — Guidelines for TLS Implementations
- OWASP Top Ten Web Application Security Risks
