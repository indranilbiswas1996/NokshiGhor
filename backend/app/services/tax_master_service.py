import logging
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session


logger = logging.getLogger(__name__)


def _create_tax_master_record(
    db: Session,
    function_name: str,
    params: dict,
) -> UUID:
    allowed_functions = {
        "fn_create_tax_type",
        "fn_create_tax_component",
        "fn_create_tax_profile",
    }

    if function_name not in allowed_functions:
        raise ValueError("Invalid tax master function")

    placeholders = ", ".join(
        f":{key}" for key in params
    )

    query = text(
        f"SELECT public.{function_name}({placeholders})"
    )

    try:
        result = db.execute(query, params).scalar_one()
        db.commit()
        return result

    except IntegrityError as exc:
        db.rollback()
        logger.warning(
            "Tax master duplicate or constraint violation: %s",
            function_name,
        )
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="A tax master record with these details already exists.",
        ) from exc

    except SQLAlchemyError as exc:
        db.rollback()
        logger.exception(
            "Tax master creation failed: %s",
            function_name,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to create tax master record.",
        ) from exc


def create_tax_type(
    db: Session,
    user_id: UUID,
    business_id: UUID,
    tax_code: str,
    tax_name: str,
    description: str | None,
) -> UUID:
    return _create_tax_master_record(
        db=db,
        function_name="fn_create_tax_type",
        params={
            "p_user_id": user_id,
            "p_business_id": business_id,
            "p_tax_code": tax_code,
            "p_tax_name": tax_name,
            "p_description": description,
        },
    )


def create_tax_component(
    db: Session,
    user_id: UUID,
    business_id: UUID,
    component_code: str,
    component_name: str,
    jurisdiction_level: str,
    description: str | None,
) -> UUID:
    return _create_tax_master_record(
        db=db,
        function_name="fn_create_tax_component",
        params={
            "p_user_id": user_id,
            "p_business_id": business_id,
            "p_component_code": component_code,
            "p_component_name": component_name,
            "p_jurisdiction_level": jurisdiction_level,
            "p_description": description,
        },
    )


def create_tax_profile(
    db: Session,
    user_id: UUID,
    business_id: UUID,
    profile_code: str,
    profile_name: str,
    description: str | None,
) -> UUID:
    return _create_tax_master_record(
        db=db,
        function_name="fn_create_tax_profile",
        params={
            "p_user_id": user_id,
            "p_business_id": business_id,
            "p_profile_code": profile_code,
            "p_profile_name": profile_name,
            "p_description": description,
        },
    )