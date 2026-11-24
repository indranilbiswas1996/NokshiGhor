BEGIN;

GRANT SELECT (id, business_id, branch_name, branch_code, address, phone, email, is_default, is_active, created_at, updated_at)
ON public.branches TO nokshighor_branch_manager;
GRANT SELECT (id, status, deleted_at)
ON public.businesses TO nokshighor_branch_manager;
GRANT SELECT (id, business_id, user_id, role_id, status)
ON public.business_users TO nokshighor_branch_manager;
GRANT SELECT (id, business_id, role_name)
ON public.roles TO nokshighor_branch_manager;
GRANT SELECT (business_id, branch_id, business_user_id, assignment_type, assignment_status, effective_from, effective_to)
ON public.branch_user_assignments TO nokshighor_branch_manager;
GRANT SELECT (id, business_id, branch_id, is_active, deleted_at)
ON public.warehouses TO nokshighor_branch_manager;

CREATE OR REPLACE FUNCTION public.fn_accessible_branch_list(
    p_business_id UUID,
    p_actor_user_id UUID
)
RETURNS TABLE (
    id UUID,
    branch_name VARCHAR(150),
    branch_code VARCHAR(50),
    address TEXT,
    phone VARCHAR(20),
    email VARCHAR(255),
    is_default BOOLEAN,
    is_active BOOLEAN,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b ON b.id = bu.business_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active business membership required';
    END IF;

    RETURN QUERY
    SELECT br.id, br.branch_name, br.branch_code, br.address, br.phone,
           br.email, br.is_default, br.is_active, br.created_at, br.updated_at
    FROM public.branches br
    WHERE br.business_id = p_business_id
      AND br.is_active = TRUE
      AND (
          EXISTS (
              SELECT 1
              FROM public.business_users bu
              JOIN public.roles r
                ON r.id = bu.role_id
               AND (r.business_id = bu.business_id OR r.business_id IS NULL)
              WHERE bu.business_id = p_business_id
                AND bu.user_id = p_actor_user_id
                AND bu.status = 'active'
                AND LOWER(r.role_name) = 'owner'
          )
          OR EXISTS (
              SELECT 1
              FROM public.branch_user_assignments bua
              JOIN public.business_users bu
                ON bu.id = bua.business_user_id
               AND bu.business_id = bua.business_id
              WHERE bua.business_id = p_business_id
                AND bua.branch_id = br.id
                AND bu.user_id = p_actor_user_id
                AND bu.status = 'active'
                AND bua.assignment_status = 'active'
                AND bua.effective_from <= CURRENT_TIMESTAMP
                AND (bua.effective_to IS NULL OR bua.effective_to >= CURRENT_TIMESTAMP)
          )
      )
    ORDER BY br.branch_name;
END;
$$;

ALTER FUNCTION public.fn_accessible_branch_list(UUID, UUID)
OWNER TO nokshighor_branch_manager;
REVOKE ALL ON FUNCTION public.fn_accessible_branch_list(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_accessible_branch_list(UUID, UUID) TO nokshighor_app;

CREATE OR REPLACE FUNCTION public.fn_validate_branch_context(
    p_business_id UUID,
    p_actor_user_id UUID,
    p_branch_id UUID,
    p_warehouse_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.branches br
        WHERE br.id = p_branch_id
          AND br.business_id = p_business_id
          AND br.is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Active branch not found';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r
          ON r.id = bu.role_id
         AND (r.business_id = bu.business_id OR r.business_id IS NULL)
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND LOWER(r.role_name) = 'owner'
    ) AND NOT EXISTS (
        SELECT 1
        FROM public.branch_user_assignments bua
        JOIN public.business_users bu
          ON bu.id = bua.business_user_id
         AND bu.business_id = bua.business_id
        WHERE bua.business_id = p_business_id
          AND bua.branch_id = p_branch_id
          AND bu.user_id = p_actor_user_id
          AND bu.status = 'active'
          AND bua.assignment_status = 'active'
          AND bua.effective_from <= CURRENT_TIMESTAMP
          AND (bua.effective_to IS NULL OR bua.effective_to >= CURRENT_TIMESTAMP)
    ) THEN
        RAISE EXCEPTION 'User does not have access to this branch';
    END IF;

    IF p_warehouse_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.warehouses w
        WHERE w.id = p_warehouse_id
          AND w.business_id = p_business_id
          AND w.branch_id = p_branch_id
          AND w.is_active = TRUE
          AND w.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Warehouse does not belong to the selected branch';
    END IF;

    RETURN TRUE;
END;
$$;

ALTER FUNCTION public.fn_validate_branch_context(UUID, UUID, UUID, UUID)
OWNER TO nokshighor_branch_manager;
REVOKE ALL ON FUNCTION public.fn_validate_branch_context(UUID, UUID, UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_validate_branch_context(UUID, UUID, UUID, UUID) TO nokshighor_app;
GRANT EXECUTE ON FUNCTION public.fn_validate_branch_context(UUID, UUID, UUID, UUID) TO nokshighor_sales_reader;

GRANT SELECT (business_id, warehouse_id)
ON public.sales TO nokshighor_sales_reader;
GRANT SELECT (id, business_id, branch_id)
ON public.warehouses TO nokshighor_sales_reader;

CREATE OR REPLACE FUNCTION public.fn_get_sales_list(
    p_user_id UUID,
    p_business_id UUID,
    p_limit INTEGER,
    p_offset INTEGER,
    p_sale_status VARCHAR,
    p_branch_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_items JSONB;
    v_total_count BIGINT;
    v_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
    v_offset INTEGER := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b ON b.id = bu.business_id
        WHERE bu.user_id = p_user_id
          AND bu.business_id = p_business_id
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

    SELECT COUNT(*)
    INTO v_total_count
    FROM public.sales s
    LEFT JOIN public.warehouses w
      ON w.business_id = s.business_id
     AND w.id = s.warehouse_id
    WHERE s.business_id = p_business_id
      AND s.deleted_at IS NULL
      AND (p_sale_status IS NULL OR s.sale_status = p_sale_status)
      AND (p_branch_id IS NULL OR w.branch_id = p_branch_id);

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', x.id,
                'sale_number', x.sale_number,
                'sale_date', x.sale_date,
                'due_date', x.due_date,
                'sale_status', x.sale_status,
                'payment_status', x.payment_status,
                'subtotal', x.subtotal,
                'discount_amount', x.discount_amount,
                'tax_amount', x.tax_amount,
                'shipping_charge', x.shipping_charge,
                'other_charges', x.other_charges,
                'round_off', x.round_off,
                'total_amount', x.total_amount,
                'paid_amount', x.paid_amount,
                'customer_name_snapshot', x.customer_name_snapshot,
                'customer_phone_snapshot', x.customer_phone_snapshot,
                'shop_name_snapshot', x.shop_name_snapshot,
                'created_at', x.created_at
            ) ORDER BY x.created_at DESC, x.id DESC
        ),
        '[]'::JSONB
    )
    INTO v_items
    FROM (
        SELECT s.id, s.sale_number, s.sale_date, s.due_date, s.sale_status,
               s.payment_status, s.subtotal, s.discount_amount, s.tax_amount,
               s.shipping_charge, s.other_charges, s.round_off, s.total_amount,
               s.paid_amount, s.customer_name_snapshot,
               s.customer_phone_snapshot, s.shop_name_snapshot, s.created_at
        FROM public.sales s
        LEFT JOIN public.warehouses w
          ON w.business_id = s.business_id
         AND w.id = s.warehouse_id
        WHERE s.business_id = p_business_id
          AND s.deleted_at IS NULL
          AND (p_sale_status IS NULL OR s.sale_status = p_sale_status)
          AND (p_branch_id IS NULL OR w.branch_id = p_branch_id)
        ORDER BY s.created_at DESC, s.id DESC
        LIMIT v_limit OFFSET v_offset
    ) x;

    RETURN jsonb_build_object(
        'items', v_items,
        'total_count', v_total_count,
        'limit', v_limit,
        'offset', v_offset
    );
END;
$$;

ALTER FUNCTION public.fn_get_sales_list(UUID, UUID, INTEGER, INTEGER, VARCHAR, UUID)
OWNER TO nokshighor_sales_reader;
REVOKE ALL ON FUNCTION public.fn_get_sales_list(UUID, UUID, INTEGER, INTEGER, VARCHAR, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_sales_list(UUID, UUID, INTEGER, INTEGER, VARCHAR, UUID) TO nokshighor_app;

GRANT SELECT (branch_id)
ON public.warehouses TO nokshighor_sales_reference_reader;

CREATE OR REPLACE FUNCTION public.fn_get_sales_warehouses(
    p_user_id UUID,
    p_business_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.businesses b ON b.id = bu.business_id
        WHERE bu.user_id = p_user_id
          AND bu.business_id = p_business_id
          AND bu.status = 'active'
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Active business membership required';
    END IF;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', w.id,
                'warehouse_name', w.warehouse_name,
                'warehouse_code', w.warehouse_code,
                'is_default', w.is_default,
                'branch_id', w.branch_id
            ) ORDER BY w.is_default DESC, w.warehouse_name
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM public.warehouses w
    WHERE w.business_id = p_business_id
      AND w.is_active = TRUE
      AND w.deleted_at IS NULL;

    RETURN v_result;
END;
$$;

ALTER FUNCTION public.fn_get_sales_warehouses(UUID, UUID)
OWNER TO nokshighor_sales_reference_reader;
REVOKE ALL ON FUNCTION public.fn_get_sales_warehouses(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_sales_warehouses(UUID, UUID) TO nokshighor_app;

COMMIT;