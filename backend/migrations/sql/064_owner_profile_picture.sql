BEGIN;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS profile_picture TEXT;

GRANT SELECT (profile_picture)
ON public.users
TO nokshighor_auth_reader;

GRANT SELECT (profile_picture), UPDATE (profile_picture, updated_at, updated_by)
ON public.users
TO nokshighor_owner_manager;

CREATE OR REPLACE FUNCTION public.fn_owner_list(
    p_business_id UUID,
    p_actor_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r
          ON r.id = bu.role_id
         AND r.business_id = bu.business_id
        JOIN public.businesses b
          ON b.id = bu.business_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND LOWER(r.role_name) = 'owner'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Access denied: active Owner permission required';
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'membership_id', bu.id,
                'user_id', u.id,
                'full_name', u.full_name,
                'email', u.email,
                'phone', u.phone,
                'profile_picture', u.profile_picture,
                'status', bu.status,
                'created_at', bu.created_at,
                'updated_at', bu.updated_at
            )
            ORDER BY u.full_name
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM public.business_users bu
    JOIN public.users u ON u.id = bu.user_id
    JOIN public.roles r
      ON r.id = bu.role_id
     AND r.business_id = bu.business_id
    WHERE bu.business_id = p_business_id
      AND LOWER(r.role_name) = 'owner';

    RETURN v_result;
END;
$$;

ALTER FUNCTION public.fn_owner_list(UUID, UUID)
OWNER TO nokshighor_owner_manager;

CREATE OR REPLACE FUNCTION public.fn_owner_profile_picture_update(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_target_user_id UUID,
    p_profile_picture TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_old_picture TEXT;
    v_new_picture TEXT;
BEGIN
    IF p_profile_picture IS NOT NULL THEN
        IF p_profile_picture !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$'
           OR octet_length(
                decode(split_part(p_profile_picture, ',', 2), 'base64')
           ) > 51200 THEN
            RAISE EXCEPTION 'Profile picture must be a valid image no larger than 50 KB';
        END IF;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses
        WHERE id = p_business_id
          AND status = 'active'
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Business not found or inactive';
    END IF;

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

    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r
          ON r.id = bu.role_id
         AND r.business_id = bu.business_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_target_user_id
          AND bu.status = 'active'
          AND LOWER(r.role_name) = 'owner'
    ) THEN
        RAISE EXCEPTION 'Active Owner profile not found';
    END IF;

    SELECT u.profile_picture
    INTO v_old_picture
    FROM public.users u
    WHERE u.id = p_target_user_id
      AND u.status = 'active'
      AND u.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active User profile not found';
    END IF;

    UPDATE public.users
    SET profile_picture = p_profile_picture,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = p_target_user_id
      AND status = 'active'
      AND deleted_at IS NULL
    RETURNING profile_picture INTO v_new_picture;

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
        p_target_user_id,
        jsonb_build_object('has_profile_picture', v_old_picture IS NOT NULL),
        jsonb_build_object('has_profile_picture', v_new_picture IS NOT NULL)
    );

    RETURN jsonb_build_object(
        'user_id', p_target_user_id,
        'profile_picture', v_new_picture
    );
END;
$$;

ALTER FUNCTION public.fn_owner_profile_picture_update(UUID, UUID, UUID, TEXT)
OWNER TO nokshighor_owner_manager;

REVOKE ALL ON FUNCTION public.fn_owner_profile_picture_update(UUID, UUID, UUID, TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_owner_profile_picture_update(UUID, UUID, UUID, TEXT)
TO nokshighor_app;

DROP FUNCTION public.fn_auth_user_by_id(UUID);

CREATE FUNCTION public.fn_auth_user_by_id(
    p_user_id UUID
)
RETURNS TABLE (
    id UUID,
    full_name VARCHAR,
    email VARCHAR,
    status VARCHAR,
    profile_picture TEXT
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT
        u.id,
        u.full_name,
        u.email,
        u.status,
        u.profile_picture
    FROM public.users AS u
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
    LIMIT 1;
$$;

ALTER FUNCTION public.fn_auth_user_by_id(UUID)
OWNER TO nokshighor_auth_reader;

REVOKE ALL ON FUNCTION public.fn_auth_user_by_id(UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_auth_user_by_id(UUID)
TO nokshighor_app;

COMMIT;