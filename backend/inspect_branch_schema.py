from sqlalchemy import text
from app.core.database import engine

tables = [
    "business_users", "roles", "warehouses", "products",
    "sales", "sale_items", "purchases", "purchase_items",
    "sales_returns", "purchase_returns", "stock_ledger",
    "stock_transfers", "stock_adjustments",
    "opening_stock_documents", "expenses", "interior_projects",
    "audit_logs"
]

with engine.connect() as conn:
    print("\nDATABASE:", conn.execute(
        text("SELECT current_database(), current_user")
    ).fetchone())

    for table in tables:
        print(f"\n========== {table} ==========")

        rows = conn.execute(text("""
            SELECT column_name, data_type, is_nullable
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = :table
            ORDER BY ordinal_position
        """), {"table": table}).fetchall()

        for row in rows:
            print(" | ".join(str(x) for x in row))

        rows = conn.execute(text("""
            SELECT conname, contype, pg_get_constraintdef(oid)
            FROM pg_constraint
            WHERE conrelid = to_regclass(:table)
            ORDER BY conname
        """), {"table": f"public.{table}"}).fetchall()

        print("-- CONSTRAINTS --")
        for row in rows:
            print(" | ".join(str(x) for x in row))

engine.dispose()
