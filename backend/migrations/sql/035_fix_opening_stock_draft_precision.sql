
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_create_opening_stock_draft(
    p_business_id UUID,
    p_user_id UUID,
    p_warehouse_id UUID,
    p_opening_date DATE,
    p_notes TEXT,
    p_items JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_document_id UUID;
    v_opening_number VARCHAR(50);

    v_item JSONB;
    v_product RECORD;

    v_product_id UUID;
    v_quantity NUMERIC;
    v_unit_cost NUMERIC;

    v_item_count INTEGER := 0;
    v_distinct_count INTEGER := 0;
BEGIN
    IF p_business_id IS NULL
       OR p_user_id IS NULL
       OR p_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'Business, user and warehouse are required';
    END IF;

    IF p_opening_date IS NULL THEN
        RAISE EXCEPTION 'Opening date is required';
    END IF;

    IF p_opening_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'Opening date cannot be in the future';
    END IF;

    IF jsonb_typeof(p_items) IS DISTINCT FROM 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'At least one opening stock item is required';
    END IF;

    IF jsonb_array_length(p_items) > 500 THEN
        RAISE EXCEPTION 'Maximum 500 opening stock items are allowed';
    END IF;

    PERFORM 1
    FROM public.business_users bu
    JOIN public.businesses b
      ON b.id = bu.business_id
    WHERE bu.business_id = p_business_id
      AND bu.user_id = p_user_id
      AND bu.status = 'active'
      AND b.status = 'active'
      AND b.deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User has no active access to this business';
    END IF;

    PERFORM 1
    FROM public.warehouses w
    WHERE w.business_id = p_business_id
      AND w.id = p_warehouse_id
      AND w.deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Warehouse is unavailable';
    END IF;

    SELECT
        COUNT(*)::INTEGER,
        COUNT(DISTINCT NULLIF(value->>'product_id', '')::UUID)::INTEGER
    INTO
        v_item_count,
        v_distinct_count
    FROM jsonb_array_elements(p_items);

    IF v_item_count <> v_distinct_count THEN
        RAISE EXCEPTION 'Duplicate products are not allowed';
    END IF;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(p_items)
    LOOP
        IF NULLIF(v_item->>'product_id', '') IS NULL
           OR NULLIF(v_item->>'quantity', '') IS NULL THEN
            RAISE EXCEPTION 'Product and quantity are required';
        END IF;

        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::NUMERIC;
        v_unit_cost := COALESCE(
            NULLIF(v_item->>'unit_cost', '')::NUMERIC,
            0
        );

        IF v_quantity <= 0 THEN
            RAISE EXCEPTION 'Quantity must be greater than zero';
        END IF;

        IF v_unit_cost < 0 THEN
            RAISE EXCEPTION 'Unit cost cannot be negative';
        END IF;

        IF v_unit_cost <> ROUND(v_unit_cost, 2) THEN
            RAISE EXCEPTION 'Unit cost supports maximum 2 decimal places';
        END IF;

        SELECT
            p.id,
            p.unit_id,
            p.product_type,
            p.track_inventory,
            p.is_active,
            p.deleted_at,
            u.is_active AS unit_is_active,
            u.decimal_places
        INTO v_product
        FROM public.products p
        JOIN public.units u
          ON u.id = p.unit_id
        JOIN public.business_unit_access bua
          ON bua.business_id = p.business_id
         AND bua.unit_id = p.unit_id
        WHERE p.business_id = p_business_id
          AND p.id = v_product_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product or its unit is unavailable';
        END IF;

        IF v_quantity <> ROUND(
            v_quantity,
            v_product.decimal_places
        ) THEN
            RAISE EXCEPTION 'Quantity exceeds product unit precision: %',
                v_product_id
                USING ERRCODE = 'P0001';
        END IF;

        IF v_product.product_type <> 'goods'
           OR v_product.track_inventory IS NOT TRUE
           OR v_product.is_active IS NOT TRUE
           OR v_product.deleted_at IS NOT NULL
           OR v_product.unit_is_active IS NOT TRUE THEN
            RAISE EXCEPTION 'Product is not eligible for opening stock';
        END IF;
    END LOOP;

    v_opening_number :=
        'OS-' ||
        TO_CHAR(p_opening_date, 'YYYYMMDD') ||
        '-' ||
        UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', ''), 1, 8));

    INSERT INTO public.opening_stock_documents (
        business_id,
        warehouse_id,
        opening_number,
        opening_date,
        opening_status,
        notes,
        created_by,
        updated_by
    )
    VALUES (
        p_business_id,
        p_warehouse_id,
        v_opening_number,
        p_opening_date,
        'draft',
        p_notes,
        p_user_id,
        p_user_id
    )
    RETURNING id INTO v_document_id;

    FOR v_item IN
        SELECT value
        FROM jsonb_array_elements(p_items)
    LOOP
        v_product_id := (v_item->>'product_id')::UUID;
        v_quantity := (v_item->>'quantity')::NUMERIC;
        v_unit_cost := COALESCE(
            NULLIF(v_item->>'unit_cost', '')::NUMERIC,
            0
        );

        SELECT p.unit_id
        INTO v_product
        FROM public.products p
        WHERE p.business_id = p_business_id
          AND p.id = v_product_id;

        INSERT INTO public.opening_stock_items (
            business_id,
            opening_stock_document_id,
            product_id,
            quantity,
            unit_id,
            unit_cost,
            notes,
            created_by,
            updated_by
        )
        VALUES (
            p_business_id,
            v_document_id,
            v_product_id,
            v_quantity,
            v_product.unit_id,
            v_unit_cost,
            NULLIF(v_item->>'notes', ''),
            p_user_id,
            p_user_id
        );
    END LOOP;

    RETURN v_document_id;
END;
$function$;

GRANT CREATE ON SCHEMA public
TO nokshighor_opening_stock_writer;

ALTER FUNCTION public.fn_create_opening_stock_draft(
    UUID, UUID, UUID, DATE, TEXT, JSONB
)
OWNER TO nokshighor_opening_stock_writer;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_opening_stock_writer;

REVOKE ALL ON FUNCTION public.fn_create_opening_stock_draft(
    UUID, UUID, UUID, DATE, TEXT, JSONB
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_create_opening_stock_draft(
    UUID, UUID, UUID, DATE, TEXT, JSONB
) TO nokshighor_app;

COMMIT;
