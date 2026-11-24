from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field


class SuperAdminBusinessCreateRequest(BaseModel):
    business_name: str = Field(min_length=1, max_length=200)
    business_type: Literal["electrical", "interior", "both", "other"]


class SuperAdminBusinessStatusRequest(BaseModel):
    status: Literal["active", "inactive"]


class SuperAdminBusinessResponse(BaseModel):
    id: UUID
    business_name: str
    business_type: str
    status: str


class SuperAdminBusinessListResponse(BaseModel):
    businesses: list[SuperAdminBusinessResponse]
