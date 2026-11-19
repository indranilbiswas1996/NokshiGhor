
import json
from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.schemas.sales import SaleCreateRequest
import logging

logger = logging.getLogger(__name__)

def create_sale_draft(
    db: Session,
    business_id: UUID,
    user_id: UUID,
    payload: SaleCreateRequest,
):
    items = [
        {
            "product_id": str(item.product_id),
            "quantity": str(item.quantity),
            "unit_price": (
                str(item.unit_price)
                if item.unit_price is not None
                else None
            ),
            "discount_amount": str(item.discount_amount),
        }
        for item in payload.items
    ]

    params = {
        "business_id": str(business_id),
        "user_id": str(user_id),
        "customer_id": (
            str(payload.customer_id)
            if payload.customer_id
            else None
        ),
        "warehouse_id": (
            str(payload.warehouse_id)
            if payload.warehouse_id
            else None
        ),
        "sale_date": payload.sale_date,
        "due_date": payload.due_date,
        "discount_amount": payload.discount_amount,
        "shipping_charge": payload.shipping_charge,
        "other_charges": payload.other_charges,
        "notes": payload.notes,
        "items": json.dumps(items),
    }

    statement = text("""
        SELECT public.fn_create_sales_draft(
            CAST(:business_id AS UUID),
            CAST(:user_id AS UUID),
            CAST(:customer_id AS UUID),
            CAST(:warehouse_id AS UUID),
            :sale_date,
            :due_date,
            :discount_amount,
            :shipping_charge,
            :other_charges,
            :notes,
            CAST(:items AS JSONB)
        )
    """)

    try:
        result = db.execute(statement, params).scalar_one()
        db.commit()
        return result

    except SQLAlchemyError as exc:
        db.rollback()
        logger.error(
            "Sales draft creation failed: %s",
            getattr(exc.orig, "pgerror", str(exc.orig)),
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to create sales draft",
        )

def get_sale_details(
    db: Session,
    business_id: UUID,
    user_id: UUID,
    sale_id: UUID,
):
    statement = text("""
        SELECT public.fn_get_sale_details(
            CAST(:user_id AS UUID),
            CAST(:business_id AS UUID),
            CAST(:sale_id AS UUID)
        )
    """)

    try:
        result = db.execute(
            statement,
            {
                "user_id": str(user_id),
                "business_id": str(business_id),
                "sale_id": str(sale_id),
            },
        ).scalar_one_or_none()

        return result

    except SQLAlchemyError:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Unable to retrieve sales details",
        )

def get_sales_list(
    db: Session,
    business_id: UUID,
    user_id: UUID,
    limit: int = 20,
    offset: int = 0,
    sale_status: str | None = None,
):
    statement = text("""
        SELECT public.fn_get_sales_list(
            CAST(:user_id AS UUID),
            CAST(:business_id AS UUID),
            :limit,
            :offset,
            :sale_status
        )
    """)

    try:
        result = db.execute(
            statement,
            {
                "user_id": str(user_id),
                "business_id": str(business_id),
                "limit": limit,
                "offset": offset,
                "sale_status": sale_status,
            },
        ).scalar_one_or_none()

        return result

    except SQLAlchemyError:
        db.rollback()
        logger.exception("Unable to retrieve sales list")
        raise HTTPException(
            status_code=503,
            detail="Unable to retrieve sales list",
        )
