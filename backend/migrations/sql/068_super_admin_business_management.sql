BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'nokshighor_super_admin_manager'
    ) THEN
        CREATE ROLE nokshighor_super_admin_manager
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
            NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO nokshighor_super_admin_manager;
GRANT CREATE ON SCHEMA public TO nokshighor_super_admin_manager;

CREATE TABLE public.super_admin_users (
    user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL
);

INSERT INTO public.roles (role_name, description, business_id, is_system)
VALUES ('Super Admin', 'Platform-wide business administration', NULL, TRUE)
ON CONFLICT DO NOTHING;

GRANT SELECT (id, status, deleted_at)
ON public.users TO nokshighor_super_admin_manager;
GRANT SELECT (user_id)
ON public.super_admin_users TO nokshighor_super_admin_manager;
GRANT SELECT (id, business_name, business_type, status, deleted_at)
ON public.businesses TO nokshighor_super_admin_manager;
GRANT INSERT (business_name, business_type, status, created_by)
ON public.businesses TO nokshighor_super_admin_manager;
GRANT UPDATE (status, updated_at, updated_by)
ON public.businesses TO nokshighor_super_admin_manager;
GRANT SELECT (id, business_id, role_name, is_system)
ON public.roles TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, role_name, description, is_system, created_by)
ON public.roles TO nokshighor_super_admin_manager;
GRANT SELECT (id)
ON public.permissions TO nokshighor_super_admin_manager;
GRANT INSERT (role_id, permission_id, created_by)
ON public.role_permissions TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, role_id, role_owner_business_id)
ON public.business_role_access TO nokshighor_super_admin_manager;
GRANT SELECT (id, business_id)
ON public.units TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, unit_id, unit_owner_business_id)
ON public.business_unit_access TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, user_id, role_id, status, created_by)
ON public.business_users TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, shop_name, created_by)
ON public.business_settings TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, branch_name, branch_code, is_default, is_active, created_by)
ON public.branches TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, branch_id, warehouse_name, warehouse_code, is_default, is_active, created_by)
ON public.warehouses TO nokshighor_super_admin_manager;
GRANT SELECT (id)
ON public.roles TO nokshighor_super_admin_manager;
GRANT SELECT (business_id, role_id)
ON public.business_role_access TO nokshighor_super_admin_manager;
GRANT SELECT (business_id, role_id)
ON public.business_role_access TO nokshighor_super_admin_manager;
GRANT SELECT (business_id, id)
ON public.branches TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, user_id, action, table_name, record_id, old_values, new_values)
ON public.audit_logs TO nokshighor_super_admin_manager;

-- Triggers provision shared roles and units for each newly created business.
GRANT SELECT (id, business_id) ON public.roles TO nokshighor_super_admin_manager;
GRANT SELECT (id, business_id) ON public.units TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, role_id, role_owner_business_id)
ON public.business_role_access TO nokshighor_super_admin_manager;
GRANT INSERT (business_id, unit_id, unit_owner_business_id)
ON public.business_unit_access TO nokshighor_super_admin_manager;

CREATE OR REPLACE FUNCTION public.fn_is_super_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.super_admin_users sa
        JOIN public.users u ON u.id = sa.user_id
        WHERE sa.user_id = p_user_id
          AND u.status = 'active'
          AND u.deleted_at IS NULL
    );
$$;

ALTER FUNCTION public.fn_is_super_admin(UUID)
OWNER TO nokshighor_super_admin_manager;
REVOKE ALL ON FUNCTION public.fn_is_super_admin(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_is_super_admin(UUID) TO nokshighor_app;

CREATE OR REPLACE FUNCTION public.fn_super_admin_business_list(p_actor_user_id UUID)
RETURNS TABLE (
    id UUID,
    business_name VARCHAR(200),
    business_type VARCHAR(40),
    status VARCHAR(20)
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NOT public.fn_is_super_admin(p_actor_user_id) THEN
        RAISE EXCEPTION 'Super Admin access is required';
    END IF;

    RETURN QUERY
    SELECT b.id, b.business_name, b.business_type, b.status
    FROM public.businesses b
    WHERE b.deleted_at IS NULL
    ORDER BY b.business_name;
END;
$$;

ALTER FUNCTION public.fn_super_admin_business_list(UUID)
OWNER TO nokshighor_super_admin_manager;
REVOKE ALL ON FUNCTION public.fn_super_admin_business_list(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_super_admin_business_list(UUID) TO nokshighor_app;

CREATE OR REPLACE FUNCTION public.fn_super_admin_business_create(
    p_actor_user_id UUID,
    p_business_name VARCHAR,
    p_business_type VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_business_id UUID;
    v_owner_role_id UUID;
    v_branch_id UUID;
BEGIN
    IF NOT public.fn_is_super_admin(p_actor_user_id) THEN
        RAISE EXCEPTION 'Super Admin access is required';
    END IF;

    IF NULLIF(BTRIM(p_business_name), '') IS NULL THEN
        RAISE EXCEPTION 'Business name is required';
    END IF;

    IF p_business_type NOT IN ('electrical', 'interior', 'both', 'other') THEN
        RAISE EXCEPTION 'Invalid business type';
    END IF;

    INSERT INTO public.businesses (
        business_name, business_type, status, created_by
    )
    VALUES (
        BTRIM(p_business_name), p_business_type, 'active', p_actor_user_id
    )
    RETURNING id INTO v_business_id;

    INSERT INTO public.business_settings (
        business_id, shop_name, created_by
    ) VALUES (v_business_id, BTRIM(p_business_name), p_actor_user_id);

    INSERT INTO public.roles (
        business_id, role_name, description, is_system, created_by
    ) VALUES (
        v_business_id, 'Owner', 'Full access to this business', FALSE, p_actor_user_id
    ) RETURNING id INTO v_owner_role_id;

    INSERT INTO public.role_permissions (role_id, permission_id, created_by)
    SELECT v_owner_role_id, p.id, p_actor_user_id
    FROM public.permissions p
    ON CONFLICT (role_id, permission_id) DO NOTHING;

    INSERT INTO public.business_users (
        business_id, user_id, role_id, status, created_by
    ) VALUES (
        v_business_id, p_actor_user_id, v_owner_role_id, 'active', p_actor_user_id
    );

    INSERT INTO public.branches (
        business_id, branch_name, branch_code,
        is_default, is_active, created_by
    ) VALUES (
        v_business_id, 'Main Branch', 'MAIN', TRUE, TRUE, p_actor_user_id
    ) RETURNING id INTO v_branch_id;

    INSERT INTO public.warehouses (
        business_id, branch_id, warehouse_name, warehouse_code,
        is_default, is_active, created_by
    ) VALUES (
        v_business_id, v_branch_id, 'Main Warehouse', 'MAIN', TRUE, TRUE, p_actor_user_id
    );

    INSERT INTO public.audit_logs (
        business_id, user_id, action, table_name, record_id,
        old_values, new_values
    ) VALUES (
        v_business_id, p_actor_user_id, 'BUSINESS_CREATED', 'businesses',
        v_business_id, NULL,
        jsonb_build_object(
            'business_name', BTRIM(p_business_name),
            'business_type', p_business_type,
            'status', 'active'
        )
    );

    RETURN jsonb_build_object(
        'id', v_business_id,
        'business_name', BTRIM(p_business_name),
        'business_type', p_business_type,
        'status', 'active',
        'role_name', 'Owner'
    );
END;
$$;

ALTER FUNCTION public.fn_super_admin_business_create(UUID, VARCHAR, VARCHAR)
OWNER TO nokshighor_super_admin_manager;
REVOKE ALL ON FUNCTION public.fn_super_admin_business_create(UUID, VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_super_admin_business_create(UUID, VARCHAR, VARCHAR) TO nokshighor_app;

CREATE OR REPLACE FUNCTION public.fn_super_admin_business_set_status(
    p_actor_user_id UUID,
    p_business_id UUID,
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
    v_name VARCHAR(200);
BEGIN
    IF NOT public.fn_is_super_admin(p_actor_user_id) THEN
        RAISE EXCEPTION 'Super Admin access is required';
    END IF;

    IF p_status NOT IN ('active', 'inactive') THEN
        RAISE EXCEPTION 'Business status must be active or inactive';
    END IF;

    SELECT b.business_name, b.status
    INTO v_name, v_old_status
    FROM public.businesses b
    WHERE b.id = p_business_id
      AND b.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Business not found';
    END IF;

    UPDATE public.businesses
    SET status = p_status,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = p_business_id;

    INSERT INTO public.audit_logs (
        business_id, user_id, action, table_name, record_id,
        old_values, new_values
    ) VALUES (
        p_business_id, p_actor_user_id, 'BUSINESS_STATUS_CHANGED', 'businesses',
        p_business_id, jsonb_build_object('status', v_old_status),
        jsonb_build_object('status', p_status)
    );

    RETURN jsonb_build_object(
        'id', p_business_id,
        'business_name', v_name,
        'status', p_status
    );
END;
$$;

ALTER FUNCTION public.fn_super_admin_business_set_status(UUID, UUID, VARCHAR)
OWNER TO nokshighor_super_admin_manager;
REVOKE ALL ON FUNCTION public.fn_super_admin_business_set_status(UUID, UUID, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_super_admin_business_set_status(UUID, UUID, VARCHAR) TO nokshighor_app;

REVOKE CREATE ON SCHEMA public FROM nokshighor_super_admin_manager;

COMMIT;
