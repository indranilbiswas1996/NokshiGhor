
from typing import Annotated
from uuid import UUID
from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.dependencies import (
    get_current_user,
    require_permission,
)
from app.schemas.opening_stock import (
    OpeningStockCreateRequest,
    OpeningStockUpdateRequest,
    OpeningStockResponse,
    OpeningStockDraftListResponse,
)
from app.services.opening_stock_service import (
    create_opening_stock_draft,
    update_opening_stock_draft,
    post_opening_stock,
    list_opening_stock_drafts,
)
router = APIRouter(prefix="/opening-stock", tags=["Opening Stock"])


@router.post(
    "/drafts",
    response_model=OpeningStockResponse,
    status_code=status.HTTP_201_CREATED,
)
def create_draft(
    payload: OpeningStockCreateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("stock.manage")),
):
    return create_opening_stock_draft(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
        payload=payload,
    )
@router.post("/{document_id}/post")
def post_opening_stock_document(
    document_id: UUID,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("stock.manage")),
):
    return post_opening_stock(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
        document_id=str(document_id),
    )
@router.put(
    "/{document_id}/draft",
    response_model=OpeningStockResponse,
)
def update_draft(
    document_id: UUID,
    payload: OpeningStockUpdateRequest,
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("stock.manage")),
):
    return update_opening_stock_draft(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
        document_id=str(document_id),
        payload=payload,
    )
@router.get(
    "/drafts",
    response_model=OpeningStockDraftListResponse,
)
def get_opening_stock_drafts(
    db: Annotated[Session, Depends(get_db)],
    current_user=Depends(get_current_user),
    current_business=Depends(require_permission("stock.manage")),
):
    return list_opening_stock_drafts(
        db=db,
        business_id=current_business["id"],
        user_id=current_user["id"],
    )