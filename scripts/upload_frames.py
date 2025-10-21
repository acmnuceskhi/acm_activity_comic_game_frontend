#!/usr/bin/env python3
"""
Upload frames one-by-one in filename order to an HTTP endpoint.

Features:
- Natural (human) sort of filenames so frame1, frame2, frame10 order correctly.
- Sequential uploads (one-by-one) with configurable retries and delay.
- Optional Authorization header via --token or UPLOAD_TOKEN env var.
- Dry-run mode, logging to a file (JSON lines), and progress output.

Usage examples:
  python scripts/upload_frames.py /path/to/frames --url https://example.com/upload --token ABC123
  python scripts/upload_frames.py ./frames --url http://localhost:8080/upload --pattern "*.png" --dry-run

Dependencies:
  pip install requests

Defaults:
- field name for file in multipart: 'file'
- retries: 3
- delay between uploads: 0.2s

"""

from __future__ import annotations

import argparse
import os
import sys
import time
import json
import glob
import mimetypes
import re
from typing import List

try:
    import requests
    from requests.exceptions import RequestException
except Exception:
    print("This script requires the 'requests' library. Install with: pip install requests", file=sys.stderr)
    raise


_number_re = re.compile(r"(\d+)")

def natural_key(s: str):
    # Split string into list of ints and text for natural sorting
    parts = _number_re.split(s)
    return [int(p) if p.isdigit() else p.lower() for p in parts]


def find_files(directory: str, pattern: str) -> List[str]:
    path = os.path.join(directory, pattern)
    files = glob.glob(path)
    files = [f for f in files if os.path.isfile(f)]
    files.sort(key=lambda p: natural_key(os.path.basename(p)))
    return files


def upload_file(
    url: str,
    file_path: str,
    field_name: str = "file",
    token: str | None = None,
    max_retries: int = 3,
    retry_delay: float = 1.0,
    timeout: float = 30.0,
):
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    content_type, _ = mimetypes.guess_type(file_path)
    if not content_type:
        content_type = "application/octet-stream"

    attempt = 0
    while True:
        attempt += 1
        try:
            with open(file_path, "rb") as fh:
                files = {field_name: (os.path.basename(file_path), fh, content_type)}
                resp = requests.post(url, headers=headers, files=files, timeout=timeout)

            # Consider 2xx success
            if 200 <= resp.status_code < 300:
                # Try to decode json if present, else raw text
                try:
                    data = resp.json()
                except Exception:
                    data = {"text": resp.text}
                return True, resp.status_code, data

            # Non-2xx -> error
            err = {"status": resp.status_code, "text": resp.text}
            if attempt >= max_retries:
                return False, resp.status_code, err
            time.sleep(retry_delay)

        except RequestException as e:
            if attempt >= max_retries:
                return False, None, {"error": str(e)}
            time.sleep(retry_delay)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Upload frames one-by-one in filename order.")
    ap.add_argument("directory", help="Directory containing frame image files")
    ap.add_argument("--url", required=True, help="Upload endpoint URL (POST)")
    ap.add_argument("--pattern", default="*.png", help="Glob pattern for image files (default: *.png)")
    ap.add_argument("--field-name", default="file", help="Multipart field name for the file (default: file)")
    ap.add_argument("--token", default=None, help="Authorization token (will be used as Bearer token)")
    ap.add_argument("--retries", type=int, default=3, help="Max retries per file (default: 3)")
    ap.add_argument("--retry-delay", type=float, default=1.0, help="Seconds between retries (default: 1.0)")
    ap.add_argument("--wait", type=float, default=0.2, help="Seconds to wait between successful uploads (default: 0.2)")
    ap.add_argument("--timeout", type=float, default=30.0, help="Request timeout in seconds (default: 30)")
    ap.add_argument("--log-file", default="upload_frames.log", help="File to append JSONL upload results to")
    ap.add_argument("--start", type=int, default=0, help="Start index (0-based) to resume uploads")
    ap.add_argument("--end", type=int, default=-1, help="End index (exclusive). -1 means upload all")
    ap.add_argument("--dry-run", action="store_true", help="Print file order but don't actually upload")

    args = ap.parse_args(argv)

    directory = os.path.abspath(args.directory)
    if not os.path.isdir(directory):
        print(f"Directory not found: {directory}", file=sys.stderr)
        return 2

    token = args.token or os.environ.get("UPLOAD_TOKEN")

    files = find_files(directory, args.pattern)
    total = len(files)
    if total == 0:
        print("No files found matching pattern.")
        return 0

    start = max(0, args.start)
    end = args.end if args.end >= 0 else total
    end = min(end, total)

    subset = files[start:end]

    print(f"Found {total} files, uploading indices [{start}:{end}) -> {len(subset)} files")

    all_ok = True
    with open(args.log_file, "a", encoding="utf-8") as logfh:
        for idx, path in enumerate(subset, start=start):
            name = os.path.basename(path)
            print(f"[{idx+1}/{total}] {name}")

            if args.dry_run:
                print("  dry-run: skipping upload")
                entry = {"index": idx, "file": path, "status": "dry-run"}
                print(json.dumps(entry), file=logfh)
                continue

            ok, status, data = upload_file(
                args.url,
                path,
                field_name=args.field_name,
                token=token,
                max_retries=args.retries,
                retry_delay=args.retry_delay,
                timeout=args.timeout,
            )

            entry = {"index": idx, "file": path, "ok": bool(ok), "status": status, "response": data}
            print(json.dumps(entry), file=logfh)
            logfh.flush()

            if ok:
                print("  uploaded")
                time.sleep(args.wait)
            else:
                print(f"  FAILED -> {status} {data}")
                all_ok = False
                # continue uploading remaining files unless you prefer to stop on first failure

    print("Done. Log appended to:", args.log_file)
    return 0 if all_ok else 3


if __name__ == "__main__":
    raise SystemExit(main())
