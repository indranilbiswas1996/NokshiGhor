from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, get_db
from app.schemas.super_admin import (
    SuperAdminBusinessCreateRequest,
    SuperAdminBusinessListResponse,
    SuperAdminBusinessResponse,
    SuperAdminBusinessStatusRequest,
)
from app.services import super_admin_service

router = APIRouter(prefix="/super-admin", tags=["Super Admin"])


@router.get("/businesses", response_model=SuperAdminBusinessListResponse)
def get_businesses(
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
):
    return {
        "businesses": super_admin_service.list_businesses(
            db=db,
            actor_user_id=str(current_user["id"]),
        )
    }


@router.post("/businesses", response_model=SuperAdminBusinessResponse, status_code=201)
def add_business(
    payload: SuperAdminBusinessCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
):
    return super_admin_service.create_business(
        db=db,
        actor_user_id=str(current_user["id"]),
        business_name=payload.business_name,
        business_type=payload.business_type,
    )


@router.patch("/businesses/{business_id}/status", response_model=SuperAdminBusinessResponse)
def update_business_status(
    business_id: UUID,
    payload: SuperAdminBusinessStatusRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
):
    return super_admin_service.set_business_status(
        db=db,
        actor_user_id=str(current_user["id"]),
        business_id=str(business_id),
        new_status=payload.status,
    )
