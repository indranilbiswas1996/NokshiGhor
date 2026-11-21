
from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session


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
            message = str(exc.orig)

            if "Owner access" in message:
                raise HTTPException(
                    status_code=403,
                    detail="Active Owner access is required.",
                )

            raise HTTPException(
                status_code=400,
                detail=message,
            )

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

