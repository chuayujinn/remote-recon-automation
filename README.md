# Remote Recon & Anonymised Network Audit Automation

A Bash automation toolkit that connects to a remote Linux server over SSH, performs reconnaissance and a WHOIS lookup while routing local traffic through Tor for anonymity, captures the resulting network traffic, retrieves the evidence files, and produces a full audit log of every action taken.



---

## What this project demonstrates

- **Automation & scripting** — a 540+ line Bash script that orchestrates a multi-stage workflow end-to-end with no manual intervention once started
- **Operational security (OPSEC)** — verifying and enforcing an anonymous network connection (via Tor/Nipe) before any reconnaissance activity begins, with automatic retry logic
- **Remote system administration** — SSH automation, remote package management, and remote service configuration (FTP server setup via `vsftpd`)
- **Network traffic analysis** — capturing live traffic with `tcpdump` and analysing the resulting `.pcap` file in Wireshark
- **Protocol security analysis** — a written comparison of FTP vs SFTP against the CIA Triad (Confidentiality, Integrity, Availability), with attack scenarios and secure-alternative recommendations
- **Audit logging** — every step of execution is timestamped and logged to a local audit file, supporting accountability and traceability — a principle directly relevant to compliance and audit work

---

## Project structure

```
.
├── remote_recon_automation.sh   # Main automation script (Scope 1)
├── docs/
│   ├── ftp-vs-sftp-analysis.md  # Protocol research & CIA Triad analysis (Scope 2)
│   └── project-brief.pdf        # Original assignment brief
├── screenshots/                 # Execution evidence (terminal output, logs, captures)
└── README.md
```

---

## How it works (Scope 1 — Automation)

The script runs in three stages:

### 1. Installation & Anonymity Check
- Checks for required tools (`nipe`, `whois`, `sshpass`, `ftp`, `tcpdump`, `geoip-bin`) and installs any that are missing
- Verifies the local connection is anonymised via **Nipe** (a Tor-based anonymiser) — if not anonymous, it restarts Nipe and retries (up to 500 attempts, 30-second intervals) until an anonymous Tor circuit is established
- Displays the spoofed public IP and country once anonymity is confirmed

### 2. Remote Connection & Reconnaissance
- Prompts for remote server credentials and establishes an SSH connection via `sshpass`
- Displays the remote server's public IP, country, and uptime for verification
- Starts `tcpdump` on the remote server to capture network traffic
- Accepts a target IP/domain and runs a `WHOIS` lookup on the remote server

### 3. Evidence Collection & Cleanup
- Configures a temporary FTP server (`vsftpd`) on the remote host
- Retrieves the WHOIS results and the `.pcap` capture file via FTP
- Stops the packet capture and removes all temporary files from the remote server
- Outputs three artefacts locally: the WHOIS result file, the packet capture file, and a full timestamped audit log

---

## How it works (Scope 2 — Protocol Security Analysis)

The `docs/ftp-vs-sftp-analysis.md` file contains a structured research report covering:

- FTP fundamentals (RFC 959), command set, and the active vs passive mode distinction
- A full annotated FTP session trace (control connection, authentication, data transfer)
- CIA Triad impact analysis — how FTP's plaintext design fails Confidentiality and Integrity, and creates Availability risks (DoS, session hijacking, firewall/NAT issues)
- A comparison against **SFTP** as the secure alternative, including encryption (AES-256), MAC-based integrity verification, and authentication options (public key, certificate-based, GSSAPI/Kerberos)
- Practical demonstration captured via Wireshark, showing the cleartext FTP exchange (including credentials) versus the fully encrypted SFTP equivalent

---

## Tools used

`bash` · `sshpass` · `nipe` (Tor) · `whois` · `geoiplookup` · `tcpdump` · `vsftpd` · `Wireshark`

---

## Disclaimer

This project was built for educational purposes within a controlled lab environment as part of a structured cybersecurity training programme. The anonymisation and reconnaissance techniques demonstrated here are intended to illustrate OPSEC principles and protocol security concepts, not for use against systems without explicit authorisation.
