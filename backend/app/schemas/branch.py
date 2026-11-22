
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict
from typing import Any

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
class BranchAdminAssignmentRequest(BaseModel):
    business_user_id: UUID
    notes: str | None = None


class BranchAdminAssignmentResponse(BaseModel):
    assignment: dict

class BranchAdminCreateRequest(BaseModel):
    full_name: str
    email: str
    phone: str | None = None
    password: str


class BranchAdminCreateResponse(BaseModel):
    admin: dict

class BranchAdminListResponse(BaseModel):
    admins: list[dict] = []
class MasterBranchAdminListResponse(BaseModel):
    admins: list[dict] = []


class BranchAdminAuditHistoryResponse(BaseModel):
    admin: dict[str, Any]
    current_branch_assignments: list[dict[str, Any]]
    history: list[dict[str, Any]]
class BranchAdminRevokeRequest(BaseModel):
    revocation_reason: str | None = None