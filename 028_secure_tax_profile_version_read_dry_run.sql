BEGIN;

-- 1. Allow the existing tax writer role to read only
-- the columns required for the version response.

GRANT SELECT (
    id,
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
    created_at
)
ON public.tax_profile_versions
TO nokshighor_tax_writer;

GRANT SELECT (
    business_id,
    tax_profile_version_id,
    tax_component_id,
    component_code_snapshot,
    component_name_snapshot,
    jurisdiction_snapshot,
    tax_rate,
    calculation_order
)
ON public.tax_profile_version_components
TO nokshighor_tax_writer;


-- 2. Secure function to fetch a complete version
-- including its persisted component snapshots.

CREATE OR REPLACE FUNCTION public.fn_get_tax_profile_version(
    p_user_id UUID,
    p_business_id UUID,
    p_version_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    -- Validate active business membership and tax permission.
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
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_user_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
          AND p.permission_key IN ('tax.view', 'tax.manage')
    ) THEN
        RAISE EXCEPTION 'Tax permission denied'
            USING ERRCODE = '42501';
    END IF;

    -- Fetch the requested version and its saved snapshots.
    SELECT jsonb_build_object(
        'id', v.id,
        'business_id', v.business_id,
        'tax_profile_id', v.tax_profile_id,
        'version_number', v.version_number,
        'tax_type_id', v.tax_type_id,
        'calculation_mode', v.calculation_mode,
        'rounding_mode', v.rounding_mode,
        'rounding_precision', v.rounding_precision,
        'effective_from', v.effective_from,
        'effective_to', v.effective_to,
        'version_status', v.version_status,
        'status', v.version_status,
        'version_notes', v.version_notes,
        'notes', v.version_notes,
        'created_at', v.created_at,
        'components',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'tax_component_id', c.tax_component_id,
                        'component_code_snapshot', c.component_code_snapshot,
                        'component_name_snapshot', c.component_name_snapshot,
                        'jurisdiction_snapshot', c.jurisdiction_snapshot,
                        'tax_rate', c.tax_rate,
                        'calculation_order', c.calculation_order
                    )
                    ORDER BY c.calculation_order
                )
                FROM public.tax_profile_version_components c
                WHERE c.business_id = v.business_id
                  AND c.tax_profile_version_id = v.id
            ),
            '[]'::JSONB
        )
    )
    INTO v_result
    FROM public.tax_profile_versions v
    WHERE v.id = p_version_id
      AND v.business_id = p_business_id;

    IF v_result IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN v_result;
END;
$function$;


-- 3. Secure function ownership and execution permissions.

ALTER FUNCTION public.fn_get_tax_profile_version(
    UUID, UUID, UUID
)
OWNER TO nokshighor_tax_writer;

REVOKE ALL ON FUNCTION public.fn_get_tax_profile_version(
    UUID, UUID, UUID
)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_get_tax_profile_version(
    UUID, UUID, UUID
)
TO nokshighor_app;

ROLLBACK;
