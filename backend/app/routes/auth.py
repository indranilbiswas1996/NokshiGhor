from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import get_db
from app.core.tokens import create_access_token
from app.schemas.auth import LoginRequest, LoginResponse, UserResponse
from app.services.auth_service import authenticate_user
from app.core.dependencies import get_current_user

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
):
    return UserResponse(
        id=current_user["id"],
        full_name=current_user["full_name"],
        email=current_user["email"],
    )