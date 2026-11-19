from uuid import UUID

from sqlalchemy import text
from sqlalchemy.orm import Session


def user_has_permission(
    db: Session,
    user_id: UUID,
    business_id: UUID,
    permission_key: str,
) -> bool:
    statement = text("""
        SELECT public.fn_auth_user_has_permission(
            :user_id,
            :business_id,
            :permission_key
        )
    """)

    result = db.execute(
        statement,
        {
            "user_id": user_id,
            "business_id": business_id,
            "permission_key": permission_key,
        },
    )

    return bool(result.scalar())