from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session


def _raise_super_admin_error(exc: SQLAlchemyError) -> None:
    original_error = getattr(exc, "orig", None)
    sqlstate = getattr(original_error, "sqlstate", None)
    message = str(original_error or exc).split("\n", 1)[0]

    if sqlstate == "P0001" and "super admin" in message.lower():
        raise HTTPException(status_code=403, detail="Super Admin access is required.") from exc

    if sqlstate == "P0001":
        raise HTTPException(status_code=400, detail=message) from exc

    raise HTTPException(status_code=503, detail="Super Admin service is unavailable.") from exc


def list_businesses(db: Session, actor_user_id: str) -> list[dict]:
    try:
        result = db.execute(
            text("""
                SELECT *
                FROM public.fn_super_admin_business_list(
                    CAST(:actor_user_id AS UUID)
                )
            """),
            {"actor_user_id": actor_user_id},
        )
        return [dict(row) for row in result.mappings().all()]
    except SQLAlchemyError as exc:
        db.rollback()
        _raise_super_admin_error(exc)


def create_business(
    db: Session,
    actor_user_id: str,
    business_name: str,
    business_type: str,
) -> dict:
    try:
        result = db.execute(
            text("""
                SELECT public.fn_super_admin_business_create(
                    CAST(:actor_user_id AS UUID),
                    :business_name,
                    :business_type
                )
            """),
            {
                "actor_user_id": actor_user_id,
                "business_name": business_name,
                "business_type": business_type,
            },
        ).scalar_one()
        db.commit()
        return result
    except SQLAlchemyError as exc:
        db.rollback()
        _raise_super_admin_error(exc)


def set_business_status(
    db: Session,
    actor_user_id: str,
    business_id: str,
    new_status: str,
) -> dict:
    try:
        result = db.execute(
            text("""
                SELECT public.fn_super_admin_business_set_status(
                    CAST(:actor_user_id AS UUID),
                    CAST(:business_id AS UUID),
                    :status
                )
            """),
            {
                "actor_user_id": actor_user_id,
                "business_id": business_id,
                "status": new_status,
            },
        ).scalar_one()
        db.commit()
        return result
    except SQLAlchemyError as exc:
        db.rollback()
        _raise_super_admin_error(exc)
