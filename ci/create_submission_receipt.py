#!/usr/bin/env python3
"""Generate a deterministic TestFlightSubmission.json receipt.

Binds the embedded build claim to the exact IPA uploaded to App Store Connect and
to the public GitHub verification artifact. The receipt is serialized with sorted
keys and no insignificant whitespace, with a trailing newline; those exact bytes
are what gets signed (Tools/SignJsonFile.swift) and hashed.

Every input may be supplied as a CLI flag (e.g. --ipa-sha256) or, when the flag is
omitted, via the matching environment variable (e.g. IPA_SHA256).

Usage:
  create_submission_receipt.py --out receipt.json --key-id ... --repository ... \
    --tag ... --commit ... --version ... --build ... --claim-sha256 ... \
    --ipa-sha256 ... --verification-sha256 ... --run-id ... --run-attempt ... \
    --uploaded-at ...
"""
import argparse
import json
import os
import pathlib

# CLI flag -> environment-variable fallback.
FIELDS = {
    "out": "OUT",
    "key-id": "KEY_ID",
    "repository": "REPOSITORY",
    "tag": "TAG",
    "commit": "COMMIT",
    "version": "VERSION",
    "build": "BUILD",
    "claim-sha256": "CLAIM_SHA256",
    "ipa-sha256": "IPA_SHA256",
    "verification-sha256": "VERIFICATION_SHA256",
    "run-id": "RUN_ID",
    "run-attempt": "RUN_ATTEMPT",
    "uploaded-at": "UPLOADED_AT",
}


def main():
    parser = argparse.ArgumentParser()
    for flag, env in FIELDS.items():
        parser.add_argument(f"--{flag}", default=os.environ.get(env))
    args = parser.parse_args()

    missing = [flag for flag in FIELDS if getattr(args, flag.replace("-", "_")) is None]
    if missing:
        parser.error("missing required inputs: " + ", ".join(sorted(missing)))

    def value(flag):
        return getattr(args, flag.replace("-", "_"))

    receipt = {
        "schema": 1,
        "keyId": value("key-id"),
        "repository": value("repository"),
        "tag": value("tag"),
        "commitSha": value("commit"),
        "version": value("version"),
        "build": value("build"),
        "buildClaimSha256": value("claim-sha256"),
        "submittedIpaSha256": value("ipa-sha256"),
        "verificationArtifactSha256": value("verification-sha256"),
        "workflowRun": {
            "repository": value("repository"),
            "runId": value("run-id"),
            "runAttempt": value("run-attempt"),
        },
        "destination": "app-store-connect",
        "uploadResult": "accepted",
        "uploadedAt": value("uploaded-at"),
    }

    data = json.dumps(receipt, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode() + b"\n"
    out = pathlib.Path(value("out"))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)


if __name__ == "__main__":
    main()
