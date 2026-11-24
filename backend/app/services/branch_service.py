
from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from app.core.security import hash_password

def get_branches(
    db: Session,
    business_id: str,
    actor_user_id: str,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_branch_list(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
            },
        )

        return [dict(row) for row in result.mappings().all()]

    except SQLAlchemyError as exc:
        db.rollback()

        if getattr(exc.orig, "sqlstate", None) == "P0001":
            raise HTTPException(
                status_code=403,
                detail="Active Owner access is required.",
            )

        raise HTTPException(
            status_code=503,
            detail="Unable to retrieve branches.",
        )


def get_accessible_branches(
    db: Session,
    business_id: str,
    actor_user_id: str,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_accessible_branch_list(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
            },
        )
        return [dict(row) for row in result.mappings().all()]
    except SQLAlchemyError as exc:
        db.rollback()
        if getattr(exc.orig, "sqlstate", None) == "P0001":
            raise HTTPException(status_code=403, detail="Active business access is required.")
        raise HTTPException(status_code=503, detail="Unable to retrieve accessible branches.")


def create_branch(
    db: Session,
    business_id: str,
    actor_user_id: str,
    payload,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_branch_create(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    :branch_name,
                    :branch_code,
                    :address,
                    :phone,
                    :email
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
                "branch_name": payload.branch_name,
                "branch_code": payload.branch_code,
                "address": payload.address,
                "phone": payload.phone,
                "email": payload.email,
            },
        )

        branch = dict(result.mappings().one())
        db.commit()
        return branch

    except SQLAlchemyError as exc:
        db.rollback()

        if getattr(exc.orig, "sqlstate", None) == "P0001":
            diag = getattr(exc.orig, "diag", None)
            message = (
                getattr(diag, "message_primary", None)
                or str(exc.orig).split("\nCONTEXT:", 1)[0]
            ).strip()

            if "Owner access" in message:
                raise HTTPException(
                    status_code=403,
                    detail="Active Owner access is required.",
                )

            raise HTTPException(status_code=400, detail=message)

        raise HTTPException(
            status_code=503,
            detail="Unable to create branch.",
        )


def update_branch(
    db: Session,
    business_id: str,
    actor_user_id: str,
    branch_id: str,
    payload,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_branch_update(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    CAST(:branch_id AS UUID),
                    :branch_name,
                    :branch_code,
                    :address,
                    :phone,
                    :email
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
                "branch_id": branch_id,
                "branch_name": payload.branch_name,
                "branch_code": payload.branch_code,
                "address": payload.address,
                "phone": payload.phone,
                "email": payload.email,
            },
        )

        branch = dict(result.mappings().one())
        db.commit()
        return branch

    except SQLAlchemyError as exc:
        db.rollback()

        if getattr(exc.orig, "sqlstate", None) == "P0001":
            diag = getattr(exc.orig, "diag", None)
            message = (
                getattr(diag, "message_primary", None)
                or str(exc.orig).split("\nCONTEXT:", 1)[0]
            ).strip()

            if "Owner access" in message:
                raise HTTPException(
                    status_code=403,
                    detail="Active Owner access is required.",
                )

            if "Branch not found" in message:
                raise HTTPException(
                    status_code=404,
                    detail="Branch not found.",
                )

            if "branch with this code already exists" in message.lower():
                raise HTTPException(
                    status_code=409,
                    detail="This branch code is already used by another branch. Please enter a different code.",
                )

            if "branch with this name already exists" in message.lower():
                raise HTTPException(
                    status_code=409,
                    detail="This branch name is already used. Please enter a different name.",
                )

            raise HTTPException(
                status_code=400,
                detail=message,
            )

        raise HTTPException(
            status_code=503,
            detail="Unable to update branch.",
        )


def set_branch_status(
    db: Session,
    business_id: str,
    actor_user_id: str,
    branch_id: str,
    is_active: bool,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_branch_set_status(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    CAST(:branch_id AS UUID),
                    :is_active
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
                "branch_id": branch_id,
                "is_active": is_active,
            },
        ).mappings().first()

        db.commit()

        if not result:
            raise HTTPException(
                status_code=500,
                detail="Unable to update branch status.",
            )

        return dict(result)

    except HTTPException:
        raise

    except SQLAlchemyError as exc:
        db.rollback()

        print("BRANCH STATUS ERROR:", repr(exc.orig))
        print("SQLSTATE:", getattr(exc.orig, "sqlstate", None))
        print(
            "DB MESSAGE:",
            getattr(
                getattr(exc.orig, "diag", None),
                "message_primary",
                None,
            ),
        )
        print(
            "DB CONTEXT:",
            getattr(
                getattr(exc.orig, "diag", None),
                "context",
                None,
            ),
        )

        if getattr(exc.orig, "sqlstate", None) == "P0001":
            diag = getattr(exc.orig, "diag", None)
            message = (
                getattr(diag, "message_primary", None)
                or str(exc.orig).split("\nCONTEXT:", 1)[0]
            ).strip()

            if "Owner access" in message:
                raise HTTPException(
                    status_code=403,
                    detail="Active Owner access is required.",
                )

            if "Branch not found" in message:
                raise HTTPException(
                    status_code=404,
                    detail="Branch not found.",
                )

            raise HTTPException(
                status_code=400,
                detail=message,
            )

        raise HTTPException(
            status_code=503,
            detail="Unable to update branch status.",
        )

def set_default_branch(
    db: Session,
    business_id: str,
    actor_user_id: str,
    branch_id: str,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_branch_set_default(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    CAST(:branch_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
                "branch_id": branch_id,
            },
        ).mappings().first()

        if result is None:
            raise HTTPException(
                status_code=404,
                detail="Branch not found.",
            )

        db.commit()
        return dict(result)

    except HTTPException:
        db.rollback()
        raise

    except SQLAlchemyError as exc:
        db.rollback()

        message = (
            getattr(getattr(exc.orig, "diag", None), "message_primary", None)
            or str(exc.orig)
        )

        if "Active Owner access is required" in message:
            status_code = 403
        elif "Branch not found" in message:
            status_code = 404
        elif "Active business not found" in message:
            status_code = 404
        else:
            status_code = 400

        raise HTTPException(
            status_code=status_code,
            detail=message.split("\n")[0],
        ) from exc

def assign_branch_admin(
    db: Session,
    business_id: str,
    actor_user_id: str,
    branch_id: str,
    business_user_id: str,
    notes: str | None = None,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_branch_assign_admin(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    CAST(:branch_id AS UUID),
                    CAST(:business_user_id AS UUID),
                    :notes
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
                "branch_id": branch_id,
                "business_user_id": business_user_id,
                "notes": notes,
            },
        ).mappings().one()

        db.commit()
        return dict(result)

    except HTTPException:
        db.rollback()
        raise

    except SQLAlchemyError as exc:
        db.rollback()

        message = "Unable to assign Branch Admin."

        if getattr(exc, "orig", None) is not None:
            message = (
                getattr(getattr(exc.orig, "diag", None), "message_primary", None)
                or str(exc.orig)
            ).split("\nCONTEXT:")[0]

        if "already assigned" in message.lower():
            raise HTTPException(status_code=409, detail=message)

        if "only an active business owner" in message.lower():
            raise HTTPException(status_code=403, detail=message)

        if "inactive or does not belong" in message.lower():
            raise HTTPException(status_code=404, detail=message)

        if "not an active branch admin" in message.lower():
            raise HTTPException(status_code=400, detail=message)

        raise HTTPException(status_code=400, detail=message)

def get_branch_admin_candidates(
    db: Session,
    business_id: str,
    actor_user_id: str,
    branch_id: str,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_branch_admin_candidates(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    CAST(:branch_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
                "branch_id": branch_id,
            },
        )

        candidates = [
            dict(row)
            for row in result.mappings().all()
        ]

        return {"candidates": candidates}

    except SQLAlchemyError as exc:
        db.rollback()
        error_message = str(exc.orig).lower() if exc.orig else str(exc).lower()

        if "only an active owner" in error_message:
            raise HTTPException(
                status_code=403,
                detail="Only an active Owner can view Branch Admin candidates.",
            )

        if "active branch not found" in error_message:
            raise HTTPException(
                status_code=404,
                detail="Active Branch not found.",
            )

        if "business not found or inactive" in error_message:
            raise HTTPException(
                status_code=404,
                detail="Business not found or inactive.",
            )

        raise HTTPException(
            status_code=500,
            detail="Unable to load Branch Admin candidates.",
        )
def create_branch_admin(
    db: Session,
    business_id: str,
    actor_user_id: str,
    full_name: str,
    email: str,
    phone: str | None,
    password: str,
):
    try:
        password_hash = hash_password(password)

        result = db.execute(
            text("""
                SELECT public.fn_branch_admin_add(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    :full_name,
                    :email,
                    :phone,
                    :password_hash
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
                "full_name": full_name,
                "email": email,
                "phone": phone,
                "password_hash": password_hash,
            },
        )

        admin = result.scalar_one()
        db.commit()

        return {"admin": admin}

    except SQLAlchemyError as exc:
        db.rollback()
        error_message = str(exc.orig).lower() if exc.orig else str(exc).lower()
        print("BRANCH ADMIN DATABASE ERROR:", repr(exc.orig or exc))
        if "only an active owner" in error_message:
            raise HTTPException(
                status_code=403,
                detail="Only an active Owner can create a Branch Admin.",
            )
        if "business not found or inactive" in error_message:
            raise HTTPException(status_code=404, detail="Business not found or inactive.")
        if "already has a membership" in error_message:
            raise HTTPException(status_code=409, detail="User already belongs to this Business.")
        if "branch admin role not configured" in error_message:
            raise HTTPException(status_code=400, detail="Branch Admin role is not configured.")
        if "name and email are required" in error_message:
            raise HTTPException(status_code=400, detail="Name and email are required.")

        raise HTTPException(
            status_code=500,
            detail="Unable to create Branch Admin.",
        )


def get_branch_admins(
    db: Session,
    business_id: str,
    actor_user_id: str,
    branch_id: str,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_branch_admin_list(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    CAST(:branch_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
                "branch_id": branch_id,
            },
        )

        admins = [dict(row) for row in result.mappings().all()]

        return {"admins": admins}

    except SQLAlchemyError as exc:
        db.rollback()
        error_message = str(exc.orig or exc)

        if "Only an active Business Owner" in error_message:
            raise HTTPException(
                status_code=403,
                detail="Only an active Business Owner can view Branch Admins.",
            )

        if "Branch not found" in error_message:
            raise HTTPException(
                status_code=404,
                detail="Branch not found.",
            )

        raise HTTPException(
            status_code=500,
            detail="Unable to load Branch Admins.",
        )
def get_master_branch_admins(
    db: Session,
    business_id: str,
    actor_user_id: str,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_master_branch_admin_list(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
            },
        ).mappings().all()

        return {
            "admins": [dict(row) for row in result]
        }

    except SQLAlchemyError as exc:
        db.rollback()

        error_message = str(getattr(exc, "orig", exc))

        if "Only an active Business Owner" in error_message:
            raise HTTPException(
                status_code=403,
                detail="Only an active Business Owner can view Master Branch Admins.",
            )

        if "Business is inactive or unavailable" in error_message:
            raise HTTPException(
                status_code=404,
                detail="Business is inactive or unavailable.",
            )

        raise HTTPException(
            status_code=500,
            detail="Failed to load Master Branch Admins.",
        )

def get_unassigned_branch_admins(
    db: Session,
    business_id: str,
    actor_user_id: str,
):
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_unassigned_branch_admin_list(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "actor_user_id": actor_user_id,
            },
        ).mappings().all()

        return {
            "admins": [dict(row) for row in result]
        }

    except SQLAlchemyError as exc:
        db.rollback()

        error_message = str(getattr(exc, "orig", exc))

        if "Only an active Business Owner" in error_message:
            raise HTTPException(
                status_code=403,
                detail="Only an active Business Owner can view unassigned Branch Admins.",
            )

        if "Business is inactive or unavailable" in error_message:
            raise HTTPException(
                status_code=404,
                detail="Business is inactive or unavailable.",
            )

        raise HTTPException(
            status_code=500,
            detail="Failed to load unassigned Branch Admins.",
        )

def get_branch_admin_audit_history(
    db: Session,
    business_id,
    actor_user_id,
    business_user_id,
):
    try:
        result = db.execute(
            text("""
                SELECT public.fn_branch_admin_audit_history(
                    CAST(:business_id AS UUID),
                    CAST(:actor_user_id AS UUID),
                    CAST(:business_user_id AS UUID)
                )
            """),
            {
                "business_id": str(business_id),
                "actor_user_id": str(actor_user_id),
                "business_user_id": str(business_user_id),
            },
        )

        history = result.scalar_one()

        return history

    except SQLAlchemyError as exc:
        db.rollback()

        error_message = str(exc.orig)

        if "Only an active Business Owner" in error_message:
            raise HTTPException(
                status_code=403,
                detail="Only an active Business Owner can view Admin audit history.",
            )

        if "Branch Admin not found" in error_message:
            raise HTTPException(
                status_code=404,
                detail="Branch Admin not found in this Business.",
            )

        raise HTTPException(
            status_code=500,
            detail="Unable to load Branch Admin audit history.",
        )
def revoke_branch_admin(
    db: Session,
    business_id: str,
    requester_user_id: str,
    assignment_id: str,
    revocation_reason: str | None = None,
):
    try:
        result = db.execute(
            text("""
                SELECT public.fn_branch_admin_revoke(
                    CAST(:business_id AS UUID),
                    CAST(:requester_user_id AS UUID),
                    CAST(:assignment_id AS UUID),
                    :revocation_reason
                )
            """),
            {
                "business_id": business_id,
                "requester_user_id": requester_user_id,
                "assignment_id": assignment_id,
                "revocation_reason": revocation_reason,
            },
        )

        response = result.scalar_one()
        db.commit()
        return response

    except SQLAlchemyError:
        db.rollback()
        raise