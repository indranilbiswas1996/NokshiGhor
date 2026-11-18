from fastapi import FastAPI
from sqlalchemy import text

from app.core.database import engine
from app.routes.auth import router as auth_router


app = FastAPI(
    title="NokshiGhor API",
    description="Smart Electrical & Interior Business Management System",
    version="0.1.0",
)


app.include_router(auth_router)


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