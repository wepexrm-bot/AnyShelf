"""Thin wrapper around S3-compatible object storage.

Books are streamed from here on read rather than being fully copied to the
client device, which is what lets users open a PDF "from anywhere" without
needing local storage of the full file.
"""

import logging
import os

import boto3
from botocore.config import Config

from app.config import settings

logger = logging.getLogger("Anyshelf.storage")

_r2_access = os.environ.get("R2_ACCESS_KEY_ID") or os.environ.get("AWS_ACCESS_KEY_ID") or None
_r2_secret = os.environ.get("R2_SECRET_ACCESS_KEY") or os.environ.get("AWS_SECRET_ACCESS_KEY") or None

_s3 = boto3.client(
    "s3",
    region_name=settings.s3_region,
    endpoint_url=settings.s3_endpoint_url,  # None -> real AWS S3; set for local MinIO
    aws_access_key_id=_r2_access,
    aws_secret_access_key=_r2_secret,
    config=Config(signature_version="s3v4"),
)
logger.warning(
    "S3 client initialized: bucket=%s region=%s endpoint=%s creds=%s",
    settings.s3_bucket,
    settings.s3_region,
    settings.s3_endpoint_url,
    "set" if (_r2_access and _r2_secret) else "MISSING",
)


def upload_file(local_path: str, storage_key: str, content_type: str | None = None) -> str:
    extra_args = {"ContentType": content_type} if content_type else {}
    _s3.upload_file(local_path, settings.s3_bucket, storage_key, ExtraArgs=extra_args)
    return storage_key


def upload_bytes(data: bytes, storage_key: str, content_type: str = "application/octet-stream") -> str:
    _s3.put_object(Bucket=settings.s3_bucket, Key=storage_key, Body=data, ContentType=content_type)
    return storage_key


def get_presigned_url(storage_key: str, expires_in: int = 3600, inline: bool = False) -> str:
    """Generate a temporary URL the client can stream the file from directly,
    instead of proxying large PDF bytes through the API server.

    `inline=True` sets Content-Disposition: inline so browsers render the
    file in the page rather than downloading it.
    """
    params: dict = {"Bucket": settings.s3_bucket, "Key": storage_key}
    if inline:
        params["ResponseContentDisposition"] = "inline"
    return _s3.generate_presigned_url(
        "get_object",
        Params=params,
        ExpiresIn=expires_in,
    )


def download_bytes(storage_key: str) -> bytes:
    obj = _s3.get_object(Bucket=settings.s3_bucket, Key=storage_key)
    return obj["Body"].read()


def delete_file(storage_key: str) -> None:
    _s3.delete_object(Bucket=settings.s3_bucket, Key=storage_key)
