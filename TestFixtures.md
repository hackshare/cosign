# Devnet Smoke Fixtures

The devnet smoke harness is opt-in and read-only. It does not run during normal
unit tests or lint.

## Run

```sh
cd core
COSIGN_DEVNET_RPC_URL=https://api.devnet.solana.com \
COSIGN_DEVNET_MULTISIG=<devnet-squad-address> \
COSIGN_DEVNET_MEMBER=<member-pubkey> \
cargo test --test devnet_smoke -- --ignored --nocapture
```

For Helius devnet, copy `.env.devnet.example` to `.env.devnet` and set
`COSIGN_DEVNET_RPC_URL` to the Helius devnet URL. The Rust smoke test loads the
repo-root `.env` and `.env.devnet` automatically without overriding variables
already exported in the shell. Use `COSIGN_ENV_FILE=/path/to/file` to load a
different env file instead.

Set `COSIGN_DEVNET_PROPOSAL_INDEX=<index>` to fetch one proposal detail.

Set `COSIGN_DEVNET_DISCOVER_MULTISIG=1` to discover the first Squads multisig
account on devnet when you do not yet have a fixture. Discovery validates that
the read stack can hit devnet, but it does not prove hot-wallet membership.

To run the Swift `SquadsService` smoke tests, export the same `COSIGN_DEVNET_*`
variables in the shell and run:

```sh
xcodebuild -quiet \
  -project Cosign.xcodeproj \
  -scheme Squads \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath Derived/SquadsDevnetSmoke \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Hot-Wallet Fixture Setup

1. Run the app on the simulator and create a hot wallet.
2. Copy the signer pubkey from the Signers screen.
3. Add that pubkey as a member of a devnet Squad using Squads web or CLI.
4. Set `COSIGN_DEVNET_MEMBER` to the signer pubkey.
5. Set `COSIGN_DEVNET_MULTISIG` to the devnet Squad address.

Ledger and YubiKey are not covered by this harness yet. Voting and execution
are also out of scope until the write-path milestone lands.
