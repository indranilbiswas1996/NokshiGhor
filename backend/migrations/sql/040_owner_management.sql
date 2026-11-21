
BEGIN;

-- =========================================================
-- 040: SECURE OWNER MANAGEMENT
-- =========================================================

-- 1. Dedicated database role
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'nokshighor_owner_manager'
    ) THEN
        CREATE ROLE nokshighor_owner_manager
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            NOINHERIT;
    END IF;
END
$$;

-- 2. Audit log: preserve both before and after values.
ALTER TABLE public.audit_logs
    ADD COLUMN IF NOT EXISTS new_values JSONB;

GRANT USAGE ON SCHEMA public
TO nokshighor_owner_manager;

GRANT CREATE ON SCHEMA public
TO nokshighor_owner_manager;

-- 3. Least-privilege table permissions.

GRANT SELECT (id, status, deleted_at)
ON public.businesses
TO nokshighor_owner_manager;

GRANT SELECT (id, business_id, role_name, is_system)
ON public.roles
TO nokshighor_owner_manager;

GRANT SELECT (business_id, role_id)
ON public.business_role_access
TO nokshighor_owner_manager;

GRANT SELECT (
    id, full_name, email, phone, status, deleted_at
)
ON public.users
TO nokshighor_owner_manager;

GRANT INSERT (
    full_name, email, phone, password_hash,
    status, created_by
)
ON public.users
TO nokshighor_owner_manager;

GRANT UPDATE (
    full_name, email, phone, updated_at, updated_by
)
ON public.users
TO nokshighor_owner_manager;

GRANT SELECT (
    id, business_id, user_id, role_id, status,
    created_at, created_by, updated_at, updated_by
)
ON public.business_users
TO nokshighor_owner_manager;

GRANT INSERT (
    business_id, user_id, role_id, status, created_by
)
ON public.business_users
TO nokshighor_owner_manager;

GRANT UPDATE (
    status, updated_at, updated_by
)
ON public.business_users
TO nokshighor_owner_manager;

GRANT INSERT (
    business_id, user_id, action, table_name,
    record_id, old_values, new_values
)
ON public.audit_logs
TO nokshighor_owner_manager;


-- =========================================================
-- 4. LIST OWNERS
-- =========================================================

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


-- =========================================================
-- 5. ADD OWNER
-- =========================================================

CREATE OR REPLACE FUNCTION public.fn_owner_add(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_full_name VARCHAR,
    p_email VARCHAR,
    p_phone VARCHAR,
    p_password_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id UUID;
    v_membership_id UUID;
    v_role_id UUID;
    v_existing_status VARCHAR(20);
    v_existing_membership UUID;
    v_created_user BOOLEAN := FALSE;
BEGIN
    -- Validate input.
    IF NULLIF(BTRIM(p_full_name), '') IS NULL
       OR NULLIF(BTRIM(p_email), '') IS NULL THEN
        RAISE EXCEPTION 'Owner name and email are required';
    END IF;

    -- Serialize Owner membership changes for this Business.
    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_business_id::TEXT, 0)
    );
        
    -- Verify Business and actor.
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

    -- Find the Business-specific Owner role.
    SELECT r.id
    INTO v_role_id
    FROM public.roles r
    JOIN public.business_role_access bra
      ON bra.business_id = r.business_id
     AND bra.role_id = r.id
    WHERE r.business_id = p_business_id
      AND LOWER(r.role_name) = 'owner'
      AND r.is_system = FALSE
    LIMIT 1;

    IF v_role_id IS NULL THEN
        RAISE EXCEPTION 'Owner role is not configured for this Business';
    END IF;

    -- Reuse an existing active User by email.
    SELECT id, status
    INTO v_user_id, v_existing_status
    FROM public.users
    WHERE LOWER(email) = LOWER(BTRIM(p_email))
      AND deleted_at IS NULL
    LIMIT 1;

    IF v_user_id IS NOT NULL THEN
        IF v_existing_status <> 'active' THEN
            RAISE EXCEPTION 'Existing User is inactive or locked';
        END IF;
    ELSE
        IF NULLIF(BTRIM(p_password_hash), '') IS NULL THEN
            RAISE EXCEPTION 'Password hash is required for a new User';
        END IF;

        INSERT INTO public.users (
            full_name,
            email,
            phone,
            password_hash,
            status,
            created_by
        )
        VALUES (
            BTRIM(p_full_name),
            LOWER(BTRIM(p_email)),
            NULLIF(BTRIM(p_phone), ''),
            p_password_hash,
            'active',
            p_actor_user_id
        )
        ON CONFLICT (lower(email))
        WHERE deleted_at IS NULL
        DO NOTHING
        RETURNING id INTO v_user_id;

        IF v_user_id IS NULL THEN
            SELECT id, status
            INTO v_user_id, v_existing_status
            FROM public.users
            WHERE LOWER(email) = LOWER(BTRIM(p_email))
              AND deleted_at IS NULL
            LIMIT 1;

            IF v_user_id IS NULL OR v_existing_status <> 'active' THEN
                RAISE EXCEPTION 'Unable to create or reuse User';
            END IF;
        ELSE
            v_created_user := TRUE;
        END IF;
    END IF;

    -- Do not create duplicate Business membership.
    SELECT id
    INTO v_existing_membership
    FROM public.business_users
    WHERE business_id = p_business_id
      AND user_id = v_user_id;

    IF v_existing_membership IS NOT NULL THEN
        RAISE EXCEPTION
            'User already has a Business membership; reactivate or manage the existing membership';
    END IF;

    INSERT INTO public.business_users (
        business_id,
        user_id,
        role_id,
        status,
        created_by
    )
    VALUES (
        p_business_id,
        v_user_id,
        v_role_id,
        'active',
        p_actor_user_id
    )
    RETURNING id INTO v_membership_id;

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
        'INSERT',
        'business_users',
        v_membership_id,
        NULL,
        jsonb_build_object(
            'user_id', v_user_id,
            'full_name', p_full_name,
            'email', p_email,
            'phone', p_phone,
            'role', 'Owner',
            'status', 'active',
            'new_user_created', v_created_user
        )
    );

    RETURN jsonb_build_object(
        'membership_id', v_membership_id,
        'user_id', v_user_id,
        'full_name', (
            SELECT full_name FROM public.users WHERE id = v_user_id
        ),
        'email', (
            SELECT email FROM public.users WHERE id = v_user_id
        ),
        'status', 'active',
        'new_user_created', v_created_user
    );
END;
$$;


-- =========================================================
-- 6. EDIT OWNER PROFILE
-- =========================================================

CREATE OR REPLACE FUNCTION public.fn_owner_update(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_membership_id UUID,
    p_full_name VARCHAR,
    p_email VARCHAR,
    p_phone VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_user_id UUID;
    v_old_values JSONB;
    v_new_values JSONB;
BEGIN
    IF NULLIF(BTRIM(p_full_name), '') IS NULL
       OR NULLIF(BTRIM(p_email), '') IS NULL THEN
        RAISE EXCEPTION 'Owner name and email are required';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_business_id::TEXT, 0)
    );
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

    SELECT u.id,
           jsonb_build_object(
               'full_name', u.full_name,
               'email', u.email,
               'phone', u.phone
           )
    INTO v_user_id, v_old_values
    FROM public.business_users bu
    JOIN public.roles r
      ON r.id = bu.role_id
     AND r.business_id = bu.business_id
    JOIN public.users u ON u.id = bu.user_id
    WHERE bu.id = p_membership_id
      AND bu.business_id = p_business_id
      AND LOWER(r.role_name) = 'owner'
    FOR UPDATE OF u;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Owner membership not found';
    END IF;

    IF v_user_id <> p_actor_user_id THEN
        RAISE EXCEPTION 'Owners can only edit their own profile';
    END IF;

    UPDATE public.users
    SET full_name = BTRIM(p_full_name),
        email = LOWER(BTRIM(p_email)),
        phone = NULLIF(BTRIM(p_phone), ''),
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = v_user_id
      AND deleted_at IS NULL;

    SELECT jsonb_build_object(
        'full_name', full_name,
        'email', email,
        'phone', phone
    )
    INTO v_new_values
    FROM public.users
    WHERE id = v_user_id;

    INSERT INTO public.audit_logs (
        business_id, user_id, action,
        table_name, record_id, old_values, new_values
    )
    VALUES (
        p_business_id, p_actor_user_id, 'UPDATE',
        'users', v_user_id, v_old_values, v_new_values
    );

    RETURN jsonb_build_object(
        'membership_id', p_membership_id,
        'user_id', v_user_id,
        'profile', v_new_values
    );
END;
$$;


-- =========================================================
-- 7. INACTIVE / REACTIVATE OWNER
-- =========================================================

CREATE OR REPLACE FUNCTION public.fn_owner_set_status(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_membership_id UUID,
    p_status VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_old_status VARCHAR(20);
    v_user_id UUID;
    v_active_owners BIGINT;
BEGIN
    IF p_status IS NULL OR p_status NOT IN ('active', 'inactive') THEN
        RAISE EXCEPTION 'Invalid Owner status';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(p_business_id::TEXT, 0)
    );
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

    SELECT bu.status, bu.user_id
    INTO v_old_status, v_user_id
    FROM public.business_users bu
    JOIN public.roles r
      ON r.id = bu.role_id
     AND r.business_id = bu.business_id
    WHERE bu.id = p_membership_id
      AND bu.business_id = p_business_id
      AND LOWER(r.role_name) = 'owner'
    FOR UPDATE OF bu;

    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Owner membership not found';
    END IF;
    IF p_status = 'inactive' AND v_user_id = p_actor_user_id THEN
        RAISE EXCEPTION 'Owners cannot deactivate their own account';
    END IF;
    IF v_old_status = p_status THEN
        RETURN jsonb_build_object(
            'membership_id', p_membership_id,
            'user_id', v_user_id,
            'status', p_status,
            'changed', FALSE
        );
    END IF;

    IF p_status = 'inactive' THEN
        SELECT COUNT(*)
        INTO v_active_owners
        FROM public.business_users bu
        JOIN public.roles r
          ON r.id = bu.role_id
         AND r.business_id = bu.business_id
        WHERE bu.business_id = p_business_id
          AND bu.status = 'active'
          AND LOWER(r.role_name) = 'owner';

        IF v_active_owners <= 1 THEN
            RAISE EXCEPTION 'The last active Owner cannot be deactivated';
        END IF;
    END IF;

    UPDATE public.business_users
    SET status = p_status,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = p_membership_id
      AND business_id = p_business_id;

    INSERT INTO public.audit_logs (
        business_id, user_id, action,
        table_name, record_id, old_values, new_values
    )
    VALUES (
        p_business_id,
        p_actor_user_id,
        'UPDATE',
        'business_users',
        p_membership_id,
        jsonb_build_object(
            'user_id', v_user_id,
            'status', v_old_status
        ),
        jsonb_build_object(
            'user_id', v_user_id,
            'status', p_status
        )
    );

    RETURN jsonb_build_object(
        'membership_id', p_membership_id,
        'user_id', v_user_id,
        'status', p_status,
        'changed', TRUE
    );
END;
$$;


-- =========================================================
-- 8. FUNCTION OWNERSHIP
-- =========================================================

ALTER FUNCTION public.fn_owner_list(UUID, UUID)
OWNER TO nokshighor_owner_manager;

ALTER FUNCTION public.fn_owner_add(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
)
OWNER TO nokshighor_owner_manager;

ALTER FUNCTION public.fn_owner_update(
    UUID, UUID, UUID, VARCHAR, VARCHAR, VARCHAR
)
OWNER TO nokshighor_owner_manager;

ALTER FUNCTION public.fn_owner_set_status(
    UUID, UUID, UUID, VARCHAR
)
OWNER TO nokshighor_owner_manager;


-- =========================================================
-- 9. REVOKE DIRECT ACCESS / GRANT EXECUTE
-- =========================================================

REVOKE CREATE ON SCHEMA public
FROM nokshighor_owner_manager;


REVOKE ALL ON FUNCTION public.fn_owner_list(UUID, UUID)
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_owner_add(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
)
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_owner_update(
    UUID, UUID, UUID, VARCHAR, VARCHAR, VARCHAR
)
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_owner_set_status(
    UUID, UUID, UUID, VARCHAR
)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_owner_list(UUID, UUID)
TO nokshighor_app;

GRANT EXECUTE ON FUNCTION public.fn_owner_add(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
)
TO nokshighor_app;

GRANT EXECUTE ON FUNCTION public.fn_owner_update(
    UUID, UUID, UUID, VARCHAR, VARCHAR, VARCHAR
)
TO nokshighor_app;

GRANT EXECUTE ON FUNCTION public.fn_owner_set_status(
    UUID, UUID, UUID, VARCHAR
)
TO nokshighor_app;

COMMIT;
