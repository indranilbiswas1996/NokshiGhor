
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import (
    get_current_user,
    require_permission,
)
from app.schemas.sales import SaleCreateRequest
from app.services.sales_service import (
    create_sale_draft,
    get_sale_details,
    get_sales_list,
    get_sales_products,
    get_sales_customers,
    get_sales_warehouses,
    post_sale,
)

router = APIRouter(prefix="/sales", tags=["Sales"])


@router.post(
    "/drafts",
    status_code=status.HTTP_201_CREATED,
)
def create_draft(
    payload: SaleCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("sales.manage")),
):
    try:
        sale_id = create_sale_draft(
            db=db,
            business_id=current_business["id"],
            user_id=current_user["id"],
            payload=payload,
        )

        return {
            "message": "Sales draft created successfully",
            "sale_id": sale_id,
            "sale_status": "draft",
        }

    except HTTPException:
        raise

@router.get("/reference/products")
def list_sales_products(
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("sales.view")),
):
    return get_sales_products(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
    )


@router.get("/reference/customers")
def list_sales_customers(
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("sales.view")),
):
    return get_sales_customers(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
    )


@router.get("/reference/warehouses")
def list_sales_warehouses(
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("sales.view")),
):
    return get_sales_warehouses(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
    )

@router.get("/{sale_id}")
def read_sale_details(
    sale_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("sales.view")),
    branch_id: UUID | None = None,
):
    sale = get_sale_details(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
        sale_id=sale_id,
        branch_id=branch_id,
    )

    if sale is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Sale not found",
        )

    return sale

@router.get("")
def list_sales(
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("sales.view")),
    limit: int = 20,
    offset: int = 0,
    sale_status: str | None = None,
    branch_id: UUID | None = None,
):
    if limit < 1 or limit > 100:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Limit must be between 1 and 100",
        )

    if offset < 0:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Offset cannot be negative",
        )

    allowed_statuses = {
        "draft",
        "posted",
        "cancelled",
    }

    if sale_status is not None and sale_status not in allowed_statuses:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Invalid sale status",
        )

    result = get_sales_list(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
        limit=limit,
        offset=offset,
        sale_status=sale_status,
        branch_id=branch_id,
    )

    return result


@router.post("/{sale_id}/post")
def post_sale_endpoint(
    sale_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("sales.manage")),
    branch_id: UUID | None = None,
):
    result = post_sale(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
        sale_id=sale_id,
        branch_id=branch_id,
    )

    return {
        "success": True,
        "message": "Sale posted successfully",
        "sale_id": str(result),
    }
