
BEGIN;

-- Dedicated non-login role for business membership lookup.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nokshighor_business_reader'
    ) THEN
        CREATE ROLE nokshighor_business_reader
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
TO nokshighor_business_reader;

GRANT CREATE ON SCHEMA public
TO nokshighor_business_reader;

-- Read only active memberships and their associated business and role.
GRANT SELECT (
    business_id,
    user_id,
    role_id,
    status
)
ON public.business_users
TO nokshighor_business_reader;

GRANT SELECT (
    id,
    business_name,
    business_type,
    status,
    deleted_at
)
ON public.businesses
TO nokshighor_business_reader;

GRANT SELECT (
    id,
    role_name,
    business_id
)
ON public.roles
TO nokshighor_business_reader;

CREATE OR REPLACE FUNCTION public.fn_auth_user_businesses(
    p_user_id UUID
)
RETURNS TABLE (
    business_id UUID,
    business_name VARCHAR,
    business_type VARCHAR,
    business_status VARCHAR,
    role_name VARCHAR
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT
        b.id,
        b.business_name,
        b.business_type,
        b.status,
        r.role_name
    FROM public.business_users AS bu
    JOIN public.businesses AS b
      ON b.id = bu.business_id
    JOIN public.roles AS r
      ON r.id = bu.role_id
     AND r.business_id = bu.business_id
    WHERE bu.user_id = p_user_id
      AND bu.status = 'active'
      AND b.status = 'active'
      AND b.deleted_at IS NULL
    ORDER BY b.business_name;
$$;

ALTER FUNCTION public.fn_auth_user_businesses(UUID)
OWNER TO nokshighor_business_reader;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_business_reader;

REVOKE ALL ON FUNCTION public.fn_auth_user_businesses(UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_auth_user_businesses(UUID)
TO nokshighor_app;

COMMIT;
