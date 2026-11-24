from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from datetime import datetime, timezone
from uuid import UUID
from app.core.config import settings
from app.core.database import get_db
from app.core.tokens import create_access_token, decode_access_token
from app.schemas.auth import LoginRequest, LoginResponse, UserResponse
from app.services.auth_service import authenticate_user
from app.core.dependencies import get_current_user
from fastapi.security import HTTPBearer
from sqlalchemy import text
from app.schemas.business import (
    BusinessListResponse,
    BusinessResponse,
    BusinessSelectRequest,
    BusinessSelectResponse,
)
from app.services.business_service import (
    get_user_businesses,
    get_user_business,
)
from app.core.dependencies import get_current_business

bearer_scheme = HTTPBearer(auto_error=False)
router = APIRouter(
    prefix="/auth",
    tags=["Authentication"],
)


@router.post("/login", response_model=LoginResponse)
def login(
    request: LoginRequest,
    db: Session = Depends(get_db),
):
    user = authenticate_user(
        db=db,
        email=request.email,
        password=request.password,
    )

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    access_token = create_access_token(
        user_id=user["id"],
    )

    return LoginResponse(
        access_token=access_token,
        token_type="bearer",
        expires_in=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        user=UserResponse(
            id=user["id"],
            full_name=user["full_name"],
            email=user["email"],
        ),
    )
@router.get("/me", response_model=UserResponse)
def get_my_profile(
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    is_super_admin = db.execute(
        text("SELECT public.fn_is_super_admin(CAST(:user_id AS UUID))"),
        {"user_id": current_user["id"]},
    ).scalar_one()

    return UserResponse(
        id=current_user["id"],
        full_name=current_user["full_name"],
        email=current_user["email"],
        profile_picture=current_user["profile_picture"],
        is_super_admin=is_super_admin,
    )
@router.get("/businesses", response_model=BusinessListResponse)
def get_my_businesses(
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    businesses = get_user_businesses(
        db=db,
        user_id=current_user["id"],
    )
    is_super_admin = db.execute(
        text("SELECT public.fn_is_super_admin(CAST(:user_id AS UUID))"),
        {"user_id": current_user["id"]},
    ).scalar_one()

    return BusinessListResponse(
        businesses=[
            BusinessResponse(**business)
            for business in businesses
        ],
        total=len(businesses),
        is_super_admin=is_super_admin,
    )
@router.post(
    "/businesses/select",
    response_model=BusinessSelectResponse,
)
def select_business(
    request: BusinessSelectRequest,
    current_user=Depends(get_current_user),
    db: Session = Depends(get_db),
):
    business = get_user_business(
        db=db,
        user_id=current_user["id"],
        business_id=request.business_id,
    )

    if business is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this business",
        )

    access_token = create_access_token(
        user_id=current_user["id"],
        business_id=business["id"],
    )

    return BusinessSelectResponse(
        access_token=access_token,
        token_type="bearer",
        expires_in=settings.JWT_ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        business=BusinessResponse(**business),
    )
@router.get(
    "/current-business",
    response_model=BusinessResponse,
)
def get_current_business_info(
    current_business=Depends(get_current_business),
):
    return BusinessResponse(**current_business)
@router.post("/logout")
def logout(
    current_user=Depends(get_current_user),
    credentials=Depends(bearer_scheme),
    db: Session = Depends(get_db),
):
    payload = decode_access_token(credentials.credentials)

    token_id = UUID(payload["jti"])
    expires_at = datetime.fromtimestamp(
        payload["exp"],
        tz=timezone.utc,
    )

    try:
        db.execute(
            text("""
                SELECT public.fn_auth_revoke_token(
                    :token_id,
                    :expires_at
                )
            """),
            {
                "token_id": token_id,
                "expires_at": expires_at,
            },
        )
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Logout service temporarily unavailable",
        )

    return {"message": "Successfully logged out"}