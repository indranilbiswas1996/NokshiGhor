
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import (
    get_current_user,
    get_current_business,
)
from app.schemas.owner import (
    OwnerListResponse,
    OwnerCreateRequest,
    OwnerCreateResponse,
    OwnerStatusUpdateRequest,
    OwnerStatusUpdateResponse,
    OwnerProfileUpdateRequest,
    OwnerProfileUpdateResponse,
)
from app.services.owner_service import (
    list_owners,
    create_owner,
    set_owner_status,
    update_owner_profile,
)


router = APIRouter(prefix="/owners", tags=["Owner Management"])


@router.get(
    "",
    response_model=OwnerListResponse,
)
def get_owners(
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    return list_owners(
        db=db,
        business_id=str(current_business["id"]),
        user_id=str(current_user["id"]),
    )


@router.post(
    "",
    response_model=OwnerCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
def add_owner(
    payload: OwnerCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    return create_owner(
        db=db,
        business_id=str(current_business["id"]),
        user_id=str(current_user["id"]),
        payload=payload,
    )
@router.patch(
    "/{membership_id}/status",
    response_model=OwnerStatusUpdateResponse,
)
def update_owner_status(
    membership_id: str,
    payload: OwnerStatusUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    return set_owner_status(
        db=db,
        business_id=str(current_business["id"]),
        user_id=str(current_user["id"]),
        membership_id=membership_id,
        new_status=payload.status,
    )

@router.patch(
    "/me/profile",
    response_model=OwnerProfileUpdateResponse,
)
def edit_my_owner_profile(
    payload: OwnerProfileUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    return update_owner_profile(
        db=db,
        business_id=str(current_business["id"]),
        user_id=str(current_user["id"]),
        full_name=payload.full_name,
        phone=payload.phone,
        profile_picture=payload.profile_picture,
        update_picture="profile_picture" in payload.model_fields_set,
    )
