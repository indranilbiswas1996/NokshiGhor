
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_branch_set_default(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_branch_id UUID
)
RETURNS public.branches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_branch public.branches%ROWTYPE;
    v_old_default public.branches%ROWTYPE;
    v_new_branch public.branches%ROWTYPE;
BEGIN
    -- Lock business to prevent concurrent default changes
    PERFORM 1
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

    -- Lock target branch
    SELECT *
    INTO v_branch
    FROM public.branches
    WHERE id = p_branch_id
      AND business_id = p_business_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch not found.';
    END IF;

    IF NOT v_branch.is_active THEN
        RAISE EXCEPTION 'Inactive branch cannot be set as default.';
    END IF;

    -- No unnecessary update
    IF v_branch.is_default THEN
        RETURN v_branch;
    END IF;

    -- Lock and unset existing default branch
    SELECT *
    INTO v_old_default
    FROM public.branches
    WHERE business_id = p_business_id
      AND is_default = TRUE
    FOR UPDATE;

    IF FOUND THEN
        UPDATE public.branches
        SET is_default = FALSE,
            updated_at = CURRENT_TIMESTAMP,
            updated_by = p_actor_user_id
        WHERE id = v_old_default.id
        RETURNING * INTO v_old_default;

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
            'BRANCH_DEFAULT_REMOVED',
            'branches',
            v_old_default.id,
            TO_JSONB(v_old_default) || '{"is_default": true}'::JSONB,
            TO_JSONB(v_old_default)
        );
    END IF;

    -- Set new default branch
    UPDATE public.branches
    SET is_default = TRUE,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = p_branch_id
      AND business_id = p_business_id
    RETURNING * INTO v_new_branch;

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
        'BRANCH_DEFAULT_SET',
        'branches',
        p_branch_id,
        TO_JSONB(v_branch),
        TO_JSONB(v_new_branch)
    );

    RETURN v_new_branch;
END;
$$;

ALTER FUNCTION public.fn_branch_set_default(UUID, UUID, UUID)
OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_branch_set_default(UUID, UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_branch_set_default(UUID, UUID, UUID)
TO nokshighor_app;

COMMIT;
