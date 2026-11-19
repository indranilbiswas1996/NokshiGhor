BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nokshighor_permission_reader'
    ) THEN
        CREATE ROLE nokshighor_permission_reader
        WITH NOLOGIN
        NOSUPERUSER
        NOCREATEDB
        NOCREATEROLE
        NOREPLICATION
        NOBYPASSRLS
        NOINHERIT;
    END IF;
END
$$;

GRANT USAGE, CREATE ON SCHEMA public
TO nokshighor_permission_reader;

GRANT SELECT (business_id, user_id, role_id, status)
ON public.business_users
TO nokshighor_permission_reader;

GRANT SELECT (id, status, deleted_at)
ON public.businesses
TO nokshighor_permission_reader;

GRANT SELECT (role_id, permission_id)
ON public.role_permissions
TO nokshighor_permission_reader;

GRANT SELECT (id, permission_key)
ON public.permissions
TO nokshighor_permission_reader;

CREATE OR REPLACE FUNCTION public.fn_auth_user_has_permission(
    p_user_id UUID,
    p_business_id UUID,
    p_permission_key TEXT
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b
            ON b.id = bu.business_id
        JOIN public.role_permissions rp
            ON rp.role_id = bu.role_id
        JOIN public.permissions p
            ON p.id = rp.permission_id
        WHERE bu.user_id = p_user_id
          AND bu.business_id = p_business_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
          AND p.permission_key = p_permission_key
    );
$$;

ALTER FUNCTION public.fn_auth_user_has_permission(UUID, UUID, TEXT)
OWNER TO nokshighor_permission_reader;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_permission_reader;

REVOKE ALL ON FUNCTION
public.fn_auth_user_has_permission(UUID, UUID, TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
public.fn_auth_user_has_permission(UUID, UUID, TEXT)
TO nokshighor_app;

COMMIT;