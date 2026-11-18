from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.security import verify_password


def authenticate_user(
    db: Session,
    email: str,
    password: str,
):
    statement = text("""
        SELECT id, full_name, email, password_hash, status
        FROM public.fn_auth_user_by_email(:email)
    """)

    user = db.execute(
        statement,
        {"email": email.strip().lower()},
    ).mappings().first()

    if user is None:
        return None

    if not verify_password(password, user["password_hash"]):
        return None

    if user["status"] != "active":
        return None

    return user