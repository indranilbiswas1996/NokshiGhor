
BEGIN;

-- Dedicated non-login role for controlled Sales Draft writes.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'nokshighor_sales_writer'
    ) THEN
        CREATE ROLE nokshighor_sales_writer
        WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
        NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO nokshighor_sales_writer;

GRANT SELECT ON
    public.businesses,
    public.business_users,
    public.customers,
    public.parties,
    public.business_settings,
    public.warehouses,
    public.products,
    public.business_unit_access
TO nokshighor_sales_writer;

GRANT INSERT ON
    public.sales,
    public.sale_items
TO nokshighor_sales_writer;

CREATE OR REPLACE FUNCTION public.fn_create_sales_draft(
    p_business_id UUID,
    p_user_id UUID,
    p_customer_id UUID,
    p_warehouse_id UUID,
    p_sale_date DATE,
    p_due_date DATE,
    p_discount_amount NUMERIC,
    p_shipping_charge NUMERIC,
    p_other_charges NUMERIC,
    p_notes TEXT,
    p_items JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_sale_id UUID;
    v_sale_number VARCHAR(80);

    v_business_name VARCHAR(200);
    v_shop_name VARCHAR(200);
    v_shop_address TEXT;
    v_shop_gstin VARCHAR(20);

    v_customer_name VARCHAR(200);
    v_customer_phone VARCHAR(20);
    v_customer_gstin VARCHAR(20);

    v_product RECORD;
    v_item JSONB;

    v_quantity NUMERIC(14,3);
    v_unit_price NUMERIC(14,2);
    v_item_discount NUMERIC(14,2);
    v_tax_rate NUMERIC(7,4);
    v_gross NUMERIC(14,2);
    v_tax NUMERIC(14,2);
    v_line_total NUMERIC(14,2);

    v_subtotal NUMERIC(14,2) := 0;
    v_items_discount NUMERIC(14,2) := 0;
    v_total_discount NUMERIC(14,2);
    v_tax_total NUMERIC(14,2) := 0;
    v_total NUMERIC(14,2);

    v_has_inventory BOOLEAN := FALSE;
    v_item_count INTEGER := 0;
BEGIN
    -- Basic request validation.
    IF p_business_id IS NULL OR p_user_id IS NULL THEN
        RAISE EXCEPTION 'Business and user are required';
    END IF;

    IF p_sale_date IS NULL
       OR (p_due_date IS NOT NULL AND p_due_date < p_sale_date) THEN
        RAISE EXCEPTION 'Invalid sale or due date';
    END IF;

    IF COALESCE(p_discount_amount, 0) < 0
       OR COALESCE(p_shipping_charge, 0) < 0
       OR COALESCE(p_other_charges, 0) < 0 THEN
        RAISE EXCEPTION 'Amounts cannot be negative';
    END IF;

    IF jsonb_typeof(p_items) <> 'array'
       OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'At least one sale item is required';
    END IF;

    IF jsonb_array_length(p_items) > 200 THEN
        RAISE EXCEPTION 'Maximum 200 sale items are allowed';
    END IF;

    -- Validate active user membership and business.
    SELECT b.business_name
    INTO v_business_name
    FROM public.business_users bu
    JOIN public.businesses b
      ON b.id = bu.business_id
    WHERE bu.business_id = p_business_id
      AND bu.user_id = p_user_id
      AND bu.status = 'active'
      AND b.status = 'active'
      AND b.deleted_at IS NULL
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User has no active access to this business';
    END IF;

    -- Shop snapshot.
    SELECT
        COALESCE(NULLIF(bs.shop_name, ''), v_business_name),
        bs.address,
        bs.gstin
    INTO
        v_shop_name,
        v_shop_address,
        v_shop_gstin
    FROM public.businesses b
    LEFT JOIN public.business_settings bs
      ON bs.business_id = b.id
    WHERE b.id = p_business_id;

    -- Customer snapshot.
    IF p_customer_id IS NULL THEN
        v_customer_name := 'Walk-in Customer';
        v_customer_phone := NULL;
        v_customer_gstin := NULL;
    ELSE
        SELECT
            p.party_name,
            p.phone,
            p.gstin
        INTO
            v_customer_name,
            v_customer_phone,
            v_customer_gstin
        FROM public.customers c
        JOIN public.parties p
          ON p.business_id = c.business_id
         AND p.id = c.party_id
        WHERE c.business_id = p_business_id
          AND c.id = p_customer_id
          AND c.deleted_at IS NULL
          AND p.deleted_at IS NULL
          AND p.is_active = TRUE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Customer is unavailable';
        END IF;
    END IF;

    -- Validate warehouse if supplied.
    IF p_warehouse_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.warehouses w
        WHERE w.business_id = p_business_id
          AND w.id = p_warehouse_id
    ) THEN
        RAISE EXCEPTION 'Invalid warehouse';
    END IF;

    -- Calculate item totals using database-owned product data.
    FOR v_item IN
        SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        v_item_count := v_item_count + 1;

        IF NULLIF(v_item->>'product_id', '') IS NULL
           OR NULLIF(v_item->>'quantity', '') IS NULL THEN
            RAISE EXCEPTION 'Product and quantity are required';
        END IF;

        v_quantity := (v_item->>'quantity')::NUMERIC;

        IF v_quantity <= 0 THEN
            RAISE EXCEPTION 'Quantity must be greater than zero';
        END IF;

        SELECT
            p.id,
            p.product_name,
            p.sku,
            p.hsn_sac_code,
            p.unit_id,
            p.purchase_price,
            p.selling_price,
            p.tax_rate,
            p.track_inventory
        INTO v_product
        FROM public.products p
        WHERE p.business_id = p_business_id
          AND p.id = (v_item->>'product_id')::UUID
          AND p.is_active = TRUE
          AND p.deleted_at IS NULL
        FOR SHARE OF p;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Product is unavailable';
        END IF;

        IF NOT EXISTS (
            SELECT 1
            FROM public.business_unit_access bua
            WHERE bua.business_id = p_business_id
              AND bua.unit_id = v_product.unit_id
        ) THEN
            RAISE EXCEPTION 'Product unit is not available to this business';
        END IF;

        IF v_product.track_inventory THEN
            v_has_inventory := TRUE;
        END IF;

        v_unit_price := COALESCE(
            NULLIF(v_item->>'unit_price', '')::NUMERIC,
            v_product.selling_price
        );

        v_item_discount := COALESCE(
            NULLIF(v_item->>'discount_amount', '')::NUMERIC,
            0
        );

        IF v_unit_price < 0 OR v_item_discount < 0 THEN
            RAISE EXCEPTION 'Price and discount cannot be negative';
        END IF;

        v_gross := ROUND(v_quantity * v_unit_price, 2);

        IF v_item_discount > v_gross THEN
            RAISE EXCEPTION 'Item discount exceeds item amount';
        END IF;

        v_tax_rate := v_product.tax_rate;

        v_tax := ROUND(
            (v_gross - v_item_discount) * v_tax_rate / 100,
            2
        );

        v_line_total := v_gross - v_item_discount + v_tax;

        v_subtotal := v_subtotal + v_gross;
        v_items_discount := v_items_discount + v_item_discount;
        v_tax_total := v_tax_total + v_tax;

    END LOOP;

    IF v_has_inventory AND p_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'Warehouse is required for inventory products';
    END IF;

    v_total_discount := COALESCE(p_discount_amount, 0)
                        + v_items_discount;

    IF v_total_discount > v_subtotal THEN
        RAISE EXCEPTION 'Total discount exceeds subtotal';
    END IF;

    v_total := ROUND(
        v_subtotal
        - v_total_discount
        + v_tax_total
        + COALESCE(p_shipping_charge, 0)
        + COALESCE(p_other_charges, 0),
        2
    );

    -- Generate a business-unique invoice number.
    v_sale_number :=
        'NG-' ||
        TO_CHAR(p_sale_date, 'YYYYMMDD') ||
        '-' ||
        UPPER(SUBSTRING(REPLACE(gen_random_uuid()::TEXT, '-', ''), 1, 8));

    -- Create draft header.
    INSERT INTO public.sales (
        business_id,
        customer_id,
        warehouse_id,
        sale_number,
        sale_date,
        due_date,
        sale_status,
        payment_status,
        subtotal,
        discount_amount,
        tax_amount,
        shipping_charge,
        other_charges,
        round_off,
        total_amount,
        paid_amount,
        notes,
        customer_name_snapshot,
        customer_phone_snapshot,
        customer_gstin_snapshot,
        shop_name_snapshot,
        shop_address_snapshot,
        shop_gstin_snapshot,
        created_by
    )
    VALUES (
        p_business_id,
        p_customer_id,
        p_warehouse_id,
        v_sale_number,
        p_sale_date,
        p_due_date,
        'draft',
        'unpaid',
        v_subtotal,
        v_total_discount,
        v_tax_total,
        COALESCE(p_shipping_charge, 0),
        COALESCE(p_other_charges, 0),
        0,
        v_total,
        0,
        p_notes,
        v_customer_name,
        v_customer_phone,
        v_customer_gstin,
        v_shop_name,
        v_shop_address,
        v_shop_gstin,
        p_user_id
    )
    RETURNING id INTO v_sale_id;

    -- Create item snapshots.
    FOR v_item IN
        SELECT value FROM jsonb_array_elements(p_items)
    LOOP
        SELECT
            p.id,
            p.product_name,
            p.sku,
            p.hsn_sac_code,
            p.unit_id,
            p.purchase_price,
            p.selling_price,
            p.tax_rate,
            p.track_inventory
        INTO v_product
        FROM public.products p
        WHERE p.business_id = p_business_id
          AND p.id = (v_item->>'product_id')::UUID
          AND p.is_active = TRUE
          AND p.deleted_at IS NULL;

        v_quantity := (v_item->>'quantity')::NUMERIC;

        v_unit_price := COALESCE(
            NULLIF(v_item->>'unit_price', '')::NUMERIC,
            v_product.selling_price
        );

        v_item_discount := COALESCE(
            NULLIF(v_item->>'discount_amount', '')::NUMERIC,
            0
        );

        v_gross := ROUND(v_quantity * v_unit_price, 2);
        v_tax_rate := v_product.tax_rate;

        v_tax := ROUND(
            (v_gross - v_item_discount) * v_tax_rate / 100,
            2
        );

        v_line_total := v_gross - v_item_discount + v_tax;

        INSERT INTO public.sale_items (
            business_id,
            sale_id,
            product_id,
            product_name_snapshot,
            sku_snapshot,
            hsn_sac_snapshot,
            track_inventory_snapshot,
            quantity,
            unit_id,
            unit_price,
            cost_price_snapshot,
            discount_amount,
            tax_rate,
            tax_amount,
            line_total,
            created_by
        )
        VALUES (
            p_business_id,
            v_sale_id,
            v_product.id,
            v_product.product_name,
            v_product.sku,
            v_product.hsn_sac_code,
            v_product.track_inventory,
            v_quantity,
            v_product.unit_id,
            v_unit_price,
            v_product.purchase_price,
            v_item_discount,
            v_tax_rate,
            v_tax,
            v_line_total,
            p_user_id
        );
    END LOOP;

    RETURN v_sale_id;
END;
$function$;

ALTER FUNCTION public.fn_create_sales_draft(
    UUID, UUID, UUID, UUID, DATE, DATE,
    NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB
) OWNER TO nokshighor_sales_writer;

REVOKE ALL ON FUNCTION public.fn_create_sales_draft(
    UUID, UUID, UUID, UUID, DATE, DATE,
    NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_create_sales_draft(
    UUID, UUID, UUID, UUID, DATE, DATE,
    NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB
) TO nokshighor_app;

COMMIT;
