
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_branch_admin_add(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_full_name VARCHAR,
    p_email VARCHAR,
    p_phone VARCHAR,
    p_password_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_business_user_id UUID;
    v_role_id UUID;
    v_user_created BOOLEAN := FALSE;
    v_result JSONB;
BEGIN
    -- Validate active Business
    IF NOT EXISTS (
        SELECT 1
        FROM businesses
        WHERE id = p_business_id
          AND status = 'active'
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Business not found or inactive.';
    END IF;

    -- Only an active Owner can add Branch Admin
    IF NOT EXISTS (
        SELECT 1
        FROM business_users bu
        JOIN roles r ON r.id = bu.role_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND r.business_id = p_business_id
          AND LOWER(r.role_name) = 'owner'
          AND r.is_system = FALSE
    ) THEN
        RAISE EXCEPTION 'Only an active Owner can add Branch Admin.';
    END IF;

    -- Resolve Business-specific Branch Admin role
    SELECT r.id
    INTO v_role_id
    FROM roles r
    JOIN business_role_access bra
      ON bra.role_id = r.id
     AND bra.business_id = r.business_id
    WHERE r.business_id = p_business_id
      AND LOWER(BTRIM(r.role_name)) = 'branch admin'
      AND r.is_system = FALSE
    LIMIT 1;

    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Branch Admin role not configured for this Business.';
    END IF;

    -- Validate input
    IF NULLIF(BTRIM(p_full_name), '') IS NULL
       OR NULLIF(BTRIM(p_email), '') IS NULL THEN
        RAISE EXCEPTION 'Name and email are required.';
    END IF;

    -- Reuse existing active User by email
    SELECT id
    INTO v_user_id
    FROM users
    WHERE LOWER(email) = LOWER(BTRIM(p_email))
      AND status = 'active'
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_user_id IS NULL THEN
        IF NULLIF(p_password_hash, '') IS NULL THEN
            RAISE EXCEPTION 'Password is required for a new User.';
        END IF;

        INSERT INTO users (
            full_name,
            email,
            phone,
            password_hash,
            status,
            created_by,
            updated_by
        )
        VALUES (
            BTRIM(p_full_name),
            LOWER(BTRIM(p_email)),
            NULLIF(BTRIM(p_phone), ''),
            p_password_hash,
            'active',
            p_actor_user_id,
            p_actor_user_id
        )
        RETURNING id INTO v_user_id;

        v_user_created := TRUE;
    END IF;

    -- Do not replace an existing Business membership
    IF EXISTS (
        SELECT 1
        FROM business_users
        WHERE business_id = p_business_id
          AND user_id = v_user_id
    ) THEN
        RAISE EXCEPTION 'User already has a membership in this Business.';
    END IF;

    -- Create active Branch Admin membership
    INSERT INTO business_users (
        business_id,
        user_id,
        role_id,
        status,
        created_by,
        updated_by
    )
    VALUES (
        p_business_id,
        v_user_id,
        v_role_id,
        'active',
        p_actor_user_id,
        p_actor_user_id
    )
    RETURNING id INTO v_business_user_id;

    -- Audit
    INSERT INTO audit_logs (
        business_id,
        user_id,
        action,
        table_name,
        record_id,
        old_values,
        new_values,
        created_at
    )
    VALUES (
        p_business_id,
        p_actor_user_id,
        'BRANCH_ADMIN_CREATED',
        'business_users',
        v_business_user_id,
        NULL,
        jsonb_build_object(
            'business_user_id', v_business_user_id,
            'user_id', v_user_id,
            'role_id', v_role_id,
            'role_name', 'Branch Admin',
            'new_user_created', v_user_created
        ),
        NOW()
    );

    SELECT jsonb_build_object(
        'business_user_id', bu.id,
        'user_id', u.id,
        'full_name', u.full_name,
        'email', u.email,
        'phone', u.phone,
        'role_name', 'Branch Admin',
        'new_user_created', v_user_created
    )
    INTO v_result
    FROM business_users bu
    JOIN users u ON u.id = bu.user_id
    WHERE bu.id = v_business_user_id;

    RETURN v_result;
END;
$$;

ALTER FUNCTION public.fn_branch_admin_add(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
) OWNER TO nokshighor_owner_manager;

REVOKE ALL ON FUNCTION public.fn_branch_admin_add(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_branch_admin_add(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
) TO nokshighor_app;

COMMIT;
