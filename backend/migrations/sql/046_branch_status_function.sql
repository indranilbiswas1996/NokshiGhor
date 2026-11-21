
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_branch_set_status(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_branch_id UUID,
    p_is_active BOOLEAN
)
RETURNS public.branches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_branch public.branches%ROWTYPE;
    v_old_branch public.branches%ROWTYPE;
    v_business_status TEXT;
    v_active_count INTEGER;
BEGIN
    IF p_is_active IS NULL THEN
        RAISE EXCEPTION 'Branch status is required.';
    END IF;

    -- Lock the business row to prevent concurrent status changes
    SELECT b.status
    INTO v_business_status
    FROM public.businesses b
    WHERE b.id = p_business_id
      AND b.status = 'active'
      AND b.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active business not found.';
    END IF;

    -- Verify active Owner membership
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r
          ON r.id = bu.role_id
         AND (r.business_id = bu.business_id OR r.business_id IS NULL)
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND LOWER(r.role_name) = 'owner'
    ) THEN
        RAISE EXCEPTION 'Active Owner access is required.';
    END IF;

    -- Lock the branch
    SELECT *
    INTO v_old_branch
    FROM public.branches
    WHERE id = p_branch_id
      AND business_id = p_business_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch not found.';
    END IF;

    -- No unnecessary status update
    IF v_old_branch.is_active = p_is_active THEN
        RETURN v_old_branch;
    END IF;

    IF p_is_active = FALSE THEN
        IF v_old_branch.is_default THEN
            RAISE EXCEPTION 'The default branch cannot be deactivated.';
        END IF;

        SELECT COUNT(*)
        INTO v_active_count
        FROM public.branches
        WHERE business_id = p_business_id
          AND is_active = TRUE;

        IF v_active_count <= 1 THEN
            RAISE EXCEPTION 'The last active branch cannot be deactivated.';
        END IF;
    END IF;

    UPDATE public.branches
    SET is_active = p_is_active,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = p_branch_id
      AND business_id = p_business_id
    RETURNING * INTO v_branch;

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
        CASE
            WHEN p_is_active THEN 'BRANCH_ACTIVATED'
            ELSE 'BRANCH_DEACTIVATED'
        END,
        'branches',
        p_branch_id,
        TO_JSONB(v_old_branch),
        TO_JSONB(v_branch)
    );

    RETURN v_branch;
END;
$$;

ALTER FUNCTION public.fn_branch_set_status(UUID, UUID, UUID, BOOLEAN)
OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_branch_set_status(UUID, UUID, UUID, BOOLEAN)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_branch_set_status(UUID, UUID, UUID, BOOLEAN)
TO nokshighor_app;

COMMIT;
