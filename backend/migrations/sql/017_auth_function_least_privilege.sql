BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nokshighor_auth_reader'
    ) THEN
        CREATE ROLE nokshighor_auth_reader
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public
TO nokshighor_auth_reader;

GRANT CREATE ON SCHEMA public
TO nokshighor_auth_reader;

GRANT SELECT (
    id,
    full_name,
    email,
    password_hash,
    status,
    deleted_at
)
ON public.users
TO nokshighor_auth_reader;

ALTER FUNCTION public.fn_auth_user_by_email(TEXT)
OWNER TO nokshighor_auth_reader;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_auth_reader;

REVOKE ALL ON FUNCTION public.fn_auth_user_by_email(TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_auth_user_by_email(TEXT)
TO nokshighor_app;

COMMIT;