#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> rustfmt --check"
(cd core && cargo fmt --all -- --check)

echo "==> clippy"
(cd core && cargo clippy --all-targets -- -D warnings)

if command -v swiftformat >/dev/null 2>&1; then
    echo "==> swiftformat --lint"
    swiftformat --lint App/ Modules/
else
    echo "swiftformat not installed; skipping. (Install: brew install swiftformat)"
fi

if command -v swiftlint >/dev/null 2>&1; then
    echo "==> swiftlint"
    swiftlint lint --quiet --strict --cache-path Derived/swiftlint-cache App Modules
else
    echo "swiftlint not installed; skipping. (Install: brew install swiftlint)"
fi

echo "==> UI copy guard"
ruby scripts/check-ui-copy.rb

echo "==> lint complete"
