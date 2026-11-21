from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent / "backend"))

from sqlalchemy import text
from app.core.database import engine

tables = ["businesses", "users", "business_role_access", "business_users", "warehouses"]

with engine.connect() as conn:
    for table in tables:
        print(f"\n========== {table} COLUMNS ==========")
        rows = conn.execute(text("""
            SELECT column_name, data_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = :table
            ORDER BY ordinal_position
        """), {"table": table}).fetchall()

        for row in rows:
            print(" | ".join(str(value) for value in row))

    print("\n========== EXISTING ROLES ==========")
    rows = conn.execute(text("""
        SELECT id, business_id, role_name, is_system
        FROM public.roles
        ORDER BY role_name
    """)).fetchall()

    for row in rows:
        print(" | ".join(str(value) for value in row))
