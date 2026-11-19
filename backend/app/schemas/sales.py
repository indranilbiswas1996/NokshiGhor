
from datetime import date
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class SaleItemCreate(BaseModel):
    product_id: UUID
    quantity: Decimal = Field(gt=0, max_digits=14, decimal_places=3)
    unit_price: Decimal | None = Field(
        default=None, ge=0, max_digits=14, decimal_places=2
    )
    discount_amount: Decimal = Field(
        default=Decimal("0"), ge=0, max_digits=14, decimal_places=2
    )


class SaleCreateRequest(BaseModel):
    customer_id: UUID | None = None
    warehouse_id: UUID | None = None
    sale_date: date = Field(default_factory=date.today)
    due_date: date | None = None
    discount_amount: Decimal = Field(
        default=Decimal("0"), ge=0, max_digits=14, decimal_places=2
    )
    shipping_charge: Decimal = Field(
        default=Decimal("0"), ge=0, max_digits=14, decimal_places=2
    )
    other_charges: Decimal = Field(
        default=Decimal("0"), ge=0, max_digits=14, decimal_places=2
    )
    notes: str | None = None
    items: list[SaleItemCreate] = Field(min_length=1)

    @model_validator(mode="after")
    def validate_dates(self):
        if self.due_date is not None and self.due_date < self.sale_date:
            raise ValueError("Due date cannot be earlier than sale date")
        return self


class SaleItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    product_id: UUID
    product_name_snapshot: str
    sku_snapshot: str | None
    quantity: Decimal
    unit_id: UUID
    unit_price: Decimal
    discount_amount: Decimal
    tax_rate: Decimal
    tax_amount: Decimal
    line_total: Decimal


class SaleResponse(BaseModel):
    id: UUID
    sale_number: str
    sale_date: date
    due_date: date | None
    sale_status: str
    payment_status: str
    subtotal: Decimal
    discount_amount: Decimal
    tax_amount: Decimal
    shipping_charge: Decimal
    other_charges: Decimal
    round_off: Decimal
    total_amount: Decimal
    paid_amount: Decimal
    customer_name_snapshot: str
    shop_name_snapshot: str
    items: list[SaleItemResponse]
