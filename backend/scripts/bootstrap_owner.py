
import getpass
import re
import sys
from uuid import uuid4

import psycopg
from pwdlib import PasswordHash


DB_HOST = "127.0.0.1"
DB_PORT = 5433
DB_NAME = "nokshighor_db"
DEFAULT_DB_USER = "nokshighor_user"

PERMISSIONS = [
    ("dashboard.view", "View dashboard"),
    ("business.settings.view", "View business settings"),
    ("business.settings.manage", "Manage business settings"),
    ("users.view", "View users"),
    ("users.manage", "Manage users"),
    ("roles.view", "View roles"),
    ("roles.manage", "Manage roles"),
    ("products.view", "View products"),
    ("products.manage", "Manage products"),
    ("categories.view", "View categories"),
    ("categories.manage", "Manage categories"),
    ("parties.view", "View parties"),
    ("parties.manage", "Manage parties"),
    ("purchases.view", "View purchases"),
    ("purchases.manage", "Manage purchases"),
    ("sales.view", "View sales"),
    ("sales.manage", "Manage sales"),
    ("stock.view", "View stock"),
    ("stock.manage", "Manage stock"),
    ("payments.view", "View payments"),
    ("payments.manage", "Manage payments"),
    ("expenses.view", "View expenses"),
    ("expenses.manage", "Manage expenses"),
    ("projects.view", "View projects"),
    ("projects.manage", "Manage projects"),
    ("reports.view", "View reports"),
    ("reports.export", "Export reports"),
    ("audit_logs.view", "View audit logs"),
]


def ask_required(label: str, maximum: int) -> str:
    while True:
        value = input(label).strip()
        if value and len(value) <= maximum:
            return value
        print(f"Please enter a value between 1 and {maximum} characters.")


def main() -> None:
    print("\n=== NokshiGhor | First Owner Setup ===\n")

    owner_name = ask_required("Owner full name: ", 150)
    owner_email = ask_required("Owner email: ", 255).lower()

    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", owner_email):
        print("Invalid email address.")
        sys.exit(1)

    business_name = ask_required("Business name: ", 200)

    print("\nBusiness types: electrical / interior / both / other")
    while True:
        business_type = input("Business type: ").strip().lower()
        if business_type in {"electrical", "interior", "both", "other"}:
            break
        print("Please enter electrical, interior, both, or other.")

    while True:
        owner_password = getpass.getpass("Owner password (minimum 12 characters): ")
        confirm_password = getpass.getpass("Confirm owner password: ")

        if len(owner_password) < 12:
            print("Password must contain at least 12 characters.")
        elif owner_password != confirm_password:
            print("Passwords do not match.")
        else:
            break

    db_user = input(
        f"PostgreSQL admin username [{DEFAULT_DB_USER}]: "
    ).strip() or DEFAULT_DB_USER

    db_password = getpass.getpass("PostgreSQL admin password: ")

    password_hasher = PasswordHash.recommended()
    password_digest = password_hasher.hash(owner_password)

    # Do not retain the owner's plaintext password.
    del owner_password
    del confirm_password

    try:
        with psycopg.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=db_user,
            password=db_password,
            connect_timeout=10,
        ) as connection:

            with connection.transaction():
                with connection.cursor() as cursor:

                    cursor.execute("""
                        SELECT
                            EXISTS (SELECT 1 FROM public.users),
                            EXISTS (SELECT 1 FROM public.businesses)
                    """)
                    has_users, has_businesses = cursor.fetchone()

                    if has_users or has_businesses:
                        raise RuntimeError(
                            "Bootstrap stopped: users or businesses "
                            "already exist. No data was changed."
                        )

                    owner_id = uuid4()
                    business_id = uuid4()
                    role_id = uuid4()

                    cursor.execute("""
                        INSERT INTO public.users (
                            id, full_name, email, password_hash, status
                        )
                        VALUES (%s, %s, %s, %s, 'active')
                    """, (
                        owner_id,
                        owner_name,
                        owner_email,
                        password_digest,
                    ))

                    cursor.execute("""
                        INSERT INTO public.businesses (
                            id, business_name, business_type,
                            status, created_by
                        )
                        VALUES (%s, %s, %s, 'active', %s)
                    """, (
                        business_id,
                        business_name,
                        business_type,
                        owner_id,
                    ))

                    cursor.execute("""
                        INSERT INTO public.roles (
                            id, role_name, description,
                            business_id, is_system, created_by
                        )
                        VALUES (
                            %s, 'Owner',
                            'Full access to this business',
                            %s, FALSE, %s
                        )
                    """, (
                        role_id,
                        business_id,
                        owner_id,
                    ))

                    # The database role-provisioning trigger should
                    # create the business_role_access mapping.
                    cursor.execute("""
                        SELECT EXISTS (
                            SELECT 1
                            FROM public.business_role_access
                            WHERE business_id = %s
                              AND role_id = %s
                        )
                    """, (business_id, role_id))

                    if not cursor.fetchone()[0]:
                        raise RuntimeError(
                            "Owner role access mapping was not created."
                        )

                    cursor.execute("""
                        INSERT INTO public.business_users (
                            business_id, user_id, role_id,
                            status, created_by
                        )
                        VALUES (%s, %s, %s, 'active', %s)
                    """, (
                        business_id,
                        owner_id,
                        role_id,
                        owner_id,
                    ))

                    for permission_key, description in PERMISSIONS:
                        cursor.execute("""
                            INSERT INTO public.permissions (
                                permission_key, description, created_by
                            )
                            VALUES (%s, %s, %s)
                            ON CONFLICT (permission_key)
                            DO UPDATE SET
                                description = EXCLUDED.description
                            RETURNING id
                        """, (
                            permission_key,
                            description,
                            owner_id,
                        ))

                        permission_id = cursor.fetchone()[0]

                        cursor.execute("""
                            INSERT INTO public.role_permissions (
                                role_id, permission_id, created_by
                            )
                            VALUES (%s, %s, %s)
                            ON CONFLICT (role_id, permission_id)
                            DO NOTHING
                        """, (
                            role_id,
                            permission_id,
                            owner_id,
                        ))

            print("\nSUCCESS: Initial Owner setup completed.")
            print(f"Owner email: {owner_email}")
            print(f"Business: {business_name}")
            print(f"Business type: {business_type}")
            print(f"Permissions assigned: {len(PERMISSIONS)}")
            print("\nYou can now test login through http://127.0.0.1:8000/docs")

    except Exception as error:
        print(f"\nBOOTSTRAP FAILED: {error}")
        sys.exit(1)


if __name__ == "__main__":
    main()
