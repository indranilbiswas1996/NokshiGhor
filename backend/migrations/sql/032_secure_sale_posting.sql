
-- ============================================================
-- Migration 032: Secure Sale Posting
-- Purpose:
--   1. Validate active business membership.
--   2. Lock draft sale against concurrent posting.
--   3. Lock inventory keys to prevent concurrent overselling.
--   4. Validate stock from stock_ledger.
--   5. Insert immutable sale_out ledger entries.
--   6. Mark the sale as posted.
--
-- All operations execute atomically within one transaction.
-- Apply only after migrations 001-031.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Dedicated function execution role
-- ------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'nokshighor_sale_poster'
    ) THEN
        CREATE ROLE nokshighor_sale_poster
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO nokshighor_sale_poster;

-- ------------------------------------------------------------
-- 2. Minimum required read permissions
-- ------------------------------------------------------------

GRANT SELECT (business_id, user_id, status)
    ON public.business_users
    TO nokshighor_sale_poster;

GRANT SELECT (id, status, deleted_at)
    ON public.businesses
    TO nokshighor_sale_poster;

GRANT SELECT (
    id,
    business_id,
    sale_number,
    sale_status,
    warehouse_id,
    deleted_at
)
    ON public.sales
    TO nokshighor_sale_poster;

GRANT SELECT (
    id,
    business_id,
    sale_id,
    product_id,
    track_inventory_snapshot,
    quantity,
    unit_id,
    cost_price_snapshot,
    deleted_at
)
    ON public.sale_items
    TO nokshighor_sale_poster;

GRANT SELECT (
    business_id,
    product_id,
    warehouse_id,
    movement_direction,
    quantity
)
    ON public.stock_ledger
    TO nokshighor_sale_poster;

-- ------------------------------------------------------------
-- 3. Minimum required write permissions
-- ------------------------------------------------------------

GRANT INSERT (
    business_id,
    product_id,
    warehouse_id,
    movement_type,
    movement_direction,
    quantity,
    unit_id,
    unit_cost,
    total_cost,
    sale_item_id,
    movement_at,
    notes,
    created_by
)
    ON public.stock_ledger
    TO nokshighor_sale_poster;

GRANT UPDATE (
    sale_status,
    posted_at,
    posted_by,
    updated_at,
    updated_by
)
    ON public.sales
    TO nokshighor_sale_poster;

-- ------------------------------------------------------------
-- 4. Secure posting function
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_post_sale(
    p_business_id UUID,
    p_user_id UUID,
    p_sale_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_sale_status VARCHAR(30);
    v_sale_number VARCHAR(80);
    v_warehouse_id UUID;
    v_item_count INTEGER;
    v_inventory_item_count INTEGER;

    v_product_id UUID;
    v_required_quantity NUMERIC(14,3);
    v_available_quantity NUMERIC(14,3);

    v_item RECORD;
    v_stock_check RECORD;
BEGIN
    -- --------------------------------------------------------
    -- A. Basic input validation
    -- --------------------------------------------------------

    IF p_business_id IS NULL
       OR p_user_id IS NULL
       OR p_sale_id IS NULL THEN
        RAISE EXCEPTION 'Business, user and sale are required';
    END IF;

    -- --------------------------------------------------------
    -- B. Validate active membership and business
    -- Same membership rule as Migration 021.
    -- --------------------------------------------------------

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
        RAISE EXCEPTION 'Active business membership required';
    END IF;

    -- --------------------------------------------------------
    -- C. Lock sale header
    -- Prevents two requests posting the same sale concurrently.
    -- --------------------------------------------------------

    SELECT
        s.sale_status,
        s.sale_number,
        s.warehouse_id
    INTO
        v_sale_status,
        v_sale_number,
        v_warehouse_id
    FROM public.sales s
    WHERE s.business_id = p_business_id
      AND s.id = p_sale_id
      AND s.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale not found';
    END IF;

    IF v_sale_status <> 'draft' THEN
        RAISE EXCEPTION 'Only draft sales can be posted';
    END IF;

    -- --------------------------------------------------------
    -- D. Validate sale items
    -- --------------------------------------------------------

    SELECT
        COUNT(*),
        COUNT(*) FILTER (
            WHERE track_inventory_snapshot = TRUE
        )
    INTO
        v_item_count,
        v_inventory_item_count
    FROM public.sale_items
    WHERE business_id = p_business_id
      AND sale_id = p_sale_id
      AND deleted_at IS NULL;

    IF v_item_count = 0 THEN
        RAISE EXCEPTION 'Cannot post a sale without items';
    END IF;

    IF v_inventory_item_count > 0
       AND v_warehouse_id IS NULL THEN
        RAISE EXCEPTION
            'A warehouse is required for inventory-tracked products';
    END IF;

    -- --------------------------------------------------------
    -- E. Acquire deterministic inventory locks
    --
    -- All inventory products are locked in UUID order.
    -- Other stock-posting workflows should follow the same
    -- advisory-lock convention.
    -- --------------------------------------------------------

    IF v_inventory_item_count > 0 THEN

        FOR v_product_id IN
            SELECT DISTINCT si.product_id
            FROM public.sale_items si
            WHERE si.business_id = p_business_id
              AND si.sale_id = p_sale_id
              AND si.deleted_at IS NULL
              AND si.track_inventory_snapshot = TRUE
            ORDER BY si.product_id
        LOOP
            PERFORM pg_catalog.pg_advisory_xact_lock(
                pg_catalog.hashtextextended(
                    p_business_id::TEXT
                    || ':'
                    || v_warehouse_id::TEXT
                    || ':'
                    || v_product_id::TEXT,
                    0
                )
            );
        END LOOP;

        -- ----------------------------------------------------
        -- F. Check stock availability per product
        -- Aggregates duplicate product lines in the same sale.
        -- ----------------------------------------------------

        FOR v_stock_check IN
            SELECT
                si.product_id,
                SUM(si.quantity)::NUMERIC(14,3)
                    AS required_quantity
            FROM public.sale_items si
            WHERE si.business_id = p_business_id
              AND si.sale_id = p_sale_id
              AND si.deleted_at IS NULL
              AND si.track_inventory_snapshot = TRUE
            GROUP BY si.product_id
            ORDER BY si.product_id
        LOOP
            SELECT
                COALESCE(
                    SUM(
                        CASE
                            WHEN sl.movement_direction = 'IN'
                                THEN sl.quantity
                            WHEN sl.movement_direction = 'OUT'
                                THEN -sl.quantity
                            ELSE 0
                        END
                    ),
                    0
                )::NUMERIC(14,3)
            INTO v_available_quantity
            FROM public.stock_ledger sl
            WHERE sl.business_id = p_business_id
              AND sl.product_id = v_stock_check.product_id
              AND sl.warehouse_id = v_warehouse_id;

            IF v_available_quantity
               < v_stock_check.required_quantity THEN

                RAISE EXCEPTION
                    'Insufficient stock for product %. Available: %, Required: %',
                    v_stock_check.product_id,
                    v_available_quantity,
                    v_stock_check.required_quantity;
            END IF;
        END LOOP;

        -- ----------------------------------------------------
        -- G. Insert stock ledger OUT entries
        -- One entry per inventory-tracked sale item.
        -- ----------------------------------------------------

        FOR v_item IN
            SELECT
                si.id,
                si.product_id,
                si.quantity,
                si.unit_id,
                si.cost_price_snapshot
            FROM public.sale_items si
            WHERE si.business_id = p_business_id
              AND si.sale_id = p_sale_id
              AND si.deleted_at IS NULL
              AND si.track_inventory_snapshot = TRUE
            ORDER BY si.product_id, si.id
        LOOP
            INSERT INTO public.stock_ledger (
                business_id,
                product_id,
                warehouse_id,
                movement_type,
                movement_direction,
                quantity,
                unit_id,
                unit_cost,
                total_cost,
                sale_item_id,
                movement_at,
                notes,
                created_by
            )
            VALUES (
                p_business_id,
                v_item.product_id,
                v_warehouse_id,
                'sale_out',
                'OUT',
                v_item.quantity,
                v_item.unit_id,
                COALESCE(v_item.cost_price_snapshot, 0),
                ROUND(
                    v_item.quantity
                    * COALESCE(v_item.cost_price_snapshot, 0),
                    2
                ),
                v_item.id,
                CURRENT_TIMESTAMP,
                'Sale posting: ' || v_sale_number,
                p_user_id
            );
        END LOOP;
    END IF;

    -- --------------------------------------------------------
    -- H. Mark sale as posted
    -- --------------------------------------------------------

    UPDATE public.sales
    SET
        sale_status = 'posted',
        posted_at = CURRENT_TIMESTAMP,
        posted_by = p_user_id,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_user_id
    WHERE business_id = p_business_id
      AND id = p_sale_id
      AND sale_status = 'draft';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Sale posting status update failed';
    END IF;

    RETURN p_sale_id;
END;
$function$;

-- ------------------------------------------------------------
-- 5. Function ownership and execution permissions
-- ------------------------------------------------------------

ALTER FUNCTION public.fn_post_sale(UUID, UUID, UUID)
    OWNER TO nokshighor_sale_poster;

REVOKE ALL
    ON FUNCTION public.fn_post_sale(UUID, UUID, UUID)
    FROM PUBLIC;

GRANT EXECUTE
    ON FUNCTION public.fn_post_sale(UUID, UUID, UUID)
    TO nokshighor_app;

COMMIT;

-- ============================================================
-- End Migration 032
-- ============================================================
