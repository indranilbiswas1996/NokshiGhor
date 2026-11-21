
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
