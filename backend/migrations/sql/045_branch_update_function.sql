
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_branch_update(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_branch_id UUID,
    p_branch_name VARCHAR,
    p_branch_code VARCHAR,
    p_address TEXT,
    p_phone VARCHAR,
    p_email VARCHAR
)
RETURNS public.branches
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_branch public.branches%ROWTYPE;
    v_old_branch public.branches%ROWTYPE;
    v_branch_name VARCHAR;
    v_branch_code VARCHAR;
BEGIN
    v_branch_name := NULLIF(BTRIM(p_branch_name), '');
    v_branch_code := NULLIF(UPPER(BTRIM(p_branch_code)), '');

    IF v_branch_name IS NULL THEN
        RAISE EXCEPTION 'Branch name is required.'
            USING ERRCODE = 'P0001';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses b
        WHERE b.id = p_business_id
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active business not found.'
            USING ERRCODE = 'P0001';
    END IF;

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
        RAISE EXCEPTION 'Active Owner access is required.'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT *
    INTO v_old_branch
    FROM public.branches
    WHERE id = p_branch_id
      AND business_id = p_business_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Branch not found.'
            USING ERRCODE = 'P0001';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.branches b
        WHERE b.business_id = p_business_id
          AND b.id <> p_branch_id
          AND LOWER(BTRIM(b.branch_name)) = LOWER(v_branch_name)
    ) THEN
        RAISE EXCEPTION 'A branch with this name already exists.'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_branch_code IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.branches b
        WHERE b.business_id = p_business_id
          AND b.id <> p_branch_id
          AND UPPER(BTRIM(b.branch_code)) = v_branch_code
    ) THEN
        RAISE EXCEPTION 'A branch with this code already exists.'
            USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.branches
    SET
        branch_name = v_branch_name,
        branch_code = v_branch_code,
        address = NULLIF(BTRIM(p_address), ''),
        phone = NULLIF(BTRIM(p_phone), ''),
        email = NULLIF(BTRIM(p_email), ''),
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
        'BRANCH_UPDATED',
        'branches',
        p_branch_id,
        TO_JSONB(v_old_branch),
        TO_JSONB(v_branch)
    );

    RETURN v_branch;
END;
$$;

ALTER FUNCTION public.fn_branch_update(
    UUID, UUID, UUID, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR
) OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_branch_update(
    UUID, UUID, UUID, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_branch_update(
    UUID, UUID, UUID, VARCHAR, VARCHAR, TEXT, VARCHAR, VARCHAR
) TO nokshighor_app;

COMMIT;
