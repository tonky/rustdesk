#!/usr/bin/env python3
"""
scripts/fetch_enve.py: Pure zero-dependency SigV4 downloader to fetch the hermetic
enve binary directly from private S3/R2 binary cache buckets.
"""
import os
import sys
import urllib.request
import hashlib
import hmac
import datetime

def fetch_enve(destination: str):
    access_key = os.environ.get("AWS_ACCESS_KEY_ID")
    secret_key = os.environ.get("AWS_SECRET_ACCESS_KEY")
    endpoint = os.environ.get("AWS_ENDPOINT_URL", "https://847959617b8d3ada9eb84238a37f56ec.r2.cloudflarestorage.com").rstrip("/")
    bucket = os.environ.get("ENVE_CACHE_BUCKET", "rustdesk-enve-cache")
    key = os.environ.get("ENVE_BINARY_KEY", "bin/enve")

    if not access_key or not secret_key:
        print("❌ Error: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set.", file=sys.stderr)
        sys.exit(1)

    url = f"{endpoint}/{bucket}/{key}"
    host = endpoint.split("://")[-1].split("/")[0]
    path = f"/{bucket}/{key}"

    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")

    payload_hash = hashlib.sha256(b"").hexdigest()
    canonical_headers = f"host:{host}\nx-amz-content-sha256:{payload_hash}\nx-amz-date:{amz_date}\n"
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    canonical_request = f"GET\n{path}\n\n{canonical_headers}\n{signed_headers}\n{payload_hash}"

    region = os.environ.get("AWS_REGION", "auto")
    service = "s3"
    scope = f"{date_stamp}/{region}/{service}/aws4_request"
    string_to_sign = f"AWS4-HMAC-SHA256\n{amz_date}\n{scope}\n{hashlib.sha256(canonical_request.encode('utf-8')).hexdigest()}"

    def sign(k, msg):
        return hmac.new(k, msg.encode("utf-8"), hashlib.sha256).digest()

    k_date = sign(("AWS4" + secret_key).encode("utf-8"), date_stamp)
    k_region = sign(k_date, region)
    k_service = sign(k_region, service)
    k_signing = sign(k_service, "aws4_request")
    signature = hmac.new(k_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()

    auth_header = (
        f"AWS4-HMAC-SHA256 Credential={access_key}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    req = urllib.request.Request(
        url,
        headers={
            "Host": host,
            "x-amz-date": amz_date,
            "x-amz-content-sha256": payload_hash,
            "Authorization": auth_header,
        },
    )

    print(f"📥 Fetching enve from {url} -> {destination}...")
    os.makedirs(os.path.dirname(os.path.abspath(destination)), exist_ok=True)
    with urllib.request.urlopen(req) as resp, open(destination, "wb") as f:
        f.write(resp.read())

    os.chmod(destination, 0o755)
    size_mb = os.path.getsize(destination) / (1024 * 1024)
    print(f"✅ Downloaded enve ({size_mb:.2f} MB) to {destination}")

if __name__ == "__main__":
    dest = sys.argv[1] if len(sys.argv) > 1 else "/usr/local/bin/enve"
    fetch_enve(dest)
