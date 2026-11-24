BEGIN;

CREATE OR REPLACE FUNCTION public.fn_accessible_branch_list(
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
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b ON b.id = bu.business_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active business membership required';
    END IF;

    RETURN QUERY
    SELECT br.id, br.branch_name, br.branch_code, br.address, br.phone,
           br.email, br.is_default, br.is_active, br.created_at, br.updated_at
    FROM public.branches br
    WHERE br.business_id = p_business_id
      AND (
          EXISTS (
              SELECT 1
              FROM public.business_users bu
              JOIN public.roles r
                ON r.id = bu.role_id
               AND (r.business_id = bu.business_id OR r.business_id IS NULL)
              WHERE bu.business_id = p_business_id
                AND bu.user_id = p_actor_user_id
                AND bu.status = 'active'
                AND LOWER(r.role_name) = 'owner'
          )
          OR EXISTS (
              SELECT 1
              FROM public.branch_user_assignments bua
              JOIN public.business_users bu
                ON bu.id = bua.business_user_id
               AND bu.business_id = bua.business_id
              WHERE bua.business_id = p_business_id
                AND bua.branch_id = br.id
                AND bu.user_id = p_actor_user_id
                AND bu.status = 'active'
                AND bua.assignment_status = 'active'
                AND bua.effective_from <= CURRENT_TIMESTAMP
                AND (bua.effective_to IS NULL OR bua.effective_to >= CURRENT_TIMESTAMP)
          )
      )
    ORDER BY br.branch_name;
END;
$$;

ALTER FUNCTION public.fn_accessible_branch_list(UUID, UUID)
OWNER TO nokshighor_branch_manager;
REVOKE ALL ON FUNCTION public.fn_accessible_branch_list(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_accessible_branch_list(UUID, UUID) TO nokshighor_app;

COMMIT;
