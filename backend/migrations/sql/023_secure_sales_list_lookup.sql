
BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'nokshighor_sales_reader'
    ) THEN
        CREATE ROLE nokshighor_sales_reader
        NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
        NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO nokshighor_sales_reader;
GRANT CREATE ON SCHEMA public TO nokshighor_sales_reader;

GRANT SELECT (
    id,
    business_id,
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
    customer_name_snapshot,
    customer_phone_snapshot,
    shop_name_snapshot,
    created_at,
    deleted_at
)
ON public.sales TO nokshighor_sales_reader;

GRANT SELECT (
    business_id,
    user_id,
    status
)
ON public.business_users TO nokshighor_sales_reader;

GRANT SELECT (
    id,
    status,
    deleted_at
)
ON public.businesses TO nokshighor_sales_reader;


CREATE OR REPLACE FUNCTION public.fn_get_sales_list(
    p_user_id UUID,
    p_business_id UUID,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0,
    p_sale_status VARCHAR DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_result JSONB;
    v_total_count BIGINT;
    v_limit INTEGER;
    v_offset INTEGER;
BEGIN
    IF p_user_id IS NULL OR p_business_id IS NULL THEN
        RAISE EXCEPTION 'Invalid user or business';
    END IF;

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

    v_limit := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
    v_offset := GREATEST(COALESCE(p_offset, 0), 0);

    SELECT COUNT(*)
    INTO v_total_count
    FROM public.sales s
    WHERE s.business_id = p_business_id
      AND s.deleted_at IS NULL
      AND (
          p_sale_status IS NULL
          OR s.sale_status = p_sale_status
      );

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
            )
            ORDER BY x.created_at DESC, x.id DESC
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM (
        SELECT
            s.id,
            s.sale_number,
            s.sale_date,
            s.due_date,
            s.sale_status,
            s.payment_status,
            s.subtotal,
            s.discount_amount,
            s.tax_amount,
            s.shipping_charge,
            s.other_charges,
            s.round_off,
            s.total_amount,
            s.paid_amount,
            s.customer_name_snapshot,
            s.customer_phone_snapshot,
            s.shop_name_snapshot,
            s.created_at
        FROM public.sales s
        WHERE s.business_id = p_business_id
          AND s.deleted_at IS NULL
          AND (
              p_sale_status IS NULL
              OR s.sale_status = p_sale_status
          )
        ORDER BY s.created_at DESC, s.id DESC
        LIMIT v_limit
        OFFSET v_offset
    ) x;

    RETURN jsonb_build_object(
        'items', v_result,
        'total_count', v_total_count,
        'limit', v_limit,
        'offset', v_offset
    );
END;
$function$;


ALTER FUNCTION public.fn_get_sales_list(
    UUID, UUID, INTEGER, INTEGER, VARCHAR
)
OWNER TO nokshighor_sales_reader;

REVOKE CREATE ON SCHEMA public FROM nokshighor_sales_reader;

REVOKE ALL ON FUNCTION public.fn_get_sales_list(
    UUID, UUID, INTEGER, INTEGER, VARCHAR
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_get_sales_list(
    UUID, UUID, INTEGER, INTEGER, VARCHAR
) TO nokshighor_app;

COMMIT;
