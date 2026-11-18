BEGIN;

CREATE OR REPLACE FUNCTION public.fn_auth_user_by_email(
    p_email TEXT
)
RETURNS TABLE (
    id UUID,
    full_name VARCHAR,
    email VARCHAR,
    password_hash TEXT,
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
        u.password_hash,
        u.status
    FROM public.users AS u
    WHERE LOWER(u.email) = LOWER(BTRIM(p_email))
      AND u.deleted_at IS NULL
    LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.fn_auth_user_by_email(TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_auth_user_by_email(TEXT)
TO nokshighor_app;

COMMIT;