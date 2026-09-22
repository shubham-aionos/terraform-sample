import datetime
import hashlib
import hmac
import json
import os
import urllib.parse
import urllib.request

REGION = os.environ["AWS_REGION"]
IMDS_BASE = "http://169.254.169.254/latest"


def _imds_token():
    request = urllib.request.Request(
        IMDS_BASE + "/api/token",
        method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        return response.read().decode()


def _credentials():
    token = _imds_token()
    request = urllib.request.Request(
        IMDS_BASE + "/meta-data/iam/security-credentials/",
        headers={"X-aws-ec2-metadata-token": token},
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        role = response.read().decode().strip()

    request = urllib.request.Request(
        IMDS_BASE + "/meta-data/iam/security-credentials/" + role,
        headers={"X-aws-ec2-metadata-token": token},
    )
    with urllib.request.urlopen(request, timeout=2) as response:
        return json.loads(response.read())


def _signing_key(secret_key, date_stamp, region, service):
    k_date = hmac.new(
        ("AWS4" + secret_key).encode(), date_stamp.encode(), hashlib.sha256
    ).digest()
    k_region = hmac.new(k_date, region.encode(), hashlib.sha256).digest()
    k_service = hmac.new(k_region, service.encode(), hashlib.sha256).digest()
    return hmac.new(k_service, b"aws4_request", hashlib.sha256).digest()


def signed_request(method, host, path, service, body=b"", extra_headers=None):
    credentials = _credentials()
    now = datetime.datetime.now(datetime.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    date_stamp = now.strftime("%Y%m%d")
    payload_hash = hashlib.sha256(body).hexdigest()

    headers = {
        "host": host,
        "x-amz-date": amz_date,
        "x-amz-security-token": credentials["Token"],
        "x-amz-content-sha256": payload_hash,
    }
    if extra_headers:
        headers.update(extra_headers)

    canonical_headers = "".join(
        key.lower() + ":" + " ".join(value.strip().split()) + "\n"
        for key, value in sorted(headers.items())
    )
    signed_headers = ";".join(key.lower() for key in sorted(headers))
    canonical_request = "\n".join(
        [
            method,
            path,
            "",
            canonical_headers,
            signed_headers,
            payload_hash,
        ]
    )

    credential_scope = f"{date_stamp}/{REGION}/{service}/aws4_request"
    string_to_sign = "\n".join(
        [
            "AWS4-HMAC-SHA256",
            amz_date,
            credential_scope,
            hashlib.sha256(canonical_request.encode()).hexdigest(),
        ]
    )
    signature = hmac.new(
        _signing_key(credentials["SecretAccessKey"], date_stamp, REGION, service),
        string_to_sign.encode(),
        hashlib.sha256,
    ).hexdigest()

    headers["Authorization"] = (
        "AWS4-HMAC-SHA256 Credential="
        + credentials["AccessKeyId"]
        + "/"
        + credential_scope
        + ", SignedHeaders="
        + signed_headers
        + ", Signature="
        + signature
    )

    request = urllib.request.Request(
        "https://" + host + path,
        data=body,
        method=method,
        headers=headers,
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return response.read()


def get_s3_object(bucket, key):
    host = f"{bucket}.s3.{REGION}.amazonaws.com"
    path = "/" + "/".join(urllib.parse.quote(part, safe="") for part in key.split("/"))
    return signed_request("GET", host, path, "s3")


def get_secret(secret_arn):
    host = f"secretsmanager.{REGION}.amazonaws.com"
    body = json.dumps({"SecretId": secret_arn}, separators=(",", ":")).encode()
    response = signed_request(
        "POST",
        host,
        "/",
        "secretsmanager",
        body,
        {
            "content-type": "application/x-amz-json-1.1",
            "x-amz-target": "secretsmanager.GetSecretValue",
        },
    )
    payload = json.loads(response)
    return json.loads(payload["SecretString"])
