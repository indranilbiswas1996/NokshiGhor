
BEGIN;

-- ============================================================
-- NOKSHIGHOR
-- MIGRATION 038: SECURE OPENING STOCK DRAFT LIST
-- PostgreSQL 17
-- ============================================================

-- 1. Dedicated read-only role

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'nokshighor_opening_stock_reader'
    ) THEN
        CREATE ROLE nokshighor_opening_stock_reader
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
            NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public
TO nokshighor_opening_stock_reader;

-- 2. Minimum read permissions

GRANT SELECT (
    business_id, user_id, status
)
ON public.business_users
TO nokshighor_opening_stock_reader;

GRANT SELECT (
    id, status, deleted_at
)
ON public.businesses
TO nokshighor_opening_stock_reader;

GRANT SELECT (
    id,
    business_id,
    warehouse_id,
    opening_number,
    opening_date,
    opening_status,
    notes,
    created_at,
    updated_at,
    deleted_at
)
ON public.opening_stock_documents
TO nokshighor_opening_stock_reader;

GRANT SELECT (
    business_id,
    opening_stock_document_id,
    product_id,
    quantity,
    unit_id,
    unit_cost,
    notes
)
ON public.opening_stock_items
TO nokshighor_opening_stock_reader;


-- 3. Secure draft list function

CREATE OR REPLACE FUNCTION public.fn_list_opening_stock_drafts(
    p_business_id UUID,
    p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_result JSONB;
BEGIN

    IF p_business_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'Business and user are required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Verify active membership and business.

    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b
          ON b.id = bu.business_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_user_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active business membership required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Return only active draft documents belonging
    -- to the selected business.

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'document_id', d.id,
                'warehouse_id', d.warehouse_id,
                'opening_number', d.opening_number,
                'opening_date', d.opening_date,
                'opening_status', d.opening_status,
                'notes', d.notes,
                'created_at', d.created_at,
                'updated_at', d.updated_at,
                'items', COALESCE(
                    (
                        SELECT jsonb_agg(
                            jsonb_build_object(
                                'product_id', i.product_id,
                                'quantity', i.quantity,
                                'unit_id', i.unit_id,
                                'unit_cost', i.unit_cost,
                                'notes', i.notes
                            )
                            ORDER BY i.product_id
                        )
                        FROM public.opening_stock_items i
                        WHERE i.business_id = d.business_id
                          AND i.opening_stock_document_id = d.id
                    ),
                    '[]'::JSONB
                )
            )
            ORDER BY d.created_at DESC
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM public.opening_stock_documents d
    WHERE d.business_id = p_business_id
      AND d.opening_status = 'draft'
      AND d.deleted_at IS NULL;

    RETURN v_result;

END;
$function$;


-- 4. Function ownership and execution permissions

GRANT CREATE ON SCHEMA public
TO nokshighor_opening_stock_reader;

ALTER FUNCTION public.fn_list_opening_stock_drafts(UUID, UUID)
OWNER TO nokshighor_opening_stock_reader;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_opening_stock_reader;

REVOKE ALL
ON FUNCTION public.fn_list_opening_stock_drafts(UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.fn_list_opening_stock_drafts(UUID, UUID)
TO nokshighor_app;

COMMENT ON FUNCTION public.fn_list_opening_stock_drafts(UUID, UUID)
IS 'Returns active opening stock drafts and their items for an authenticated active business member.';

COMMIT;
