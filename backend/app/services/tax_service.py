
import json
import logging
from datetime import datetime
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


def create_tax_profile_version(
    db: Session,
    user_id: UUID,
    business_id: UUID,
    tax_profile_id: UUID,
    version_number: int,
    tax_type_id: UUID,
    calculation_mode: str,
    rounding_mode: str,
    rounding_precision: int,
    effective_from: datetime | None,
    effective_to: datetime | None,
    version_notes: str | None,
    components: list[dict],
) -> dict:
    try:
        create_result = db.execute(
            text("""
                SELECT public.fn_create_tax_profile_version(
                    :user_id,
                    :business_id,
                    :tax_profile_id,
                    :version_number,
                    :tax_type_id,
                    :calculation_mode,
                    :rounding_mode,
                    :rounding_precision,
                    :effective_from,
                    :effective_to,
                    :version_notes,
                    CAST(:components AS JSONB)
                )
            """),
            {
                "user_id": str(user_id),
                "business_id": str(business_id),
                "tax_profile_id": str(tax_profile_id),
                "version_number": version_number,
                "tax_type_id": str(tax_type_id),
                "calculation_mode": calculation_mode,
                "rounding_mode": rounding_mode,
                "rounding_precision": rounding_precision,
                "effective_from": effective_from,
                "effective_to": effective_to,
                "version_notes": version_notes,
                "components": json.dumps([
                    {
                        "tax_component_id": str(
                            item["tax_component_id"]
                        ),
                        "tax_rate": str(item["tax_rate"]),
                        "calculation_order": item.get(
                            "calculation_order", 1
                        ),
                    }
                    for item in components
                ]),
            },
        )

        version_id = create_result.scalar_one()

        read_result = db.execute(
            text("""
                SELECT public.fn_get_tax_profile_version(
                    :user_id,
                    :business_id,
                    :version_id
                )
            """),
            {
                "user_id": str(user_id),
                "business_id": str(business_id),
                "version_id": str(version_id),
            },
        )

        version_data = read_result.scalar_one_or_none()

        if version_data is None:
            raise RuntimeError(
                "Created tax profile version could not be retrieved"
            )

        db.commit()
        return version_data

    except SQLAlchemyError as exc:
        db.rollback()
        logger.exception("Tax profile version creation failed")

        error_message = str(exc.orig).lower()

        if (
            "active business membership required" in error_message
            or "tax permission denied" in error_message
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Tax permission denied",
            ) from exc

        if any(
            message in error_message
            for message in (
                "active tax profile not found",
                "active tax type not found",
                "active tax component not found",
                "duplicate tax components",
                "duplicate calculation orders",
                "invalid version number",
                "invalid calculation mode",
                "invalid rounding mode",
                "invalid effective period",
                "invalid tax component rate",
                "invalid calculation order",
                "at least one tax component",
            )
        ):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Invalid tax profile version configuration",
            ) from exc

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to create tax profile version",
        ) from exc

    except Exception as exc:
        db.rollback()
        logger.exception("Unexpected tax profile version creation error")

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unable to create tax profile version",
        ) from exc

def get_tax_profile_version(
    db: Session,
    user_id: UUID,
    business_id: UUID,
    version_id: UUID,
) -> dict | None:
    try:
        result = db.execute(
            text("""
                SELECT public.fn_get_tax_profile_version(
                    :p_user_id,
                    :p_business_id,
                    :p_version_id
                )
            """),
            {
                "p_user_id": str(user_id),
                "p_business_id": str(business_id),
                "p_version_id": str(version_id),
            },
        )

        return result.scalar_one_or_none()

    except SQLAlchemyError as exc:
        db.rollback()
        logger.exception(
            "Failed to retrieve tax profile version: %s",
            exc.orig,
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to retrieve tax profile version",
        ) from exc
