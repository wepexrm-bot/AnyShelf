from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Central app configuration, loaded from environment variables / .env"""

    app_name: str = "Anyshelf API"
    environment: str = "development"

    # Database
    database_url: str = "postgresql://cloudread:cloudread@localhost:5432/cloudread"

    # Object storage (S3-compatible)
    s3_bucket: str = "cloudread-books"
    s3_region: str = "us-east-1"
    s3_endpoint_url: str | None = None  # set for MinIO/local dev

    # Auth
    jwt_secret: str = "change-me-in-production"
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7

    # Email (SMTP). In dev, verification/reset links are logged and echoed
    # back in the API response instead of being sent.
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_user: str | None = None
    smtp_password: str | None = None
    smtp_from: str = "Anyshelf <no-reply@anyshelf.app>"
    email_verification_link_ttl_minutes: int = 60
    password_reset_link_ttl_minutes: int = 30

    # OCR
    ocr_confidence_threshold: float = 0.65  # below this, fall back to fixed-layout mode
    use_cloud_ocr: bool = False  # False = Tesseract locally, True = cloud OCR API

    class Config:
        env_file = ".env"


settings = Settings()
