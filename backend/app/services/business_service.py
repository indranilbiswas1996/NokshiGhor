
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.orm import Session


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