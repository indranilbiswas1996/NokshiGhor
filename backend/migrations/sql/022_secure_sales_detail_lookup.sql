
BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'nokshighor_sales_reader'
    ) THEN
        CREATE ROLE nokshighor_sales_reader
        WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
        NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO nokshighor_sales_reader;
GRANT CREATE ON SCHEMA public TO nokshighor_sales_reader;

GRANT SELECT (
    id, business_id, sale_number, sale_date, due_date,
    sale_status, payment_status, subtotal, discount_amount,
    tax_amount, shipping_charge, other_charges, round_off,
    total_amount, paid_amount, notes,
    customer_name_snapshot, customer_phone_snapshot,
    customer_gstin_snapshot, shop_name_snapshot,
    shop_address_snapshot, shop_gstin_snapshot,
    posted_at, created_at, deleted_at
)
ON public.sales TO nokshighor_sales_reader;

GRANT SELECT (
    id, business_id, sale_id, product_id,
    product_name_snapshot, sku_snapshot, hsn_sac_snapshot,
    track_inventory_snapshot, quantity, unit_id, unit_price,
    cost_price_snapshot, discount_amount, tax_rate,
    tax_amount, line_total
)
ON public.sale_items TO nokshighor_sales_reader;

GRANT SELECT ON public.business_users, public.businesses
TO nokshighor_sales_reader;

CREATE OR REPLACE FUNCTION public.fn_get_sale_details(
    p_user_id UUID,
    p_business_id UUID,
    p_sale_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_result JSONB;
BEGIN
    IF p_user_id IS NULL
       OR p_business_id IS NULL
       OR p_sale_id IS NULL THEN
        RAISE EXCEPTION 'User, business and sale are required';
    END IF;

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
        RAISE EXCEPTION 'User has no active access to this business';
    END IF;

    SELECT jsonb_build_object(
        'id', s.id,
        'sale_number', s.sale_number,
        'sale_date', s.sale_date,
        'due_date', s.due_date,
        'sale_status', s.sale_status,
        'payment_status', s.payment_status,
        'subtotal', s.subtotal,
        'discount_amount', s.discount_amount,
        'tax_amount', s.tax_amount,
        'shipping_charge', s.shipping_charge,
        'other_charges', s.other_charges,
        'round_off', s.round_off,
        'total_amount', s.total_amount,
        'paid_amount', s.paid_amount,
        'notes', s.notes,
        'customer_name_snapshot', s.customer_name_snapshot,
        'customer_phone_snapshot', s.customer_phone_snapshot,
        'customer_gstin_snapshot', s.customer_gstin_snapshot,
        'shop_name_snapshot', s.shop_name_snapshot,
        'shop_address_snapshot', s.shop_address_snapshot,
        'shop_gstin_snapshot', s.shop_gstin_snapshot,
        'posted_at', s.posted_at,
        'created_at', s.created_at,
        'items', COALESCE((
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id', si.id,
                    'product_id', si.product_id,
                    'product_name_snapshot', si.product_name_snapshot,
                    'sku_snapshot', si.sku_snapshot,
                    'hsn_sac_snapshot', si.hsn_sac_snapshot,
                    'track_inventory_snapshot', si.track_inventory_snapshot,
                    'quantity', si.quantity,
                    'unit_id', si.unit_id,
                    'unit_price', si.unit_price,
                    'discount_amount', si.discount_amount,
                    'tax_rate', si.tax_rate,
                    'tax_amount', si.tax_amount,
                    'line_total', si.line_total
                )
                ORDER BY si.created_at, si.id
            )
            FROM public.sale_items si
            WHERE si.business_id = s.business_id
              AND si.sale_id = s.id
              AND si.deleted_at IS NULL
        ), '[]'::JSONB)
    )
    INTO v_result
    FROM public.sales s
    WHERE s.id = p_sale_id
      AND s.business_id = p_business_id
      AND s.deleted_at IS NULL;

    RETURN v_result;
END;
$function$;

ALTER FUNCTION public.fn_get_sale_details(UUID, UUID, UUID)
OWNER TO nokshighor_sales_reader;

REVOKE CREATE ON SCHEMA public FROM nokshighor_sales_reader;

REVOKE ALL ON FUNCTION public.fn_get_sale_details(UUID, UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_get_sale_details(UUID, UUID, UUID)
TO nokshighor_app;

COMMIT;
