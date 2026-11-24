BEGIN;

CREATE OR REPLACE FUNCTION public.fn_unassigned_branch_admin_list(
    p_business_id UUID,
    p_actor_user_id UUID
)
RETURNS TABLE (
    business_user_id UUID,
    user_id UUID,
    full_name TEXT,
    email TEXT,
    phone TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses b
        WHERE b.id = p_business_id
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Business is inactive or unavailable.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r ON r.id = bu.role_id
        JOIN public.users u ON u.id = bu.user_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND u.status = 'active'
          AND u.deleted_at IS NULL
          AND r.role_name = 'Owner'
    ) THEN
        RAISE EXCEPTION 'Only an active Business Owner can view unassigned Branch Admins.';
    END IF;

    RETURN QUERY
    SELECT
        bu.id,
        u.id,
        u.full_name::TEXT,
        u.email::TEXT,
        u.phone::TEXT
    FROM public.business_users bu
    JOIN public.users u ON u.id = bu.user_id
    JOIN public.roles r ON r.id = bu.role_id
    WHERE bu.business_id = p_business_id
      AND bu.status = 'active'
      AND u.status = 'active'
      AND u.deleted_at IS NULL
      AND r.role_name = 'Branch Admin'
      AND r.is_system = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM public.branch_user_assignments bua
          WHERE bua.business_id = p_business_id
            AND bua.business_user_id = bu.id
            AND bua.assignment_type = 'branch_admin'
            AND bua.assignment_status = 'active'
      )
    ORDER BY u.full_name;
END;
$$;

ALTER FUNCTION public.fn_unassigned_branch_admin_list(UUID, UUID)
OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_unassigned_branch_admin_list(UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_unassigned_branch_admin_list(UUID, UUID)
TO nokshighor_app;

COMMIT;
