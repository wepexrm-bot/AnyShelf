import logging
import secrets
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Header, UploadFile, File
from jose import jwt
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session

from app.config import settings
from app.core.models import User
from app.core.mail import send_email, render_code_email
from app.core.storage import upload_bytes, get_presigned_url, delete_file
from app.db.database import get_db

router = APIRouter()
logger = logging.getLogger("Anyshelf.auth")
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def generate_verification_code() -> str:
    return f"{secrets.randbelow(1000000):06d}"


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)
    display_name: str | None = None


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class VerifyEmailRequest(BaseModel):
    email: EmailStr
    code: str = Field(min_length=6, max_length=6)


class ResendVerificationRequest(BaseModel):
    email: EmailStr


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    email: EmailStr
    token: str
    password: str = Field(min_length=8)


class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str = Field(min_length=8)


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    email: str
    display_name: str | None = None
    is_verified: bool = False


def create_access_token(user_id: str) -> str:
    expire = datetime.utcnow() + timedelta(minutes=settings.access_token_expire_minutes)
    payload = {"sub": user_id, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)


def _token_response(user: User) -> TokenResponse:
    return TokenResponse(
        access_token=create_access_token(user.id),
        email=user.email,
        display_name=user.display_name,
        is_verified=user.is_verified,
    )


def _get_user_by_email(db: Session, email: str) -> User | None:
    return db.query(User).filter(User.email == email).first()


@router.post("/register")
def register(body: RegisterRequest, db: Session = Depends(get_db)):
    if _get_user_by_email(db, body.email):
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        email=body.email,
        hashed_password=pwd_context.hash(body.password),
        display_name=body.display_name,
        is_verified=False,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    _issue_verification_code(db, user)
    return {"status": "verification_sent", "email": user.email}


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = _get_user_by_email(db, body.email)
    if not user or not pwd_context.verify(body.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    if not user.is_verified:
        raise HTTPException(
            status_code=403,
            detail="Please verify your email before logging in. Check your inbox for the verification code.",
        )

    return _token_response(user)


def _issue_verification_code(db: Session, user: User, purpose: str = "finish signing up") -> str:
    code = generate_verification_code()
    user.verification_token = code
    user.verification_token_expires = datetime.utcnow() + timedelta(
        minutes=settings.email_verification_link_ttl_minutes
    )
    db.commit()

    send_email(
        user.email,
        "Your Anyshelf verification code",
        render_code_email(code, purpose),
    )
    return code


@router.post("/verify-email")
def verify_email(body: VerifyEmailRequest, db: Session = Depends(get_db)):
    user = _get_user_by_email(db, body.email)
    if not user:
        raise HTTPException(status_code=400, detail="No account found for that email")

    if user.is_verified:
        return {"status": "already_verified", "email": user.email}

    if not user.verification_token or user.verification_token != body.code:
        raise HTTPException(status_code=400, detail="Invalid verification code")

    if user.verification_token_expires and user.verification_token_expires < datetime.utcnow():
        raise HTTPException(status_code=400, detail="Verification code has expired")

    user.is_verified = True
    user.verification_token = None
    user.verification_token_expires = None
    db.commit()
    return {"status": "verified", "email": user.email}


@router.post("/resend-verification")
def resend_verification(body: ResendVerificationRequest, db: Session = Depends(get_db)):
    """Resend the verification code for a registered-but-unverified account."""
    user = _get_user_by_email(db, body.email)
    if not user:
        return {"status": "sent"}
    if user.is_verified:
        return {"status": "already_verified"}

    _issue_verification_code(db, user, purpose="resend your Anyshelf verification code")
    return {"status": "sent"}


@router.post("/forgot-password")
def forgot_password(body: ForgotPasswordRequest, db: Session = Depends(get_db)):
    user = _get_user_by_email(db, body.email)
    # Always report success to avoid user enumeration.
    if not user:
        return {"status": "sent"}

    code = generate_verification_code()
    user.reset_token = code
    user.reset_token_expires = datetime.utcnow() + timedelta(
        minutes=settings.password_reset_link_ttl_minutes
    )
    db.commit()

    send_email(
        user.email,
        "Reset your Anyshelf password",
        render_code_email(code, "reset your password"),
    )
    return {"status": "sent"}


@router.post("/reset-password")
def reset_password(body: ResetPasswordRequest, db: Session = Depends(get_db)):
    user = _get_user_by_email(db, body.email)
    if not user or user.reset_token != body.token:
        raise HTTPException(status_code=400, detail="Invalid reset code")

    if user.reset_token_expires and user.reset_token_expires < datetime.utcnow():
        raise HTTPException(status_code=400, detail="Reset code has expired")

    user.hashed_password = pwd_context.hash(body.password)
    user.reset_token = None
    user.reset_token_expires = None
    db.commit()
    return {"status": "reset"}


def get_current_user(authorization: str | None = Header(default=None), db: Session = Depends(get_db)) -> User:
    """Resolve the authenticated user from the Authorization header.

    Used by protected routes. In dev (no header) falls back to the demo user
    so existing flows keep working; production should require a token.
    """
    from app.api.deps import DEMO_USER_ID

    if not authorization or not authorization.lower().startswith("bearer "):
        user = db.get(User, DEMO_USER_ID)
        if user:
            return user
        raise HTTPException(status_code=401, detail="Not authenticated")

    token = authorization.split(" ", 1)[1].strip()
    try:
        payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
        user_id = payload.get("sub")
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid token payload")

    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="User no longer exists")
    return user


@router.post("/change-password")
def change_password(
    body: ChangePasswordRequest,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not pwd_context.verify(body.old_password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    user.hashed_password = pwd_context.hash(body.new_password)
    db.commit()
    return {"status": "changed"}


@router.get("/me")
def me(user: User = Depends(get_current_user)):
    return {
        "id": user.id,
        "email": user.email,
        "display_name": user.display_name,
        "is_verified": user.is_verified,
        "banner_url": get_presigned_url(user.banner_key) if user.banner_key else None,
        "created_at": user.created_at.isoformat() if user.created_at else None,
    }


@router.post("/me/banner")
def upload_me_banner(
    file: UploadFile = File(...),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    contents = file.file.read()
    if not contents:
        raise HTTPException(status_code=400, detail="Empty file")

    storage_key = f"banners/{user.id}/page.jpg"
    upload_bytes(contents, storage_key, content_type=file.content_type or "image/jpeg")

    old_key = user.banner_key
    user.banner_key = storage_key
    db.commit()
    if old_key:
        try:
            delete_file(old_key)
        except Exception:
            pass
    return {"banner_url": get_presigned_url(storage_key)}


@router.delete("/me/banner")
def remove_me_banner(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    old_key = user.banner_key
    user.banner_key = None
    db.commit()
    if old_key:
        try:
            delete_file(old_key)
        except Exception:
            pass
    return {"banner_url": None}
