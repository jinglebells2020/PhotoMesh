#!/usr/bin/env python3
"""Incrementally download the collector's objects from R2 (S3 API) into a local folder.

Environment: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, optional R2_BUCKET (default photomesh-data).
"""
import argparse
import os
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", default="data/raw", help="destination folder (keys are mirrored under it)")
    parser.add_argument("--prefix", default="installs/", help="only keys under this prefix")
    parser.add_argument("--skip-images", action="store_true", help="metadata and events only")
    args = parser.parse_args()

    try:
        import boto3  # type: ignore
    except ImportError:
        print("pip install boto3", file=sys.stderr)
        return 2
    account = os.environ.get("R2_ACCOUNT_ID")
    key = os.environ.get("R2_ACCESS_KEY_ID")
    secret = os.environ.get("R2_SECRET_ACCESS_KEY")
    bucket = os.environ.get("R2_BUCKET", "photomesh-data")
    if not (account and key and secret):
        print("set R2_ACCOUNT_ID, R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY", file=sys.stderr)
        return 2

    s3 = boto3.client("s3", endpoint_url=f"https://{account}.r2.cloudflarestorage.com", aws_access_key_id=key, aws_secret_access_key=secret, region_name="auto")
    out = Path(args.out)
    downloaded = skipped = 0
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=args.prefix):
        for obj in page.get("Contents", []):
            k = obj["Key"]
            if args.skip_images and "/images/" in k:
                continue
            target = out / k
            if target.exists() and target.stat().st_size == obj["Size"]:
                skipped += 1
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            s3.download_file(bucket, k, str(target))
            downloaded += 1
            if downloaded % 100 == 0:
                print(f"  {downloaded} downloaded…")
    print(f"done: {downloaded} downloaded, {skipped} already present, under {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
