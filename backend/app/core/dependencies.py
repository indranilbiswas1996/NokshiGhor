
from typing import Annotated
from uuid import UUID

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.tokens import decode_access_token


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
