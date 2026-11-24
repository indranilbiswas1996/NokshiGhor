from datetime import datetime

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.security import hash_password


def change_password(db: Session, user_id: str, new_password: str) -> None:
    try:
        db.execute(
            text("""
                SELECT public.fn_auth_password_change(
                    CAST(:user_id AS UUID),
                    :password_hash
                )
            """),
            {
                "user_id": user_id,
                "password_hash": hash_password(new_password),
            },
        )
        db.commit()
    except SQLAlchemyError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to update password.",
        ) from exc


def create_password_reset(
    db: Session,
    email: str,
    token_hash: str,
    expires_at: datetime,
) -> dict | None:
    try:
        row = db.execute(
            text("""
                SELECT user_id, email
                FROM public.fn_auth_password_reset_request(
                    :email,
                    CAST(:token_hash AS CHAR(64)),
                    :expires_at
                )
            """),
            {
                "email": email.strip().lower(),
                "token_hash": token_hash,
                "expires_at": expires_at,
            },
        ).mappings().first()
        db.commit()
        return dict(row) if row else None
    except SQLAlchemyError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to process password recovery.",
        ) from exc


def complete_password_reset(
    db: Session,
    token_hash: str,
    new_password: str,
) -> bool:
    try:
        result = db.execute(
            text("""
                SELECT public.fn_auth_password_reset_complete(
                    CAST(:token_hash AS CHAR(64)),
                    :password_hash
                )
            """),
            {
                "token_hash": token_hash,
                "password_hash": hash_password(new_password),
            },
        ).scalar_one()
        db.commit()
        return bool(result)
    except SQLAlchemyError as exc:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to reset password.",
        ) from exc
