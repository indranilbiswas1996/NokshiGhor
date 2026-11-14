
from fastapi import FastAPI

app = FastAPI(
    title="NokshiGhor API",
    description="Smart Electrical & Interior Business Management System",
    version="0.1.0"
)


@app.get("/")
def home():
    return {
        "application": "NokshiGhor",
        "message": "Backend is running successfully"
    }


@app.get("/health")
def health():
    return {
        "application": "NokshiGhor",
        "status": "healthy"
    }
