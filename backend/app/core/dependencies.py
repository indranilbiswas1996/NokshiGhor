
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.tokens import decode_access_token
from app.services.permission_service import user_has_permission

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
    db: Annotated[Session, Depends(get_db)],
):
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired authentication token",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if credentials is None:
        raise unauthorized

    try:
        payload = decode_access_token(credentials.credentials)
        user_id = UUID(payload["sub"])
    except (jwt.InvalidTokenError, ValueError, KeyError, TypeError):
        raise unauthorized

    statement = text("""
        SELECT id, full_name, email, status
        FROM public.fn_auth_user_by_id(:user_id)
    """)

    try:
        user = db.execute(
            statement,
            {"user_id": user_id},
        ).mappings().first()
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Authentication service temporarily unavailable",
        )

    if user is None or user["status"] != "active":
        raise unauthorized

    return user
def get_current_business(
    current_user=Depends(get_current_user),
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ] = None,
    db: Session = Depends(get_db),
):
    unauthorized = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="A valid business selection is required",
        headers={"WWW-Authenticate": "Bearer"},
    )

    if credentials is None:
        raise unauthorized

    try:
        payload = decode_access_token(credentials.credentials)
        business_id = UUID(payload["business_id"])
    except (jwt.InvalidTokenError, ValueError, KeyError, TypeError):
        raise unauthorized

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

    try:
        business = db.execute(
            statement,
            {
                "user_id": current_user["id"],
                "business_id": business_id,
            },
        ).mappings().first()
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Business access service temporarily unavailable",
        )

    if business is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Business access is no longer available",
        )

    return business
def require_permission(permission_key: str):
    def permission_checker(
        current_user=Depends(get_current_user),
        current_business=Depends(get_current_business),
        db: Session = Depends(get_db),
    ):
        allowed = user_has_permission(
            db=db,
            user_id=current_user["id"],
            business_id=current_business["id"],
            permission_key=permission_key,
        )

        if not allowed:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have permission to perform this action",
            )

        return current_business

    return permission_checker