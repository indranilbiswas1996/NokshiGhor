
import json
import logging

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.schemas.opening_stock import (
    OpeningStockCreateRequest,
    OpeningStockUpdateRequest,
)

logger = logging.getLogger(__name__)


def create_opening_stock_draft(
    db: Session,
    business_id: str,
    user_id: str,
    payload: OpeningStockCreateRequest,
) -> dict:
    """
    Create an opening stock draft through the secure
    PostgreSQL SECURITY DEFINER function.
    """

    items = [
        {
            "product_id": str(item.product_id),
            "quantity": str(item.quantity),
            "unit_cost": str(item.unit_cost),
            "notes": item.notes,
        }
        for item in payload.items
    ]

    try:
        result = db.execute(
            text("""
                SELECT public.fn_create_opening_stock_draft(
                    CAST(:business_id AS UUID),
                    CAST(:user_id AS UUID),
                    CAST(:warehouse_id AS UUID),
                    :opening_date,
                    :notes,
                    CAST(:items AS JSONB)
                )
            """),
            {
                "business_id": business_id,
                "user_id": user_id,
                "warehouse_id": str(payload.warehouse_id),
                "opening_date": payload.opening_date,
                "notes": payload.notes,
                "items": json.dumps(items),
            },
        )

        document_id = result.scalar_one()

        db.commit()

        return {
            "message": "Opening stock draft created successfully",
            "document_id": document_id,
            "opening_status": "draft",
        }

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
                detail=str(original_error),
            ) from exc

        logger.exception("Failed to create opening stock draft")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to create opening stock draft",
        ) from exc
def post_opening_stock(
    db: Session,
    business_id: str,
    user_id: str,
    document_id: str,
) -> dict:
    """
    Post an opening stock document through the secure
    PostgreSQL SECURITY DEFINER function.
    """

    try:
        db.execute(
            text("""
                SELECT public.fn_post_opening_stock(
                    CAST(:business_id AS UUID),
                    CAST(:user_id AS UUID),
                    CAST(:document_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "user_id": user_id,
                "document_id": document_id,
            },
        )

        db.commit()

        return {
            "message": "Opening stock posted successfully",
            "document_id": document_id,
            "opening_status": "posted",
        }

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
                detail=str(original_error),
            ) from exc

        logger.exception("Failed to post opening stock")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to post opening stock",
        ) from exc
def update_opening_stock_draft(
    db: Session,
    business_id: str,
    user_id: str,
    document_id: str,
    payload: OpeningStockUpdateRequest,
) -> dict:
    """
    Update an existing opening stock draft through the
    secure PostgreSQL SECURITY DEFINER function.
    """

    items = [
        {
            "product_id": str(item.product_id),
            "quantity": str(item.quantity),
            "unit_cost": str(item.unit_cost),
            "notes": item.notes,
        }
        for item in payload.items
    ]

    try:
        result = db.execute(
            text("""
                SELECT public.fn_update_opening_stock_draft(
                    CAST(:business_id AS UUID),
                    CAST(:user_id AS UUID),
                    CAST(:document_id AS UUID),
                    CAST(:warehouse_id AS UUID),
                    :opening_date,
                    :notes,
                    CAST(:items AS JSONB)
                )
            """),
            {
                "business_id": business_id,
                "user_id": user_id,
                "document_id": document_id,
                "warehouse_id": str(payload.warehouse_id),
                "opening_date": payload.opening_date,
                "notes": payload.notes,
                "items": json.dumps(items),
            },
        )

        updated_document_id = result.scalar_one()

        db.commit()

        return {
            "message": "Opening stock draft updated successfully",
            "document_id": updated_document_id,
            "opening_status": "draft",
        }

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
                detail=str(original_error),
            ) from exc

        logger.exception("Failed to update opening stock draft")

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to update opening stock draft",
        ) from exc
def list_opening_stock_drafts(
    db: Session,
    business_id: str,
    user_id: str,
):
    try:
        result = db.execute(
            text("""
                SELECT public.fn_list_opening_stock_drafts(
                    CAST(:business_id AS UUID),
                    CAST(:user_id AS UUID)
                )
            """),
            {
                "business_id": business_id,
                "user_id": user_id,
            },
        )

        drafts = result.scalar_one()

        return {"drafts": drafts}

    except SQLAlchemyError as exc:
        db.rollback()

        logger.exception("Failed to list opening stock drafts")

        pgcode = getattr(getattr(exc, "orig", None), "sqlstate", None)

        if pgcode == "P0001":
            raise HTTPException(
                status_code=409,
                detail="Unable to access opening stock drafts",
            ) from exc

        raise HTTPException(
            status_code=503,
            detail="Unable to retrieve opening stock drafts",
        ) from exc