
from uuid import UUID

from pydantic import BaseModel


class BusinessResponse(BaseModel):
    id: UUID
    business_name: str
    business_type: str
    status: str
    role_name: str


class BusinessListResponse(BaseModel):
    businesses: list[BusinessResponse]
    total: int

class BusinessSelectRequest(BaseModel):
    business_id: UUID


class BusinessSelectResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    business: BusinessResponse