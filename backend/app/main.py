from fastapi import FastAPI
from sqlalchemy import text

from app.core.database import engine
from app.routes.auth import router as auth_router
from app.routes.sales import router as sales_router
from app.routes.opening_stock import router as opening_stock_router
from app.routes.tax import router as tax_router
from app.routes.owner import router as owner_router
from fastapi.middleware.cors import CORSMiddleware
from app.routes.branch import router as branch_router
from app.routes.super_admin import router as super_admin_router
app = FastAPI(
    title="NokshiGhor API",
    description="Smart Electrical & Interior Business Management System",
    version="0.1.0",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(sales_router)
app.include_router(opening_stock_router)
app.include_router(tax_router)
app.include_router(owner_router)
app.include_router(branch_router)
app.include_router(super_admin_router)
@app.get("/")
def home():
    return {
        "application": "NokshiGhor",
        "message": "Backend is running successfully",
    }


@app.get("/health")
def health():
    return {
        "application": "NokshiGhor",
        "status": "healthy",
    }


@app.get("/health/db")
def database_health():
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))

        return {
            "application": "NokshiGhor",
            "database": "connected",
            "status": "healthy",
        }

    except Exception:
        return {
            "application": "NokshiGhor",
            "database": "disconnected",
            "status": "unhealthy",
        }