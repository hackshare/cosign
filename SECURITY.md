# Security Policy

Cosign is a self-custody signer. It handles keys and signs transactions, so we
take security reports seriously and appreciate responsible disclosure.

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report it privately through GitHub's private vulnerability reporting: open the
repository's Security tab and use "Report a vulnerability". Include enough detail
to reproduce the issue: the affected component, the steps, and the impact. We
will acknowledge your report, work on a fix, and credit you if you would like.

There is no bug bounty or monetary reward at this time. We value the report
regardless and will respond.

## Scope

In scope:

- The iOS app (`App/`, `Modules/`) and its handling of keys, signing, and the
  Keychain.
- The Rust core crate (`core/`, `cosign_core`) and its key derivation, signing,
  and transaction decoding.
- The relay server (`core/src/bin/relay-server.rs`).

Out of scope:

- Third-party dependencies (report those upstream).
- The Solana network, Squads protocol, or RPC providers themselves.
- Issues that require a jailbroken device or a compromised host.

## Important context

Cosign is **pre-1.0 beta software**. The current TestFlight build runs on Solana
**devnet** (a test network) and is **not security audited**. Do not use it to
manage real funds. It is provided without warranty (see `LICENSE`).

Keys are generated and stored on the device, in the iOS Keychain or on a
connected hardware signer, and are never transmitted. The relay proxies Solana
RPC and helps decode proposals; it cannot sign or move funds.
