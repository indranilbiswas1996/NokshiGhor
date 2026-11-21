
-- ============================================================
-- NokshiGhor
-- Migration 049: Branch Admin Assignment Function
-- PostgreSQL 17
--
-- Assigns an active Branch Admin to an active Business Branch.
-- Every assignment is preserved in branch_user_assignments.
-- ============================================================

BEGIN;
GRANT UPDATE (id)
ON public.business_users
TO nokshighor_branch_manager;
CREATE OR REPLACE FUNCTION public.fn_branch_assign_admin(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_branch_id UUID,
    p_business_user_id UUID,
    p_notes TEXT DEFAULT NULL
)
RETURNS public.branch_user_assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_business public.businesses%ROWTYPE;
    v_branch public.branches%ROWTYPE;
    v_target_membership public.business_users%ROWTYPE;
    v_assignment public.branch_user_assignments%ROWTYPE;
BEGIN
    -- --------------------------------------------------------
    -- 1. Lock and validate Business
    -- --------------------------------------------------------

    SELECT b.*
    INTO v_business
    FROM public.businesses b
    WHERE b.id = p_business_id
      AND b.status = 'active'
      AND b.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Business is inactive or does not exist.';
    END IF;

    -- --------------------------------------------------------
    -- 2. Verify the actor is an active Owner of this Business
    -- --------------------------------------------------------

    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r
          ON r.id = bu.role_id
         AND r.business_id = bu.business_id
        JOIN public.users u
          ON u.id = bu.user_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND LOWER(BTRIM(r.role_name)) = 'owner'
          AND r.is_system = FALSE
          AND u.status = 'active'
          AND u.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Only an active Business Owner can assign Branch Admins.';
    END IF;

    -- --------------------------------------------------------
    -- 3. Lock and validate the target Branch
    -- --------------------------------------------------------

    SELECT b.*
    INTO v_branch
    FROM public.branches b
    WHERE b.id = p_branch_id
      AND b.business_id = p_business_id
      AND b.is_active = TRUE
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch is inactive or does not belong to this Business.';
    END IF;

    -- --------------------------------------------------------
    -- 4. Lock and validate target Business User
    --    Only the Branch Admin role is accepted here.
    -- --------------------------------------------------------

    SELECT bu.*
    INTO v_target_membership
    FROM public.business_users bu
    JOIN public.roles r
      ON r.id = bu.role_id
     AND r.business_id = bu.business_id
    JOIN public.users u
      ON u.id = bu.user_id
    WHERE bu.id = p_business_user_id
      AND bu.business_id = p_business_id
      AND bu.status = 'active'
      AND LOWER(BTRIM(r.role_name)) = 'branch admin'
      AND r.is_system = FALSE
      AND u.status = 'active'
      AND u.deleted_at IS NULL
    FOR UPDATE OF bu;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'The selected user is not an active Branch Admin of this Business.';
    END IF;

    -- --------------------------------------------------------
    -- 5. Prevent duplicate active assignment
    -- --------------------------------------------------------

    IF EXISTS (
        SELECT 1
        FROM public.branch_user_assignments a
        WHERE a.business_id = p_business_id
          AND a.branch_id = p_branch_id
          AND a.business_user_id = p_business_user_id
          AND a.assignment_type = 'branch_admin'
          AND a.assignment_status = 'active'
    ) THEN
        RAISE EXCEPTION 'This Branch Admin is already assigned to this Branch.';
    END IF;

    -- --------------------------------------------------------
    -- 6. Create a new assignment history record
    -- --------------------------------------------------------

    INSERT INTO public.branch_user_assignments (
        business_id,
        branch_id,
        business_user_id,
        assignment_type,
        assignment_status,
        effective_from,
        assigned_at,
        assigned_by,
        notes
    )
    VALUES (
        p_business_id,
        p_branch_id,
        p_business_user_id,
        'branch_admin',
        'active',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        p_actor_user_id,
        NULLIF(BTRIM(p_notes), '')
    )
    RETURNING *
    INTO v_assignment;

    -- --------------------------------------------------------
    -- 7. Audit log
    -- --------------------------------------------------------

    INSERT INTO public.audit_logs (
        business_id,
        user_id,
        action,
        table_name,
        record_id,
        old_values,
        new_values
    )
    VALUES (
        p_business_id,
        p_actor_user_id,
        'BRANCH_ADMIN_ASSIGNED',
        'branch_user_assignments',
        v_assignment.id,
        NULL,
        TO_JSONB(v_assignment)
    );

    RETURN v_assignment;
END;
$$;

ALTER FUNCTION public.fn_branch_assign_admin(
    UUID, UUID, UUID, UUID, TEXT
)
OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_branch_assign_admin(
    UUID, UUID, UUID, UUID, TEXT
)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_branch_assign_admin(
    UUID, UUID, UUID, UUID, TEXT
)
TO nokshighor_app;

COMMIT;
