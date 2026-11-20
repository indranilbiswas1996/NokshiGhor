
BEGIN;

-- 1. Dedicated read-only role
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
        WHERE rolname = 'nokshighor_sales_reference_reader'
    ) THEN
        CREATE ROLE nokshighor_sales_reference_reader
        NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
        NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public
TO nokshighor_sales_reference_reader;

GRANT CREATE ON SCHEMA public
TO nokshighor_sales_reference_reader;

-- Required read permissions
GRANT SELECT (id, status, deleted_at)
ON public.businesses
TO nokshighor_sales_reference_reader;

GRANT SELECT (business_id, user_id, status)
ON public.business_users
TO nokshighor_sales_reference_reader;

GRANT SELECT (
    id, business_id, unit_id, product_name, sku,
    selling_price, tax_rate, track_inventory,
    is_active, deleted_at
)
ON public.products
TO nokshighor_sales_reference_reader;

GRANT SELECT (
    id, unit_code, unit_name, unit_symbol,
    decimal_places, is_active
)
ON public.units
TO nokshighor_sales_reference_reader;

GRANT SELECT (business_id, unit_id)
ON public.business_unit_access
TO nokshighor_sales_reference_reader;

GRANT SELECT (
    id, business_id, party_id, deleted_at
)
ON public.customers
TO nokshighor_sales_reference_reader;

GRANT SELECT (
    id, business_id, party_name, phone,
    is_active, deleted_at
)
ON public.parties
TO nokshighor_sales_reference_reader;

GRANT SELECT (
    id, business_id, warehouse_name,
    warehouse_code, is_default, is_active, deleted_at
)
ON public.warehouses
TO nokshighor_sales_reference_reader;


-- 2. Products for New Sale
CREATE OR REPLACE FUNCTION public.fn_get_sales_products(
    p_user_id UUID,
    p_business_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_result JSONB;
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

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', p.id,
                'product_name', p.product_name,
                'sku', p.sku,
                'unit_id', u.id,
                'unit_name', u.unit_name,
                'unit_symbol', u.unit_symbol,
                'decimal_places', u.decimal_places,
                'selling_price', p.selling_price,
                'tax_rate', p.tax_rate,
                'track_inventory', p.track_inventory
            )
            ORDER BY p.product_name
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM public.products p
    JOIN public.units u
      ON u.id = p.unit_id
    JOIN public.business_unit_access bua
      ON bua.business_id = p.business_id
     AND bua.unit_id = p.unit_id
    WHERE p.business_id = p_business_id
      AND p.is_active = TRUE
      AND p.deleted_at IS NULL
      AND u.is_active = TRUE;

    RETURN v_result;
END;
$function$;


-- 3. Customers for New Sale
CREATE OR REPLACE FUNCTION public.fn_get_sales_customers(
    p_user_id UUID,
    p_business_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_result JSONB;
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

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', c.id,
                'customer_name', p.party_name,
                'phone', p.phone
            )
            ORDER BY p.party_name
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM public.customers c
    JOIN public.parties p
      ON p.business_id = c.business_id
     AND p.id = c.party_id
    WHERE c.business_id = p_business_id
      AND c.deleted_at IS NULL
      AND p.deleted_at IS NULL
      AND p.is_active = TRUE;

    RETURN v_result;
END;
$function$;


-- 4. Warehouses for New Sale
CREATE OR REPLACE FUNCTION public.fn_get_sales_warehouses(
    p_user_id UUID,
    p_business_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_result JSONB;
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

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', w.id,
                'warehouse_name', w.warehouse_name,
                'warehouse_code', w.warehouse_code,
                'is_default', w.is_default
            )
            ORDER BY w.is_default DESC, w.warehouse_name
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
$function$;


-- 5. Function ownership
ALTER FUNCTION public.fn_get_sales_products(UUID, UUID)
OWNER TO nokshighor_sales_reference_reader;

ALTER FUNCTION public.fn_get_sales_customers(UUID, UUID)
OWNER TO nokshighor_sales_reference_reader;

ALTER FUNCTION public.fn_get_sales_warehouses(UUID, UUID)
OWNER TO nokshighor_sales_reference_reader;


-- 6. Remove unnecessary schema creation privilege
REVOKE CREATE ON SCHEMA public
FROM nokshighor_sales_reference_reader;


-- 7. Restrict function execution
REVOKE ALL ON FUNCTION public.fn_get_sales_products(UUID, UUID)
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_get_sales_customers(UUID, UUID)
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_get_sales_warehouses(UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_get_sales_products(UUID, UUID)
TO nokshighor_app;

GRANT EXECUTE ON FUNCTION public.fn_get_sales_customers(UUID, UUID)
TO nokshighor_app;

GRANT EXECUTE ON FUNCTION public.fn_get_sales_warehouses(UUID, UUID)
TO nokshighor_app;

COMMIT;
