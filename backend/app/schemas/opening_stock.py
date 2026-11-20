from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator


class OpeningStockItemCreate(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0, max_digits=14, decimal_places=3)
    unit_cost: Decimal = Field(default=Decimal("0"), ge=0, max_digits=14, decimal_places=2)
    notes: str | None = Field(default=None, max_length=1000)


class OpeningStockCreateRequest(BaseModel):
    warehouse_id: UUID
    opening_date: date = Field(default_factory=date.today)
    notes: str | None = Field(default=None, max_length=2000)
    items: list[OpeningStockItemCreate] = Field(min_length=1, max_length=500)

    @field_validator("items")
    @classmethod
    def validate_unique_products(cls, items):
        product_ids = [item.product_id for item in items]

        if len(product_ids) != len(set(product_ids)):
            raise ValueError("Duplicate products are not allowed")

        return items


class OpeningStockResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    message: str
    document_id: UUID
    opening_status: str
class OpeningStockUpdateRequest(BaseModel):
    warehouse_id: UUID
    opening_date: date
    notes: str | None = Field(default=None, max_length=2000)
    items: list[OpeningStockItemCreate] = Field(min_length=1, max_length=500)

    @field_validator("items")
    @classmethod
    def validate_unique_products(cls, items):
        product_ids = [item.product_id for item in items]
        if len(product_ids) != len(set(product_ids)):
            raise ValueError("Duplicate products are not allowed")
        return items
class OpeningStockDraftItemResponse(BaseModel):
    product_id: UUID
    quantity: Decimal
    unit_id: UUID
    unit_cost: Decimal
    notes: str | None = None


class OpeningStockDraftResponse(BaseModel):
    document_id: UUID
    warehouse_id: UUID
    opening_number: str
    opening_date: date
    opening_status: Literal["draft"]
    notes: str | None = None
    created_at: datetime
    updated_at: datetime
    items: list[OpeningStockDraftItemResponse]


class OpeningStockDraftListResponse(BaseModel):
    drafts: list[OpeningStockDraftResponse]