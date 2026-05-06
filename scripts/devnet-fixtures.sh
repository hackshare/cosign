#!/usr/bin/env bash
# Populate devnet fixtures: a real 2-of-3 Squads multisig + an active proposal,
# so the CosignDevnet build has live data. Reads/writes .env.devnet.
set -euo pipefail
cd "$(dirname "$0")/.."
exec cargo run --quiet --manifest-path core/Cargo.toml --example devnet_fixture "$@"
