from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import get_current_user, require_permission
from app.schemas.tax import (
    TaxProfileVersionCreate,
    TaxProfileVersionResponse,
)
from app.schemas.tax import (
    TaxTypeCreate,
    TaxTypeResponse,
    TaxComponentCreate,
    TaxComponentResponse,
    TaxProfileCreate,
    TaxProfileResponse,
)
from app.services.tax_service import (
    create_tax_profile_version,
    get_tax_profile_version,
)
from app.services.tax_master_service import (
    create_tax_type,
    create_tax_component,
    create_tax_profile,
)


router = APIRouter(prefix="/tax", tags=["Tax"])


@router.post(
    "/profiles/{tax_profile_id}/versions",
    response_model=TaxProfileVersionResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_profile_version(
    tax_profile_id: UUID,
    payload: TaxProfileVersionCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("tax.manage")),
):
    version_data = create_tax_profile_version(
        db=db,
        user_id=current_user["id"],
        business_id=current_business["id"],
        tax_profile_id=tax_profile_id,
        version_number=payload.version_number,
        tax_type_id=payload.tax_type_id,
        calculation_mode=payload.calculation_mode,
        rounding_mode=payload.rounding_mode,
        rounding_precision=payload.rounding_precision,
        effective_from=payload.effective_from,
        effective_to=payload.effective_to,
        version_notes=payload.version_notes,
        components=[
            item.model_dump(mode="json")
            for item in payload.components
        ],
    )

    return version_data

@router.get(
    "/profiles/{tax_profile_id}/versions/{version_id}",
    response_model=TaxProfileVersionResponse,
    status_code=status.HTTP_200_OK,
)
def get_profile_version(
    tax_profile_id: UUID,
    version_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("tax.view")),
):
    version_data = get_tax_profile_version(
        db=db,
        user_id=current_user["id"],
        business_id=current_business["id"],
        version_id=version_id,
    )

    if version_data is None:
        from fastapi import HTTPException

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tax profile version not found",
        )

    if str(version_data["tax_profile_id"]) != str(tax_profile_id):
        from fastapi import HTTPException

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tax profile version not found",
        )

    return version_data

@router.post(
    "/types",
    response_model=TaxTypeResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_tax_type_route(
    payload: TaxTypeCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("tax.manage")),
):
    record_id = create_tax_type(
        db=db,
        user_id=current_user["id"],
        business_id=current_business["id"],
        tax_code=payload.tax_code,
        tax_name=payload.tax_name,
        description=payload.description,
    )

    return {
        "id": record_id,
        "tax_code": payload.tax_code,
        "tax_name": payload.tax_name,
        "description": payload.description,
        "is_active": True,
    }


@router.post(
    "/components",
    response_model=TaxComponentResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_tax_component_route(
    payload: TaxComponentCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("tax.manage")),
):
    record_id = create_tax_component(
        db=db,
        user_id=current_user["id"],
        business_id=current_business["id"],
        component_code=payload.component_code,
        component_name=payload.component_name,
        jurisdiction_level=payload.jurisdiction_level,
        description=payload.description,
    )

    return {
        "id": record_id,
        "component_code": payload.component_code,
        "component_name": payload.component_name,
        "jurisdiction_level": payload.jurisdiction_level,
        "description": payload.description,
        "is_active": True,
    }


@router.post(
    "/profiles",
    response_model=TaxProfileResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_tax_profile_route(
    payload: TaxProfileCreate,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("tax.manage")),
):
    record_id = create_tax_profile(
        db=db,
        user_id=current_user["id"],
        business_id=current_business["id"],
        profile_code=payload.profile_code,
        profile_name=payload.profile_name,
        description=payload.description,
    )

    return {
        "id": record_id,
        "profile_code": payload.profile_code,
        "profile_name": payload.profile_name,
        "description": payload.description,
        "is_active": True,
    }