from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.routes.auth import get_current_user
from app.core.models import UserSettings, User
from app.db.database import get_db

router = APIRouter()

VALID_THEMES = {"light", "dark", "sepia", "night", "mint", "rose"}
VALID_FONTS = {"serif", "sans", "dyslexic", "lora", "merriweather", "garamond", "roboto", "opensans", "atkinson"}
VALID_MARGINS = {"small", "medium", "large"}
VALID_MODES = {"scroll", "paginate"}
VALID_LAYOUTS = {"spread", "single"}


class SettingsUpdate(BaseModel):
    theme: str | None = None
    custom_background: str | None = Field(default=None, max_length=7)
    font_family: str | None = None
    font_size: int | None = Field(default=None, ge=14, le=32)
    line_spacing: float | None = Field(default=None, ge=1.0, le=2.5)
    margins: str | None = None
    reading_mode: str | None = None
    page_layout: str | None = None


def _get_or_create_settings(db: Session, user_id: str) -> UserSettings:
    settings = db.query(UserSettings).filter(UserSettings.user_id == user_id).first()
    if not settings:
        settings = UserSettings(user_id=user_id)
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return settings


def _settings_to_dict(s: UserSettings) -> dict:
    return {
        "theme": s.theme,
        "custom_background": s.custom_background,
        "font_family": s.font_family,
        "font_size": s.font_size,
        "line_spacing": s.line_spacing,
        "margins": s.margins,
        "reading_mode": s.reading_mode,
        "page_layout": s.page_layout,
    }


@router.get("/")
def get_settings(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    settings = _get_or_create_settings(db, user.id)
    return _settings_to_dict(settings)


@router.put("/")
def update_settings(body: SettingsUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    settings = _get_or_create_settings(db, user.id)

    updates = body.model_dump(exclude_unset=True)
    if "theme" in updates and updates["theme"] not in VALID_THEMES:
        raise HTTPException(status_code=400, detail=f"Invalid theme. Must be one of {sorted(VALID_THEMES)}")
    if "font_family" in updates and updates["font_family"] not in VALID_FONTS:
        raise HTTPException(status_code=400, detail=f"Invalid font. Must be one of {sorted(VALID_FONTS)}")
    if "margins" in updates and updates["margins"] not in VALID_MARGINS:
        raise HTTPException(status_code=400, detail=f"Invalid margins. Must be one of {sorted(VALID_MARGINS)}")
    if "reading_mode" in updates and updates["reading_mode"] not in VALID_MODES:
        raise HTTPException(status_code=400, detail=f"Invalid mode. Must be one of {sorted(VALID_MODES)}")
    if "page_layout" in updates and updates["page_layout"] not in VALID_LAYOUTS:
        raise HTTPException(status_code=400, detail=f"Invalid page layout. Must be one of {sorted(VALID_LAYOUTS)}")

    for key, value in updates.items():
        setattr(settings, key, value)

    db.commit()
    db.refresh(settings)
    return _settings_to_dict(settings)
