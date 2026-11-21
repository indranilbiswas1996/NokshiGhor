
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_master_branch_admin_list(
    p_business_id UUID,
    p_actor_user_id UUID
)
RETURNS TABLE (
    assignment_id UUID,
    branch_id UUID,
    branch_name TEXT,
    business_user_id UUID,
    user_id UUID,
    full_name TEXT,
    email TEXT,
    phone TEXT,
    assignment_status TEXT,
    assigned_at TIMESTAMPTZ,
    notes TEXT
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
    ) THEN
        RAISE EXCEPTION 'Business is inactive or unavailable.';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r ON r.id = bu.role_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND r.role_name = 'Owner'
    ) THEN
        RAISE EXCEPTION 'Only an active Business Owner can view Master Branch Admins.';
    END IF;

    RETURN QUERY
    SELECT
        a.id,
        a.branch_id,
        br.branch_name::TEXT,
        a.business_user_id,
        bu.user_id,
        u.full_name::TEXT,
        u.email::TEXT,
        u.phone::TEXT,
        a.assignment_status::TEXT,
        a.assigned_at,
        a.notes::TEXT
    FROM public.branch_user_assignments a
    JOIN public.branches br
      ON br.id = a.branch_id
     AND br.business_id = p_business_id
    JOIN public.business_users bu
      ON bu.id = a.business_user_id
     AND bu.business_id = p_business_id
    JOIN public.users u
      ON u.id = bu.user_id
    JOIN public.roles r
      ON r.id = bu.role_id
    WHERE a.business_id = p_business_id
      AND a.assignment_type = 'branch_admin'
      AND a.assignment_status = 'active'
      AND bu.status = 'active'
      AND u.status = 'active'
      AND r.role_name = 'Branch Admin'
      AND r.is_system = FALSE
    ORDER BY br.branch_name, u.full_name;
END;
$$;

ALTER FUNCTION public.fn_master_branch_admin_list(UUID, UUID)
OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_master_branch_admin_list(UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_master_branch_admin_list(UUID, UUID)
TO nokshighor_app;

COMMIT;
