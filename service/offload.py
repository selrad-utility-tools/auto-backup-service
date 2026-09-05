#!/usr/bin/env python3

"""Offload Backups from the Local Backup Store into S3.

For every Backup matching ``DD-MM-YYYY-gz.sql.gz`` in the given directory:
  - if the object is not yet an Archive, offload it and confirm the Archive
    byte-size matches the local Backup;
  - if the Archive already exists, confirm its size matches the local Backup.

Exit code 0 means every matching Backup is confirmed as an Archive; any failure
exit with code 1 so callers know not to Prune anything.
"""

import argparse
import gzip
import re
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

BACKUP_PATTERN = re.compile(r"^(\d{2}-\d{2}-\d{4})-gz\.sql\.gz$")


def gate_log(message: str) -> None:
    print(message, flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("store", help="Local Backup Store directory")
    parser.add_argument("--bucket", required=True, help="S3 bucket holding Archives")
    parser.add_argument("--region", required=True)
    parser.add_argument("--prefix", default="warehouse", help="S3 key prefix")
    parser.add_argument(
        "--endpoint-url",
        default=None,
        help="S3-compatible endpoint URL (omit to use the default AWS endpoint)",
    )
    args = parser.parse_args()

    store = Path(args.store).resolve()
    if not store.is_dir():
        gate_log(f"ERROR store is not a directory: {store}")
        return 1

    client = boto3.client("s3", region_name=args.region, endpoint_url=args.endpoint_url)

    backups = [
        p
        for p in sorted(store.iterdir())
        if p.is_file() and BACKUP_PATTERN.match(p.name)
    ]

    failures = 0
    for backup in backups:
        key = f"{args.prefix}/{backup.name}"

        if not _gzip_ok(backup):
            gate_log(f"ERROR {backup.name}: gzip integrity check failed, not offloading")
            failures += 1
            continue

        try:
            existing = client.head_object(Bucket=args.bucket, Key=key)
        except ClientError as exc:
            if exc.response["ResponseMetadata"]["HTTPStatusCode"] != 404:
                gate_log(f"ERROR {backup.name}: could not confirm Archive status: {exc}")
                failures += 1
                continue
            existing = None

        local_size = backup.stat().st_size

        if existing is not None:
            archive_size = int(existing["ContentLength"])
            if archive_size == local_size:
                gate_log(f"SKIPPED {backup.name}: already an Archive (size matches)")
                continue
            gate_log(
                f"ERROR {backup.name}: Archive size {archive_size} != local "
                f"{local_size}; refusing to overwrite"
            )
            failures += 1
            continue

        try:
            client.upload_file(str(backup), args.bucket, key)
        except ClientError as exc:
            gate_log(f"ERROR {backup.name}: offload failed: {exc}")
            failures += 1
            continue

        try:
            confirmed = client.head_object(Bucket=args.bucket, Key=key)
        except ClientError as exc:
            gate_log(f"ERROR {backup.name}: offloaded but unconfirmable: {exc}")
            failures += 1
            continue

        confirmed_size = int(confirmed["ContentLength"])
        if confirmed_size != local_size:
            gate_log(
                f"ERROR {backup.name}: confirmed Archive size {confirmed_size} "
                f"!= local {local_size}"
            )
            failures += 1
            continue

        gate_log(f"OFFLOADED {backup.name} ({local_size} bytes)")

    if failures:
        gate_log(f"FAILED with {failures} error(s)")
    else:
        gate_log("ALL BACKUPS CONFIRMED AS ARCHIVES")
    return 1 if failures else 0


def _gzip_ok(path: Path) -> bool:
    try:
        with gzip.open(path, "rb") as handle:
            while handle.read(1 << 16):
                pass
        return True
    except (OSError, EOFError):
        return False


if __name__ == "__main__":
    sys.exit(main())