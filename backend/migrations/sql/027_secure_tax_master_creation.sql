BEGIN;

-- =====================================================
-- 1. Grant limited SELECT permissions to tax writer
-- =====================================================

GRANT SELECT (id, business_id, tax_code, tax_name,
              description, is_active, created_at,
              created_by, updated_at, updated_by, deleted_at)
ON public.tax_types TO nokshighor_tax_writer;

GRANT SELECT (id, business_id, component_code,
              component_name, jurisdiction_level,
              description, is_active, created_at,
              created_by, updated_at, updated_by, deleted_at)
ON public.tax_components TO nokshighor_tax_writer;

GRANT SELECT (id, business_id, profile_code,
              profile_name, description, is_active,
              created_at, created_by, updated_at,
              updated_by, deleted_at)
ON public.tax_profiles TO nokshighor_tax_writer;

-- =====================================================
-- 2. Grant INSERT permissions
-- =====================================================

GRANT INSERT ON public.tax_types
TO nokshighor_tax_writer;

GRANT INSERT ON public.tax_components
TO nokshighor_tax_writer;

GRANT INSERT ON public.tax_profiles
TO nokshighor_tax_writer;

-- =====================================================
-- 3. Permission lookup access
-- =====================================================

GRANT SELECT (business_id, user_id, role_id, status)
ON public.business_users TO nokshighor_tax_writer;

GRANT SELECT (id, status, deleted_at)
ON public.businesses TO nokshighor_tax_writer;

GRANT SELECT (id, permission_key)
ON public.permissions TO nokshighor_tax_writer;

GRANT SELECT (role_id, permission_id)
ON public.role_permissions TO nokshighor_tax_writer;

GRANT SELECT (id, business_id, role_name)
ON public.roles TO nokshighor_tax_writer;


-- =====================================================
-- 4. Secure Tax Type creation
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_create_tax_type(
    p_user_id UUID,
    p_business_id UUID,
    p_tax_code VARCHAR,
    p_tax_name VARCHAR,
    p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b
          ON b.id = bu.business_id
        JOIN public.roles r
          ON r.id = bu.role_id
        JOIN public.role_permissions rp
          ON rp.role_id = r.id
        JOIN public.permissions p
          ON p.id = rp.permission_id
        WHERE bu.user_id = p_user_id
          AND bu.business_id = p_business_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
          AND p.permission_key = 'tax.manage'
    ) THEN
        RAISE EXCEPTION 'Tax management permission required';
    END IF;

    IF p_tax_code IS NULL OR btrim(p_tax_code) = ''
       OR p_tax_name IS NULL OR btrim(p_tax_name) = '' THEN
        RAISE EXCEPTION 'Invalid tax type details';
    END IF;

    INSERT INTO public.tax_types (
        business_id, tax_code, tax_name,
        description, created_by
    )
    VALUES (
        p_business_id, btrim(p_tax_code),
        btrim(p_tax_name), p_description, p_user_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- =====================================================
-- 5. Secure Tax Component creation
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_create_tax_component(
    p_user_id UUID,
    p_business_id UUID,
    p_component_code VARCHAR,
    p_component_name VARCHAR,
    p_jurisdiction_level VARCHAR,
    p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b
          ON b.id = bu.business_id
        JOIN public.roles r
          ON r.id = bu.role_id
        JOIN public.role_permissions rp
          ON rp.role_id = r.id
        JOIN public.permissions p
          ON p.id = rp.permission_id
        WHERE bu.user_id = p_user_id
          AND bu.business_id = p_business_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
          AND p.permission_key = 'tax.manage'
    ) THEN
        RAISE EXCEPTION 'Tax management permission required';
    END IF;

    IF p_component_code IS NULL OR btrim(p_component_code) = ''
       OR p_component_name IS NULL OR btrim(p_component_name) = '' THEN
        RAISE EXCEPTION 'Invalid tax component details';
    END IF;

    IF p_jurisdiction_level NOT IN (
        'central', 'state', 'integrated', 'local', 'other'
    ) THEN
        RAISE EXCEPTION 'Invalid tax component jurisdiction';
    END IF;

    INSERT INTO public.tax_components (
        business_id, component_code, component_name,
        jurisdiction_level, description, created_by
    )
    VALUES (
        p_business_id, btrim(p_component_code),
        btrim(p_component_name), p_jurisdiction_level,
        p_description, p_user_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- =====================================================
-- 6. Secure Tax Profile creation
-- =====================================================

CREATE OR REPLACE FUNCTION public.fn_create_tax_profile(
    p_user_id UUID,
    p_business_id UUID,
    p_profile_code VARCHAR,
    p_profile_name VARCHAR,
    p_description TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_id UUID;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b
          ON b.id = bu.business_id
        JOIN public.roles r
          ON r.id = bu.role_id
        JOIN public.role_permissions rp
          ON rp.role_id = r.id
        JOIN public.permissions p
          ON p.id = rp.permission_id
        WHERE bu.user_id = p_user_id
          AND bu.business_id = p_business_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
          AND p.permission_key = 'tax.manage'
    ) THEN
        RAISE EXCEPTION 'Tax management permission required';
    END IF;

    IF p_profile_code IS NULL OR btrim(p_profile_code) = ''
       OR p_profile_name IS NULL OR btrim(p_profile_name) = '' THEN
        RAISE EXCEPTION 'Invalid tax profile details';
    END IF;

    INSERT INTO public.tax_profiles (
        business_id, profile_code, profile_name,
        description, created_by
    )
    VALUES (
        p_business_id, btrim(p_profile_code),
        btrim(p_profile_name), p_description, p_user_id
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- =====================================================
-- 7. Function ownership and access control
-- =====================================================

ALTER FUNCTION public.fn_create_tax_type(
    UUID, UUID, VARCHAR, VARCHAR, TEXT
) OWNER TO nokshighor_tax_writer;

ALTER FUNCTION public.fn_create_tax_component(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
) OWNER TO nokshighor_tax_writer;

ALTER FUNCTION public.fn_create_tax_profile(
    UUID, UUID, VARCHAR, VARCHAR, TEXT
) OWNER TO nokshighor_tax_writer;

REVOKE ALL ON FUNCTION public.fn_create_tax_type(
    UUID, UUID, VARCHAR, VARCHAR, TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_create_tax_component(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_create_tax_profile(
    UUID, UUID, VARCHAR, VARCHAR, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_create_tax_type(
    UUID, UUID, VARCHAR, VARCHAR, TEXT
) TO nokshighor_app;

GRANT EXECUTE ON FUNCTION public.fn_create_tax_component(
    UUID, UUID, VARCHAR, VARCHAR, VARCHAR, TEXT
) TO nokshighor_app;

GRANT EXECUTE ON FUNCTION public.fn_create_tax_profile(
    UUID, UUID, VARCHAR, VARCHAR, TEXT
) TO nokshighor_app;

COMMIT;