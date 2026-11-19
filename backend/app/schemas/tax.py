
from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


# ---------------------------------------------------------
# TAX TYPE
# ---------------------------------------------------------

class TaxTypeCreate(BaseModel):
    tax_code: str = Field(min_length=1, max_length=40)
    tax_name: str = Field(min_length=1, max_length=120)
    description: str | None = None


class TaxTypeResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tax_code: str
    tax_name: str
    description: str | None
    is_active: bool


# ---------------------------------------------------------
# TAX COMPONENT
# ---------------------------------------------------------

class TaxComponentCreate(BaseModel):
    component_code: str = Field(min_length=1, max_length=40)
    component_name: str = Field(min_length=1, max_length=120)
    jurisdiction_level: str
    description: str | None = None

    @model_validator(mode="after")
    def validate_jurisdiction(self):
        allowed = {"central", "state", "integrated", "local", "other"}
        if self.jurisdiction_level not in allowed:
            raise ValueError("Invalid tax component jurisdiction")
        return self


class TaxComponentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    component_code: str
    component_name: str
    jurisdiction_level: str
    description: str | None
    is_active: bool


# ---------------------------------------------------------
# TAX PROFILE
# ---------------------------------------------------------

class TaxProfileCreate(BaseModel):
    profile_code: str = Field(min_length=1, max_length=60)
    profile_name: str = Field(min_length=1, max_length=150)
    description: str | None = None


class TaxProfileResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    profile_code: str
    profile_name: str
    description: str | None
    is_active: bool


# ---------------------------------------------------------
# TAX PROFILE VERSION COMPONENT
# ---------------------------------------------------------

class TaxProfileComponentCreate(BaseModel):
    tax_component_id: UUID
    tax_rate: Decimal = Field(ge=0, le=100, max_digits=7, decimal_places=4)
    calculation_order: int = Field(default=1, ge=1, le=32767)


class TaxProfileComponentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tax_component_id: UUID
    component_code_snapshot: str
    component_name_snapshot: str
    jurisdiction_snapshot: str
    tax_rate: Decimal
    calculation_order: int


# ---------------------------------------------------------
# TAX PROFILE VERSION
# ---------------------------------------------------------

class TaxProfileVersionCreate(BaseModel):
    version_number: int = Field(ge=1)
    tax_type_id: UUID
    calculation_mode: str = "exclusive"
    rounding_mode: str = "half_up"
    rounding_precision: int = Field(default=2, ge=0, le=4)
    effective_from: datetime | None = None
    effective_to: datetime | None = None
    version_notes: str | None = None
    components: list[TaxProfileComponentCreate] = Field(min_length=1)

    @model_validator(mode="after")
    def validate_version(self):
        if self.calculation_mode not in {"exclusive", "inclusive"}:
            raise ValueError("Invalid tax calculation mode")

        if self.rounding_mode not in {"half_up", "half_even", "down", "up"}:
            raise ValueError("Invalid rounding mode")

        if (
            self.effective_from is not None
            and self.effective_to is not None
            and self.effective_to <= self.effective_from
        ):
            raise ValueError("effective_to must be later than effective_from")

        component_ids = [item.tax_component_id for item in self.components]
        if len(component_ids) != len(set(component_ids)):
            raise ValueError("Duplicate tax components are not allowed")

        orders = [item.calculation_order for item in self.components]
        if len(orders) != len(set(orders)):
            raise ValueError("Duplicate calculation orders are not allowed")

        return self


class TaxProfileVersionResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    tax_profile_id: UUID
    version_number: int
    tax_type_id: UUID
    calculation_mode: str
    rounding_mode: str
    rounding_precision: int
    effective_from: datetime | None
    effective_to: datetime | None
    version_status: str
    version_notes: str | None
    components: list[TaxProfileComponentResponse] = Field(default_factory=list)


# ---------------------------------------------------------
# COMMON LIST RESPONSE
# ---------------------------------------------------------

class TaxProfileListResponse(BaseModel):
    items: list[TaxProfileResponse]
    total_count: int


class TaxTypeListResponse(BaseModel):
    items: list[TaxTypeResponse]
    total_count: int


class TaxComponentListResponse(BaseModel):
    items: list[TaxComponentResponse]
    total_count: int
