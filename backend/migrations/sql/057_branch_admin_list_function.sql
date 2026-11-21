
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_branch_admin_list(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_branch_id UUID
)
RETURNS TABLE (
    assignment_id UUID,
    business_user_id UUID,
    user_id UUID,
    full_name VARCHAR,
    email VARCHAR,
    phone VARCHAR,
    assignment_status VARCHAR,
    assigned_at TIMESTAMPTZ,
    assigned_by UUID,
    notes TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Validate active Business and Owner
    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses b
        JOIN public.business_users bu
            ON bu.business_id = b.id
        JOIN public.roles r
            ON r.id = bu.role_id
        WHERE b.id = p_business_id
          AND b.status = 'active'
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND r.role_name = 'Owner'
          AND r.is_system = TRUE
    ) THEN
        RAISE EXCEPTION 'Only an active Business Owner can view Branch Admins.';
    END IF;

    -- Validate Branch
    IF NOT EXISTS (
        SELECT 1
        FROM public.branches br
        WHERE br.id = p_branch_id
          AND br.business_id = p_business_id
    ) THEN
        RAISE EXCEPTION 'Branch not found in this Business.';
    END IF;

    -- Return currently assigned Branch Admins
    RETURN QUERY
    SELECT
        a.id,
        a.business_user_id,
        u.id,
        u.full_name,
        u.email,
        u.phone,
        a.assignment_status,
        a.assigned_at,
        a.assigned_by,
        a.notes
    FROM public.branch_user_assignments a
    JOIN public.business_users bu
        ON bu.id = a.business_user_id
       AND bu.business_id = a.business_id
    JOIN public.users u
        ON u.id = bu.user_id
    JOIN public.roles r
        ON r.id = bu.role_id
    WHERE a.business_id = p_business_id
      AND a.branch_id = p_branch_id
      AND a.assignment_type = 'branch_admin'
      AND a.assignment_status = 'active'
      AND bu.status = 'active'
      AND u.status = 'active'
      AND r.role_name = 'Branch Admin'
      AND r.is_system = FALSE
    ORDER BY a.assigned_at DESC;
END;
$$;

ALTER FUNCTION public.fn_branch_admin_list(UUID, UUID, UUID)
OWNER TO nokshighor_branch_manager;

REVOKE ALL
ON FUNCTION public.fn_branch_admin_list(UUID, UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.fn_branch_admin_list(UUID, UUID, UUID)
TO nokshighor_app;

COMMIT;
