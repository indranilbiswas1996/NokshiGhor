import getpass
import os
import re
import sys
from pathlib import Path

import psycopg
from pwdlib import PasswordHash

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.core.config import settings

DEFAULT_EMAIL = os.environ.get("SUPER_ADMIN_EMAIL", "gcettbdada@gmail.com")
DEFAULT_NAME = os.environ.get("SUPER_ADMIN_NAME", "Super Admin")


def main() -> None:
    print("\n=== NokshiGhor | Super Admin Setup ===\n")
    email = input(f"Super Admin email [{DEFAULT_EMAIL}]: ").strip().lower() or DEFAULT_EMAIL
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        raise SystemExit("Invalid email address.")

    full_name = input(f"Full name [{DEFAULT_NAME}]: ").strip() or DEFAULT_NAME
    if len(full_name) > 150:
        raise SystemExit("Full name must be 150 characters or fewer.")

    password = getpass.getpass("Password (minimum 12 characters): ")
    confirmation = getpass.getpass("Confirm password: ")
    if len(password) < 12:
        raise SystemExit("Password must contain at least 12 characters.")
    if password != confirmation:
        raise SystemExit("Passwords do not match.")

    password_hash = PasswordHash.recommended().hash(password)
    del password, confirmation

    with psycopg.connect(
        host=settings.APP_DB_HOST,
        port=settings.APP_DB_PORT,
        dbname=settings.APP_DB_NAME,
        user="nokshighor_user",
        password=settings.APP_DB_PASSWORD,
        connect_timeout=10,
    ) as connection:
        with connection.transaction():
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT id, status
                    FROM public.users
                    WHERE LOWER(email) = LOWER(%s)
                      AND deleted_at IS NULL
                    FOR UPDATE
                """, (email,))
                user = cursor.fetchone()

                if user and user[1] != "active":
                    raise RuntimeError("The existing account is not active.")

                if user:
                    user_id = user[0]
                else:
                    cursor.execute("""
                        INSERT INTO public.users (
                            full_name, email, password_hash, status
                        ) VALUES (%s, %s, %s, 'active')
                        RETURNING id
                    """, (full_name, email, password_hash))
                    user_id = cursor.fetchone()[0]

                cursor.execute("""
                    INSERT INTO public.super_admin_users (user_id, created_by)
                    VALUES (%s, %s)
                    ON CONFLICT (user_id) DO NOTHING
                """, (user_id, user_id))

    print("\nSuper Admin setup complete.")
    print(f"Account: {email}")
    print("Password was not stored in plaintext.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"\nSetup failed: {error}")
        sys.exit(1)
