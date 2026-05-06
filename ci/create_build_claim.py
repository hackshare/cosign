#!/usr/bin/env python3
"""Generate a deterministic BuildClaim.json from the working tree + environment.

Environment:
  BUILD_CLAIM_KEY_ID   keyId to embed (e.g. cosign-release-2026-06)
  APP_VERSION          CFBundleShortVersionString of the build
  APP_BUILD            CFBundleVersion of the build
  COSIGN_TAG           release tag name (e.g. v0.1.0+1751312345); optional
  COSIGN_REPOSITORY    repo slug (default hackshare/cosign)

The claim is serialized with sorted keys and no insignificant whitespace, with a
trailing newline; those exact bytes are what gets signed, embedded, and hashed.
When the tag does not yet exist locally (a manual pre-tag deploy), tagObjectSha is
empty and commitSha falls back to HEAD.

Usage: create_build_claim.py <out.json>
"""
import hashlib
import json
import os
import pathlib
import subprocess
import sys

LOCKFILES = [
    "core/Cargo.lock",
    "Cosign.xcworkspace/xcshareddata/swiftpm/Package.resolved",
]
RECIPE_FILES = [
    "ci/create_build_claim.py",
    "Tools/SignBuildClaim.swift",
    "Project.swift",
    "Tuist.swift",
    "Tuist/ProjectDescriptionHelpers/TargetFactory.swift",
    "scripts/deploy-testflight.sh",
    "scripts/build-xcframework.sh",
    "scripts/build-rust.sh",
]


def run(*args, default=""):
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.DEVNULL).strip()
    except subprocess.CalledProcessError:
        return default


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def stable_hash_json(value):
    data = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(data.encode()).hexdigest()


def entries(paths):
    found = [
        {"path": rel, "sha256": f"sha256:{sha256_file(rel)}"}
        for rel in paths
        if pathlib.Path(rel).exists()
    ]
    return sorted(found, key=lambda e: e["path"])


def main():
    out = pathlib.Path(sys.argv[1])
    tag = os.environ.get("COSIGN_TAG") or os.environ.get("GITHUB_REF_NAME", "")
    tag_object = run("git", "rev-parse", f"{tag}^{{tag}}") if tag else ""
    commit = run("git", "rev-parse", f"{tag}^{{}}") if tag_object else run("git", "rev-parse", "HEAD")

    claim = {
        "schema": 1,
        "keyId": os.environ["BUILD_CLAIM_KEY_ID"],
        "repository": os.environ.get("COSIGN_REPOSITORY")
        or os.environ.get("GITHUB_REPOSITORY", "hackshare/cosign"),
        "tag": tag,
        "tagObjectSha": tag_object,
        "commitSha": commit,
        "version": os.environ["APP_VERSION"],
        "build": os.environ["APP_BUILD"],
        "dependencyLockRoot": f"sha256:{stable_hash_json(entries(LOCKFILES))}",
        "buildRecipeSha256": f"sha256:{stable_hash_json(entries(RECIPE_FILES))}",
        "toolchain": {
            "macOSProductVersion": run("sw_vers", "-productVersion"),
            "macOSBuild": run("sw_vers", "-buildVersion"),
            "xcode": " ".join(run("xcodebuild", "-version").splitlines()),
            "swift": run("xcrun", "swift", "--version"),
            "iphoneOSSDK": run("xcrun", "--sdk", "iphoneos", "--show-sdk-version"),
        },
    }

    data = json.dumps(claim, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    print(f"sha256:{hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    sys.exit(main())
