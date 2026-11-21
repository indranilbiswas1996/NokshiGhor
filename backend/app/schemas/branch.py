
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class BranchResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    branch_name: str
    branch_code: str | None = None
    address: str | None = None
    phone: str | None = None
    email: str | None = None
    is_default: bool
    is_active: bool
    created_at: datetime
    updated_at: datetime | None = None


class BranchListResponse(BaseModel):
    branches: list[BranchResponse]


from pydantic import BaseModel, ConfigDict, Field


class BranchCreateRequest(BaseModel):
    branch_name: str = Field(min_length=1, max_length=150)
    branch_code: str | None = Field(default=None, max_length=30)
    address: str | None = None
    phone: str | None = Field(default=None, max_length=30)
    email: str | None = Field(default=None, max_length=254)


class BranchCreateResponse(BaseModel):
    branch: BranchResponse


class BranchUpdateRequest(BaseModel):
    branch_name: str = Field(min_length=1, max_length=150)
    branch_code: str | None = Field(default=None, max_length=30)
    address: str | None = None
    phone: str | None = Field(default=None, max_length=30)
    email: str | None = Field(default=None, max_length=254)

class BranchStatusUpdateRequest(BaseModel):
    is_active: bool
