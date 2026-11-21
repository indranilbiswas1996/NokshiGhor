
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class OwnerResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    membership_id: UUID
    user_id: UUID
    full_name: str
    email: str
    phone: str | None = None
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


class OwnerProfileUpdateResponse(BaseModel):
    user_id: UUID
    profile: dict
