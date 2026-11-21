
BEGIN;

-- =========================================================
-- 041: SECURE SELF OWNER PROFILE UPDATE
-- Owner can update only their own name and phone.
-- Email and password are immutable through this feature.
-- =========================================================

CREATE OR REPLACE FUNCTION public.fn_owner_profile_update(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_full_name VARCHAR,
    p_phone VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_old_values JSONB;
    v_new_values JSONB;
BEGIN
    -- Validate input.
    IF NULLIF(BTRIM(p_full_name), '') IS NULL THEN
        RAISE EXCEPTION 'Owner name is required';
    END IF;

    -- Verify active Business.
    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses
        WHERE id = p_business_id
          AND status = 'active'
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Business not found or inactive';
    END IF;

    -- Verify actor is an active Owner in this Business.
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r
          ON r.id = bu.role_id
         AND r.business_id = bu.business_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND LOWER(r.role_name) = 'owner'
    ) THEN
        RAISE EXCEPTION 'Access denied: active Owner permission required';
    END IF;

    -- Lock only the actor's own User record.
    SELECT jsonb_build_object(
        'full_name', u.full_name,
        'phone', u.phone
    )
    INTO v_old_values
    FROM public.users u
    WHERE u.id = p_actor_user_id
      AND u.status = 'active'
      AND u.deleted_at IS NULL
    FOR UPDATE;

    IF v_old_values IS NULL THEN
        RAISE EXCEPTION 'Active User profile not found';
    END IF;

    -- Update only name and phone.
    UPDATE public.users
    SET full_name = BTRIM(p_full_name),
        phone = NULLIF(BTRIM(p_phone), ''),
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = p_actor_user_id
      AND status = 'active'
      AND deleted_at IS NULL;

    SELECT jsonb_build_object(
        'full_name', u.full_name,
        'phone', u.phone
    )
    INTO v_new_values
    FROM public.users u
    WHERE u.id = p_actor_user_id;

    -- Audit the profile change.
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
        'UPDATE',
        'users',
        p_actor_user_id,
        v_old_values,
        v_new_values
    );

    RETURN jsonb_build_object(
        'user_id', p_actor_user_id,
        'profile', v_new_values
    );
END;
$$;

ALTER FUNCTION public.fn_owner_profile_update(
    UUID, UUID, VARCHAR, VARCHAR
)
OWNER TO nokshighor_owner_manager;

REVOKE ALL ON FUNCTION public.fn_owner_profile_update(
    UUID, UUID, VARCHAR, VARCHAR
)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_owner_profile_update(
    UUID, UUID, VARCHAR, VARCHAR
)
TO nokshighor_app;

COMMIT;
