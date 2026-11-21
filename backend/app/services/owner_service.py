
import logging

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session
from app.core.security import hash_password
from app.schemas.owner import OwnerCreateRequest

logger = logging.getLogger(__name__)


def list_owners(
    db: Session,
    business_id: str,
    user_id: str,
) -> dict:
    """
    List all Owner memberships for the selected Business.

    Authorization is enforced inside the secure PostgreSQL
    SECURITY DEFINER function.
    """

    try:
        result = db.execute(
            text("""
                SELECT public.fn_owner_list(
                    CAST(:business_id AS UUID),
                    CAST(:user_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "user_id": user_id,
            },
        )

        owners = result.scalar_one()

        return {"owners": owners or []}

    except SQLAlchemyError as exc:
        db.rollback()

        original_error = exc.orig
        sqlstate = (
            getattr(
                getattr(original_error, "diag", None),
                "sqlstate",
                None,
            )
            or getattr(original_error, "sqlstate", None)
        )

        if sqlstate == "P0001":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Active Owner access is required",
            ) from exc

        logger.exception("Failed to list Business Owners")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to retrieve Business Owners",
        ) from exc


def create_owner(
    db: Session,
    business_id: str,
    user_id: str,
    payload: OwnerCreateRequest,
) -> dict:
    """
    Create a new Owner membership for the selected Business.
    Reuse an existing active User when the email already exists.
    """

    try:
        password_hash = (
            hash_password(payload.password)
            if payload.password
            else None
        )

        result = db.execute(
            text("""
                SELECT public.fn_owner_add(
                    CAST(:business_id AS UUID),
                    CAST(:user_id AS UUID),
                    :full_name,
                    :email,
                    :phone,
                    :password_hash
                )
            """),
            {
                "business_id": business_id,
                "user_id": user_id,
                "full_name": payload.full_name.strip(),
                "email": payload.email.strip().lower(),
                "phone": payload.phone.strip() if payload.phone else None,
                "password_hash": password_hash,
            },
        )

        owner = result.scalar_one()
        db.commit()

        return owner

    except SQLAlchemyError as exc:
        db.rollback()

        original_error = exc.orig
        sqlstate = (
            getattr(
                getattr(original_error, "diag", None),
                "sqlstate",
                None,
            )
            or getattr(original_error, "sqlstate", None)
        )

        if sqlstate == "P0001":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=str(original_error).split("\n")[0],
            ) from exc

        logger.exception("Failed to create Business Owner")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to create Business Owner",
        ) from exc

def set_owner_status(
    db: Session,
    business_id: str,
    user_id: str,
    membership_id: str,
    new_status: str,
) -> dict:
    """
    Activate or deactivate an Owner membership
    within the selected Business.
    """

    try:
        result = db.execute(
            text("""
                SELECT public.fn_owner_set_status(
                    CAST(:business_id AS UUID),
                    CAST(:user_id AS UUID),
                    CAST(:membership_id AS UUID),
                    :status
                )
            """),
            {
                "business_id": business_id,
                "user_id": user_id,
                "membership_id": membership_id,
                "status": new_status,
            },
        )

        owner = result.scalar_one()
        db.commit()

        return owner

    except SQLAlchemyError as exc:
        db.rollback()

        original_error = exc.orig
        sqlstate = (
            getattr(
                getattr(original_error, "diag", None),
                "sqlstate",
                None,
            )
            or getattr(original_error, "sqlstate", None)
        )

        if sqlstate == "P0001":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=str(original_error).split("\n")[0],
            ) from exc

        logger.exception("Failed to update Business Owner status")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to update Business Owner status",
        ) from exc

def update_owner_profile(
    db: Session,
    business_id: str,
    user_id: str,
    full_name: str,
    phone: str | None,
) -> dict:
    """
    Update only the authenticated Owner's own name and phone.
    Email and password cannot be changed through this function.
    """

    try:
        result = db.execute(
            text("""
                SELECT public.fn_owner_profile_update(
                    CAST(:business_id AS UUID),
                    CAST(:user_id AS UUID),
                    :full_name,
                    :phone
                )
            """),
            {
                "business_id": business_id,
                "user_id": user_id,
                "full_name": full_name.strip(),
                "phone": phone.strip() if phone else None,
            },
        )

        profile = result.scalar_one()
        db.commit()

        return profile

    except SQLAlchemyError as exc:
        db.rollback()

        original_error = exc.orig
        sqlstate = (
            getattr(
                getattr(original_error, "diag", None),
                "sqlstate",
                None,
            )
            or getattr(original_error, "sqlstate", None)
        )

        if sqlstate == "P0001":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=str(original_error).split("\n")[0],
            ) from exc

        logger.exception("Failed to update Owner profile")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to update Owner profile",
        ) from exc
