
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.dependencies import (
    get_db,
    get_current_user,
    get_current_business,
)
from app.schemas.branch import (
    BranchListResponse,
    BranchCreateRequest,
    BranchCreateResponse,
    BranchUpdateRequest,
)
from uuid import UUID
from app.services.branch_service import get_branches, create_branch, update_branch


router = APIRouter(
    prefix="/branches",
    tags=["Branch Management"],
)


@router.get("", response_model=BranchListResponse)
def list_branches(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    branches = get_branches(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
    )

    return {"branches": branches}

@router.post("", response_model=BranchCreateResponse, status_code=201)
def add_branch(
    payload: BranchCreateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    branch = create_branch(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
        payload=payload,
    )

    return {"branch": branch}

@router.put("/{branch_id}", response_model=BranchCreateResponse)
def edit_branch(
    branch_id: UUID,
    payload: BranchUpdateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    branch = update_branch(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
        branch_id=str(branch_id),
        payload=payload,
    )

    return {"branch": branch}
