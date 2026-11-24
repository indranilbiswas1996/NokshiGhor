BEGIN;

GRANT SELECT (id, business_id, warehouse_id, deleted_at)
ON public.sales TO nokshighor_branch_manager;
GRANT SELECT (id, business_id, warehouse_id, deleted_at)
ON public.opening_stock_documents TO nokshighor_branch_manager;
GRANT SELECT (id, business_id, branch_id)
ON public.warehouses TO nokshighor_opening_stock_reader;
GRANT EXECUTE ON FUNCTION public.fn_validate_branch_context(UUID, UUID, UUID, UUID)
TO nokshighor_opening_stock_reader;

CREATE OR REPLACE FUNCTION public.fn_validate_sale_branch(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_branch_id UUID,
    p_sale_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_warehouse_id UUID;
BEGIN
    SELECT s.warehouse_id
    INTO v_warehouse_id
    FROM public.sales s
    WHERE s.id = p_sale_id
      AND s.business_id = p_business_id
      AND s.deleted_at IS NULL;

    IF NOT FOUND OR v_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'Sale not found in the selected branch';
    END IF;

    PERFORM public.fn_validate_branch_context(
        p_business_id, p_actor_user_id, p_branch_id, v_warehouse_id
    );

    RETURN TRUE;
END;
$$;

ALTER FUNCTION public.fn_validate_sale_branch(UUID, UUID, UUID, UUID)
OWNER TO nokshighor_branch_manager;
REVOKE ALL ON FUNCTION public.fn_validate_sale_branch(UUID, UUID, UUID, UUID)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_validate_sale_branch(UUID, UUID, UUID, UUID)
TO nokshighor_app;

GRANT SELECT (business_id, id, branch_id)
ON public.warehouses TO nokshighor_opening_stock_reader;

CREATE OR REPLACE FUNCTION public.fn_validate_opening_stock_branch(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_branch_id UUID,
    p_document_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_warehouse_id UUID;
BEGIN
    SELECT d.warehouse_id
    INTO v_warehouse_id
    FROM public.opening_stock_documents d
    WHERE d.id = p_document_id
      AND d.business_id = p_business_id
      AND d.deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Opening stock document not found in the selected branch';
    END IF;

    PERFORM public.fn_validate_branch_context(
        p_business_id, p_actor_user_id, p_branch_id, v_warehouse_id
    );

    RETURN TRUE;
END;
$$;

ALTER FUNCTION public.fn_validate_opening_stock_branch(UUID, UUID, UUID, UUID)
OWNER TO nokshighor_branch_manager;
REVOKE ALL ON FUNCTION public.fn_validate_opening_stock_branch(UUID, UUID, UUID, UUID)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_validate_opening_stock_branch(UUID, UUID, UUID, UUID)
TO nokshighor_app;

CREATE OR REPLACE FUNCTION public.fn_list_opening_stock_drafts(
    p_business_id UUID,
    p_user_id UUID,
    p_branch_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF p_business_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'Business and user are required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b ON b.id = bu.business_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_user_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active business membership required';
    END IF;

    IF p_branch_id IS NOT NULL THEN
        PERFORM public.fn_validate_branch_context(
            p_business_id, p_user_id, p_branch_id, NULL
        );
    END IF;

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
                            ) ORDER BY i.product_id
                        )
                        FROM public.opening_stock_items i
                        WHERE i.business_id = d.business_id
                          AND i.opening_stock_document_id = d.id
                    ),
                    '[]'::JSONB
                )
            ) ORDER BY d.created_at DESC
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM public.opening_stock_documents d
    JOIN public.warehouses w
      ON w.business_id = d.business_id
     AND w.id = d.warehouse_id
    WHERE d.business_id = p_business_id
      AND d.opening_status = 'draft'
      AND d.deleted_at IS NULL
      AND (p_branch_id IS NULL OR w.branch_id = p_branch_id);

    RETURN v_result;
END;
$$;

ALTER FUNCTION public.fn_list_opening_stock_drafts(UUID, UUID, UUID)
OWNER TO nokshighor_opening_stock_reader;
REVOKE ALL ON FUNCTION public.fn_list_opening_stock_drafts(UUID, UUID, UUID)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_list_opening_stock_drafts(UUID, UUID, UUID)
TO nokshighor_app;

COMMIT;