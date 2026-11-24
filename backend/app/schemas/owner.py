
import base64
import binascii
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


MAX_PROFILE_PICTURE_BYTES = 50 * 1024
PROFILE_PICTURE_PREFIXES = (
    "data:image/jpeg;base64,",
    "data:image/png;base64,",
    "data:image/webp;base64,",
)


def validate_profile_picture(value: str | None) -> str | None:
    if value is None:
        return None

    prefix = next(
        (item for item in PROFILE_PICTURE_PREFIXES if value.startswith(item)),
        None,
    )
    if prefix is None:
        raise ValueError("Profile picture must be a JPEG, PNG, or WebP image.")

    try:
        image_bytes = base64.b64decode(value[len(prefix):], validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError("Profile picture data is invalid.") from exc

    if not image_bytes or len(image_bytes) > MAX_PROFILE_PICTURE_BYTES:
        raise ValueError("Profile picture must be no larger than 50 KB.")

    return value


class OwnerResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    membership_id: UUID
    user_id: UUID
    full_name: str
    email: str
    phone: str | None = None
    profile_picture: str | None = None
    status: Literal["active", "inactive"]
    created_at: datetime
    updated_at: datetime | None = None


class OwnerListResponse(BaseModel):
    owners: list[OwnerResponse]


class OwnerCreateRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=150)
    email: str = Field(min_length=3, max_length=255)
    phone: str | None = Field(default=None, max_length=30)
    password: str | None = Field(default=None, min_length=8, max_length=128)
    profile_picture: str | None = Field(default=None, max_length=70000)

    @field_validator("profile_picture")
    @classmethod
    def validate_picture(cls, value: str | None) -> str | None:
        return validate_profile_picture(value)


class OwnerCreateResponse(BaseModel):
    membership_id: UUID
    user_id: UUID
    full_name: str
    email: str
    status: Literal["active"]
    new_user_created: bool

class OwnerStatusUpdateRequest(BaseModel):
    status: Literal["active", "inactive"]


class OwnerStatusUpdateResponse(BaseModel):
    membership_id: UUID
    status: Literal["active", "inactive"]

class OwnerProfileUpdateRequest(BaseModel):
    full_name: str = Field(min_length=1, max_length=150)
    phone: str | None = Field(default=None, max_length=30)
    profile_picture: str | None = Field(default=None, max_length=70000)

    @field_validator("profile_picture")
    @classmethod
    def validate_picture(cls, value: str | None) -> str | None:
        return validate_profile_picture(value)


class OwnerProfileUpdateResponse(BaseModel):
    user_id: UUID
    profile: dict
