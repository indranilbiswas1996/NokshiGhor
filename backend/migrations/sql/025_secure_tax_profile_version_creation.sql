
BEGIN;

-- 1. Dedicated tax writer role
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'nokshighor_tax_writer'
    ) THEN
        CREATE ROLE nokshighor_tax_writer
        WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
        NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

GRANT USAGE, CREATE ON SCHEMA public
TO nokshighor_tax_writer;

-- 2. Limited read permissions
GRANT SELECT (business_id, user_id, status)
ON public.business_users TO nokshighor_tax_writer;

GRANT SELECT (id, status, deleted_at)
ON public.businesses TO nokshighor_tax_writer;

GRANT SELECT (id, business_id, is_active, deleted_at)
ON public.tax_profiles TO nokshighor_tax_writer;

GRANT SELECT (id, business_id, is_active, deleted_at)
ON public.tax_types TO nokshighor_tax_writer;

GRANT SELECT (
    id,
    business_id,
    component_code,
    component_name,
    jurisdiction_level,
    is_active,
    deleted_at
)
ON public.tax_components TO nokshighor_tax_writer;

-- 3. Version creation permissions
GRANT INSERT ON public.tax_profile_versions
TO nokshighor_tax_writer;

GRANT SELECT (id) ON public.tax_profile_versions
TO nokshighor_tax_writer;

GRANT INSERT ON public.tax_profile_version_components
TO nokshighor_tax_writer;


-- 4. Atomic version and component creation
CREATE OR REPLACE FUNCTION public.fn_create_tax_profile_version(
    p_user_id UUID,
    p_business_id UUID,
    p_tax_profile_id UUID,
    p_version_number INTEGER,
    p_tax_type_id UUID,
    p_calculation_mode VARCHAR,
    p_rounding_mode VARCHAR,
    p_rounding_precision SMALLINT,
    p_effective_from TIMESTAMPTZ,
    p_effective_to TIMESTAMPTZ,
    p_version_notes TEXT,
    p_components JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_version_id UUID;
    v_component JSONB;
    v_component_id UUID;
    v_component_rate NUMERIC(7,4);
    v_calculation_order SMALLINT;

    v_component_code VARCHAR(40);
    v_component_name VARCHAR(120);
    v_jurisdiction VARCHAR(30);

    v_component_count INTEGER := 0;
BEGIN
    -- Validate user membership and business status
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b
          ON b.id = bu.business_id
        WHERE bu.user_id = p_user_id
          AND bu.business_id = p_business_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active business membership required';
    END IF;

    -- Validate basic input
    IF p_version_number <= 0 THEN
        RAISE EXCEPTION 'Invalid version number';
    END IF;

    IF p_calculation_mode NOT IN ('exclusive', 'inclusive') THEN
        RAISE EXCEPTION 'Invalid calculation mode';
    END IF;

    IF p_rounding_mode NOT IN (
        'half_up', 'half_even', 'down', 'up'
    ) THEN
        RAISE EXCEPTION 'Invalid rounding mode';
    END IF;

    IF p_rounding_precision NOT BETWEEN 0 AND 4 THEN
        RAISE EXCEPTION 'Rounding precision must be between 0 and 4';
    END IF;

    IF p_effective_from IS NOT NULL
       AND p_effective_to IS NOT NULL
       AND p_effective_to <= p_effective_from THEN
        RAISE EXCEPTION 'Invalid effective period';
    END IF;

    IF p_components IS NULL
       OR jsonb_typeof(p_components) <> 'array'
       OR jsonb_array_length(p_components) = 0 THEN
        RAISE EXCEPTION 'At least one tax component is required';
    END IF;

    -- Validate profile belongs to this business
    IF NOT EXISTS (
        SELECT 1
        FROM public.tax_profiles
        WHERE id = p_tax_profile_id
          AND business_id = p_business_id
          AND is_active = TRUE
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active tax profile not found';
    END IF;

    -- Validate tax type belongs to this business
    IF NOT EXISTS (
        SELECT 1
        FROM public.tax_types
        WHERE id = p_tax_type_id
          AND business_id = p_business_id
          AND is_active = TRUE
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active tax type not found';
    END IF;

    -- Validate duplicate component IDs
    IF (
        SELECT COUNT(*)
        FROM (
            SELECT value->>'tax_component_id'
            FROM jsonb_array_elements(p_components)
            GROUP BY value->>'tax_component_id'
        ) x
    ) <> jsonb_array_length(p_components) THEN
        RAISE EXCEPTION 'Duplicate tax components are not allowed';
    END IF;

    -- Validate duplicate calculation orders
    IF (
        SELECT COUNT(*)
        FROM (
            SELECT value->>'calculation_order'
            FROM jsonb_array_elements(p_components)
            GROUP BY value->>'calculation_order'
        ) x
    ) <> jsonb_array_length(p_components) THEN
        RAISE EXCEPTION 'Duplicate calculation orders are not allowed';
    END IF;

    -- Create version
    INSERT INTO public.tax_profile_versions (
        business_id,
        tax_profile_id,
        version_number,
        tax_type_id,
        calculation_mode,
        rounding_mode,
        rounding_precision,
        effective_from,
        effective_to,
        version_status,
        version_notes,
        created_by
    )
    VALUES (
        p_business_id,
        p_tax_profile_id,
        p_version_number,
        p_tax_type_id,
        p_calculation_mode,
        p_rounding_mode,
        p_rounding_precision,
        p_effective_from,
        p_effective_to,
        'draft',
        p_version_notes,
        p_user_id
    )
    RETURNING id INTO v_version_id;

    -- Create component snapshots
    FOR v_component IN
        SELECT value
        FROM jsonb_array_elements(p_components)
    LOOP
        v_component_id :=
            (v_component->>'tax_component_id')::UUID;

        v_component_rate :=
            (v_component->>'tax_rate')::NUMERIC(7,4);

        v_calculation_order :=
            COALESCE(
                (v_component->>'calculation_order')::SMALLINT,
                1
            );

        IF v_component_rate NOT BETWEEN 0 AND 100 THEN
            RAISE EXCEPTION 'Invalid tax component rate';
        END IF;

        IF v_calculation_order <= 0 THEN
            RAISE EXCEPTION 'Invalid calculation order';
        END IF;

        SELECT
            component_code,
            component_name,
            jurisdiction_level
        INTO
            v_component_code,
            v_component_name,
            v_jurisdiction
        FROM public.tax_components
        WHERE id = v_component_id
          AND business_id = p_business_id
          AND is_active = TRUE
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Active tax component not found: %',
                v_component_id;
        END IF;

        INSERT INTO public.tax_profile_version_components (
            business_id,
            tax_profile_version_id,
            tax_component_id,
            component_code_snapshot,
            component_name_snapshot,
            jurisdiction_snapshot,
            tax_rate,
            calculation_order,
            created_by
        )
        VALUES (
            p_business_id,
            v_version_id,
            v_component_id,
            v_component_code,
            v_component_name,
            v_jurisdiction,
            v_component_rate,
            v_calculation_order,
            p_user_id
        );

        v_component_count := v_component_count + 1;
    END LOOP;

    IF v_component_count <> jsonb_array_length(p_components) THEN
        RAISE EXCEPTION 'Tax component creation incomplete';
    END IF;

    RETURN v_version_id;
END;
$function$;

ALTER FUNCTION public.fn_create_tax_profile_version(
    UUID, UUID, UUID, INTEGER, UUID,
    VARCHAR, VARCHAR, SMALLINT,
    TIMESTAMPTZ, TIMESTAMPTZ, TEXT, JSONB
)
OWNER TO nokshighor_tax_writer;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_tax_writer;

REVOKE ALL ON FUNCTION public.fn_create_tax_profile_version(
    UUID, UUID, UUID, INTEGER, UUID,
    VARCHAR, VARCHAR, SMALLINT,
    TIMESTAMPTZ, TIMESTAMPTZ, TEXT, JSONB
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_create_tax_profile_version(
    UUID, UUID, UUID, INTEGER, UUID,
    VARCHAR, VARCHAR, SMALLINT,
    TIMESTAMPTZ, TIMESTAMPTZ, TEXT, JSONB
) TO nokshighor_app;

COMMIT;
