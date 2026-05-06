# Contributing to Cosign

Thanks for your interest. Cosign is a self-custody signer, so correctness and
security matter. Please keep changes focused and well-tested.

## Setup

- macOS with a recent Xcode (Swift 6), [Tuist](https://tuist.io), and Rust (stable).
- Add the iOS Rust targets:
  ```bash
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
  ```
- Install lint tooling and hooks: `brew install swiftformat swiftlint lefthook gitleaks`, then `lefthook install`. The pre-commit hooks include a `gitleaks` secret scan over staged changes.
- Generate and open the project:
  ```bash
  ./scripts/build-xcframework.sh && tuist generate && open Cosign.xcworkspace
  ```

Simulator builds and CI need no signing setup. To build on a physical device or
deploy under your own Apple account, override the maintainer's defaults:

- Device builds: set your Apple Developer team in the `DEVELOPMENT_TEAM` build
  setting in `Tuist/ProjectDescriptionHelpers/TargetFactory.swift`.
- TestFlight (`scripts/deploy-testflight.sh`): the script reads `DEVELOPMENT_TEAM`,
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEYCHAIN_SERVICE` from the environment,
  falling back to the maintainer's. Set your own to deploy to your account.

## Checks

The pre-commit hooks and CI (`.github/workflows/ci.yml`) run all of these, so
run them locally before pushing:

- Rust: `cd core && cargo test`, `cargo fmt --all -- --check`, `cargo clippy --all-targets -- -D warnings`.
- Swift: `swiftformat --lint App Modules`, `swiftlint lint --strict App Modules`, plus an Xcode build and test.

New user-facing strings go through the existing copy helpers; the `ui-copy`
pre-commit hook enforces this.

## Pull requests

- Branch from `main`, keep PRs focused, and describe the change and its motivation.
- Make sure CI passes (Rust and iOS build, lint, tests) and the secret scan is clean.
- Do not commit secrets, API keys, recovery phrases, or `.env` files. The
  secret-scan workflow will flag them, but please double-check.

## Security

Do not file security vulnerabilities as public issues. See [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
