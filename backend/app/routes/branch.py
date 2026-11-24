
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
    BranchStatusUpdateRequest,
    BranchAdminAssignmentRequest,
    BranchAdminAssignmentResponse,
    BranchAdminCreateRequest,
    BranchAdminCreateResponse,
    BranchAdminListResponse,
    MasterBranchAdminListResponse,
    UnassignedBranchAdminListResponse,
    BranchAdminAuditHistoryResponse,
    BranchAdminRevokeRequest,
)
from uuid import UUID
from app.services import branch_service
from app.services.branch_service import (
    get_branches,
    create_branch,
    update_branch,
    set_branch_status,
    set_default_branch,
    assign_branch_admin,
    get_branch_admin_candidates,
    create_branch_admin,
)


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


@router.get("/accessible", response_model=BranchListResponse)
def list_accessible_branches(
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    return {
        "branches": branch_service.get_accessible_branches(
            db=db,
            business_id=str(current_business["id"]),
            actor_user_id=str(current_user["id"]),
        )
    }

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

@router.patch("/{branch_id}/status", response_model=BranchCreateResponse)
def update_branch_status(
    branch_id: UUID,
    payload: BranchStatusUpdateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    branch = set_branch_status(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
        branch_id=str(branch_id),
        is_active=payload.is_active,
    )

    return {"branch": branch}

@router.patch("/{branch_id}/default", response_model=BranchCreateResponse)
def set_branch_default(
    branch_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    branch = set_default_branch(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
        branch_id=str(branch_id),
    )

    return {"branch": branch}


@router.post("/{branch_id}/admins", response_model=BranchAdminAssignmentResponse)
def create_branch_admin_assignment(
    branch_id: UUID,
    payload: BranchAdminAssignmentRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    assignment = assign_branch_admin(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
        branch_id=str(branch_id),
        business_user_id=str(payload.business_user_id),
        notes=payload.notes,
    )

    return {"assignment": assignment}


@router.get("/{branch_id}/admin-candidates")
def list_branch_admin_candidates(
    branch_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    return get_branch_admin_candidates(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
        branch_id=str(branch_id),
    )

@router.post(
    "/admins",
    response_model=BranchAdminCreateResponse,
)
def create_branch_admin_user(
    payload: BranchAdminCreateRequest,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    return create_branch_admin(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
        full_name=payload.full_name,
        email=payload.email,
        phone=payload.phone,
        password=payload.password,
    )


@router.get(
    "/{branch_id}/admins",
    response_model=BranchAdminListResponse,
)
def get_branch_admins(
    branch_id: UUID,
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user),
    current_business=Depends(get_current_business),
):
    return branch_service.get_branch_admins(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
        branch_id=str(branch_id),
    )
@router.get(
    "/master-admins",
    response_model=MasterBranchAdminListResponse,
)
def get_master_branch_admins(
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
    current_business: dict = Depends(get_current_business),
):
    return branch_service.get_master_branch_admins(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
    )

@router.get(
    "/unassigned-admins",
    response_model=UnassignedBranchAdminListResponse,
)
def get_unassigned_branch_admins(
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
    current_business: dict = Depends(get_current_business),
):
    return branch_service.get_unassigned_branch_admins(
        db=db,
        business_id=str(current_business["id"]),
        actor_user_id=str(current_user["id"]),
    )


@router.get(
    "/master-admins/{business_user_id}/audit-history",
    response_model=BranchAdminAuditHistoryResponse,
)
def get_branch_admin_audit_history(
    business_user_id: UUID,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
    current_business: dict = Depends(get_current_business),
):
    return branch_service.get_branch_admin_audit_history(
        db=db,
        business_id=current_business["id"],
        actor_user_id=current_user["id"],
        business_user_id=business_user_id,
    )

@router.post("/admin-assignments/{assignment_id}/revoke")
def revoke_branch_admin(
    assignment_id: str,
    payload: BranchAdminRevokeRequest,
    db: Session = Depends(get_db),
    current_user: dict = Depends(get_current_user),
    current_business: dict = Depends(get_current_business),
):
    return branch_service.revoke_branch_admin(
        db=db,
        business_id=current_business["id"],
        requester_user_id=current_user["id"],
        assignment_id=assignment_id,
        revocation_reason=payload.revocation_reason,
    )