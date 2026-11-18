
BEGIN;

-- Dedicated non-login role for secure user lookup.
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

-- Read only the columns required by authenticated-user lookup.
GRANT USAGE ON SCHEMA public
TO nokshighor_auth_reader;

GRANT CREATE ON SCHEMA public
TO nokshighor_auth_reader;

GRANT SELECT (
    id,
    full_name,
    email,
    status,
    deleted_at
)
ON public.users
TO nokshighor_auth_reader;

CREATE OR REPLACE FUNCTION public.fn_auth_user_by_id(
    p_user_id UUID
)
RETURNS TABLE (
    id UUID,
    full_name VARCHAR,
    email VARCHAR,
    status VARCHAR
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT
        u.id,
        u.full_name,
        u.email,
        u.status
    FROM public.users AS u
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
    LIMIT 1;
$$;

ALTER FUNCTION public.fn_auth_user_by_id(UUID)
OWNER TO nokshighor_auth_reader;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_auth_reader;

REVOKE ALL ON FUNCTION public.fn_auth_user_by_id(UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_auth_user_by_id(UUID)
TO nokshighor_app;

COMMIT;
