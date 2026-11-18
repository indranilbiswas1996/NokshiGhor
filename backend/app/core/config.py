from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL


PROJECT_ROOT = Path(__file__).resolve().parents[3]


class Settings(BaseSettings):
    APP_NAME: str = "NokshiGhor"
    APP_VERSION: str = "0.1.0"
    APP_ENV: str = "development"

    APP_DB_HOST: str = "127.0.0.1"
    APP_DB_PORT: int = 5433
    APP_DB_NAME: str = "nokshighor_db"
    APP_DB_USER: str = "nokshighor_app"
    APP_DB_PASSWORD: str

    JWT_SECRET_KEY: str = Field(min_length=32)
    JWT_ALGORITHM: str = "HS256"
    JWT_ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    model_config = SettingsConfigDict(
        env_file=PROJECT_ROOT / ".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    @property
    def database_url(self) -> URL:
        return URL.create(
            drivername="postgresql+psycopg",
            username=self.APP_DB_USER,
            password=self.APP_DB_PASSWORD,
            host=self.APP_DB_HOST,
            port=self.APP_DB_PORT,
            database=self.APP_DB_NAME,
        )


settings = Settings()