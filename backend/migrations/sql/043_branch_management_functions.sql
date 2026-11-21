
-- ============================================================
-- NokshiGhor
-- Migration 043: Branch Management Functions
-- Feature 1: Secure Branch List
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_branch_list(
    p_business_id UUID,
    p_actor_user_id UUID
)
RETURNS TABLE (
    id UUID,
    branch_name VARCHAR(150),
    branch_code VARCHAR(50),
    address TEXT,
    phone VARCHAR(20),
    email VARCHAR(255),
    is_default BOOLEAN,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses b
        WHERE b.id = p_business_id
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Business is not active'
            USING ERRCODE = 'P0001';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r
          ON r.id = bu.role_id
         AND (
             r.business_id = bu.business_id
             OR r.business_id IS NULL
         )
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND LOWER(r.role_name) = 'owner'
    ) THEN
        RAISE EXCEPTION 'Active Owner access is required'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN QUERY
    SELECT
        br.id,
        br.branch_name,
        br.branch_code,
        br.address,
        br.phone,
        br.email,
        br.is_default,
        br.is_active,
        br.created_at,
        br.updated_at
    FROM public.branches br
    WHERE br.business_id = p_business_id
    ORDER BY br.is_default DESC, br.branch_name ASC;
END;
$$;

ALTER FUNCTION public.fn_branch_list(UUID, UUID)
OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_branch_list(UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_branch_list(UUID, UUID)
TO nokshighor_app;

COMMIT;
