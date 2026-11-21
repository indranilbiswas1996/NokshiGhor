
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.orm import Session

from sqlalchemy.exc import SQLAlchemyError
from fastapi import HTTPException

def get_user_businesses(
    db: Session,
    user_id: UUID,
):
    statement = text("""
        SELECT
            business_id AS id,
            business_name,
            business_type,
            business_status AS status,
            role_name
        FROM public.fn_auth_user_businesses(:user_id)
    """)

    result = db.execute(
        statement,
        {"user_id": user_id},
    ).mappings().all()

    return result
def get_user_business(
    db: Session,
    user_id: UUID,
    business_id: UUID,
):
    statement = text("""
        SELECT
            business_id AS id,
            business_name,
            business_type,
            business_status AS status,
            role_name
        FROM public.fn_auth_user_businesses(:user_id)
        WHERE business_id = :business_id
        LIMIT 1
    """)

    result = db.execute(
        statement,
        {
            "user_id": user_id,
            "business_id": business_id,
        },
    ).mappings().first()

    return result


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

        if (
            "inactive or does not belong" in message.lower()
            or "does not belong to this business" in message.lower()
        ):
            raise HTTPException(status_code=404, detail=message)

        if "not an active branch admin" in message.lower():
            raise HTTPException(status_code=400, detail=message)

        raise HTTPException(status_code=400, detail=message)

