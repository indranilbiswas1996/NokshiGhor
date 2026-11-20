
BEGIN;

-- ============================================================
-- NOKSHIGHOR
-- MIGRATION 033: SECURE OPENING STOCK AND STOCK ADJUSTMENTS
-- PostgreSQL 17
--
-- Opening Stock:
--   Dedicated document + item source mapping.
--
-- Stock Adjustments:
--   Reuse existing stock_adjustments and
--   stock_adjustment_items tables.
--
-- Posting:
--   SECURITY DEFINER functions with restricted NOLOGIN roles.
-- ============================================================


-- ============================================================
-- 1. OPENING STOCK DOCUMENTS
-- ============================================================

CREATE TABLE opening_stock_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,

    opening_number VARCHAR(50) NOT NULL,
    opening_date DATE NOT NULL DEFAULT CURRENT_DATE,

    opening_status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (opening_status IN ('draft', 'posted', 'cancelled')),

    notes TEXT,

    posted_at TIMESTAMPTZ,
    posted_by UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_opening_stock_documents_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_opening_stock_documents_number
        UNIQUE (business_id, opening_number),

    CONSTRAINT fk_opening_stock_documents_warehouse
        FOREIGN KEY (business_id, warehouse_id)
        REFERENCES warehouses (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT opening_stock_documents_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES users (id),

    CONSTRAINT opening_stock_documents_updated_by_fkey
        FOREIGN KEY (updated_by) REFERENCES users (id),

    CONSTRAINT opening_stock_documents_posted_by_fkey
        FOREIGN KEY (posted_by) REFERENCES users (id),

    CONSTRAINT chk_opening_stock_documents_posted_state
        CHECK (
            (opening_status IN ('draft', 'cancelled')
                AND posted_at IS NULL)
            OR
            (opening_status = 'posted'
                AND posted_at IS NOT NULL)
        )
);

CREATE INDEX idx_opening_stock_documents_business_date
    ON opening_stock_documents (business_id, opening_date DESC);

CREATE INDEX idx_opening_stock_documents_status
    ON opening_stock_documents (business_id, opening_status);

CREATE INDEX idx_opening_stock_documents_warehouse
    ON opening_stock_documents (business_id, warehouse_id);


-- ============================================================
-- 2. OPENING STOCK ITEMS
-- ============================================================

CREATE TABLE opening_stock_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,
    opening_stock_document_id UUID NOT NULL,
    product_id UUID NOT NULL,

    quantity NUMERIC(14,3) NOT NULL
        CHECK (quantity > 0),

    unit_id UUID NOT NULL,

    unit_cost NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (unit_cost >= 0),

    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,

    CONSTRAINT uq_opening_stock_items_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_opening_stock_items_business_product
        UNIQUE (business_id, id, product_id),

    CONSTRAINT fk_opening_stock_items_document
        FOREIGN KEY (business_id, opening_stock_document_id)
        REFERENCES opening_stock_documents (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_opening_stock_items_product
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_opening_stock_items_business_unit
        FOREIGN KEY (business_id, unit_id)
        REFERENCES business_unit_access (business_id, unit_id)
        ON DELETE RESTRICT,

    CONSTRAINT opening_stock_items_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES users (id),

    CONSTRAINT opening_stock_items_updated_by_fkey
        FOREIGN KEY (updated_by) REFERENCES users (id)
);

CREATE INDEX idx_opening_stock_items_document
    ON opening_stock_items (business_id, opening_stock_document_id);

CREATE INDEX idx_opening_stock_items_product
    ON opening_stock_items (business_id, product_id);



-- ============================================================
-- 3. EXTEND STOCK LEDGER SOURCE REFERENCES
-- Preserve all existing source mappings from Migrations 009-014.
-- Preserve legacy source-less opening entries.
-- ============================================================

ALTER TABLE public.stock_ledger
    ADD COLUMN opening_stock_item_id UUID;

ALTER TABLE public.stock_ledger
    ADD CONSTRAINT fk_stock_ledger_opening_stock_item
    FOREIGN KEY (business_id, opening_stock_item_id, product_id)
    REFERENCES public.opening_stock_items (business_id, id, product_id)
    ON DELETE RESTRICT;

-- Exactly one typed source, except legacy source-less opening
-- movements and source-less reversals.

ALTER TABLE public.stock_ledger
    DROP CONSTRAINT chk_stock_ledger_exactly_one_source;

ALTER TABLE public.stock_ledger
    ADD CONSTRAINT chk_stock_ledger_exactly_one_source
    CHECK (
        num_nonnulls(
            purchase_item_id,
            purchase_return_item_id,
            sale_item_id,
            sales_return_item_id,
            stock_adjustment_item_id,
            project_material_id,
            stock_transfer_item_id,
            opening_stock_item_id
        ) = 1
        OR (
            movement_type IN ('opening_in', 'opening_out', 'reversal')
            AND num_nonnulls(
                purchase_item_id,
                purchase_return_item_id,
                sale_item_id,
                sales_return_item_id,
                stock_adjustment_item_id,
                project_material_id,
                stock_transfer_item_id,
                opening_stock_item_id
            ) = 0
        )
    );

-- Validate movement type against its correct source column.

ALTER TABLE public.stock_ledger
    DROP CONSTRAINT chk_stock_ledger_movement_source_mapping;

ALTER TABLE public.stock_ledger
    ADD CONSTRAINT chk_stock_ledger_movement_source_mapping
    CHECK (
        CASE movement_type

            WHEN 'purchase_in' THEN
                purchase_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_return_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    project_material_id, stock_transfer_item_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'purchase_return_out' THEN
                purchase_return_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    project_material_id, stock_transfer_item_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'sale_out' THEN
                sale_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    project_material_id, stock_transfer_item_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'sales_return_in' THEN
                sales_return_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, stock_adjustment_item_id,
                    project_material_id, stock_transfer_item_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'adjustment_in' THEN
                stock_adjustment_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    project_material_id, stock_transfer_item_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'adjustment_out' THEN
                stock_adjustment_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    project_material_id, stock_transfer_item_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'project_material_out' THEN
                project_material_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, stock_transfer_item_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'project_material_return_in' THEN
                project_material_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, stock_transfer_item_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'transfer_out' THEN
                stock_transfer_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, project_material_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'transfer_in' THEN
                stock_transfer_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, project_material_id,
                    opening_stock_item_id
                ) = 0

            WHEN 'opening_in' THEN
                num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, project_material_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'opening_out' THEN
                num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, project_material_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'reversal' THEN
                num_nonnulls(
                    purchase_item_id, purchase_return_item_id,
                    sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, project_material_id,
                    stock_transfer_item_id, opening_stock_item_id
                ) = 0

            ELSE FALSE
        END
    );

-- Prevent duplicate product lines in one opening document.

CREATE UNIQUE INDEX uq_opening_stock_items_document_product
    ON public.opening_stock_items (
        business_id,
        opening_stock_document_id,
        product_id
    );

CREATE INDEX idx_stock_ledger_opening_stock_item
    ON public.stock_ledger (business_id, opening_stock_item_id)
    WHERE opening_stock_item_id IS NOT NULL;


-- ============================================================
-- 4. DEDICATED SECURE POSTING ROLES
-- ============================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
        WHERE rolname = 'nokshighor_opening_stock_poster'
    ) THEN
        CREATE ROLE nokshighor_opening_stock_poster
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
            NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
        WHERE rolname = 'nokshighor_stock_adjustment_poster'
    ) THEN
        CREATE ROLE nokshighor_stock_adjustment_poster
            NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
            NOREPLICATION NOBYPASSRLS NOINHERIT;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public
TO nokshighor_opening_stock_poster,
   nokshighor_stock_adjustment_poster;


-- ============================================================
-- 5. OPENING STOCK POSTER: MINIMUM READ PERMISSIONS
-- ============================================================

GRANT SELECT (
    business_id, user_id, status
)
ON public.business_users
TO nokshighor_opening_stock_poster;

GRANT SELECT (
    id, status, deleted_at
)
ON public.businesses
TO nokshighor_opening_stock_poster;

GRANT SELECT (
    id, business_id, warehouse_id,
    opening_status, deleted_at, notes
)
ON public.opening_stock_documents
TO nokshighor_opening_stock_poster;

GRANT SELECT (
    id, business_id, opening_stock_document_id,
    product_id, quantity, unit_id, unit_cost, notes
)
ON public.opening_stock_items
TO nokshighor_opening_stock_poster;

GRANT SELECT (
    id, business_id, product_type, track_inventory,
    is_active, deleted_at, unit_id
)
ON public.products
TO nokshighor_opening_stock_poster;

GRANT SELECT (
    id, decimal_places, is_active
)
ON public.units
TO nokshighor_opening_stock_poster;

GRANT SELECT (
    business_id, product_id, warehouse_id,
    movement_type, movement_direction, quantity
)
ON public.stock_ledger
TO nokshighor_opening_stock_poster;


-- ============================================================
-- 6. OPENING STOCK POSTER: MINIMUM WRITE PERMISSIONS
-- ============================================================

GRANT INSERT (
    business_id, product_id, warehouse_id,
    movement_type, movement_direction, quantity,
    unit_id, unit_cost, total_cost,
    opening_stock_item_id, movement_at, notes, created_by
)
ON public.stock_ledger
TO nokshighor_opening_stock_poster;

GRANT UPDATE (
    opening_status, posted_at, posted_by,
    updated_at, updated_by
)
ON public.opening_stock_documents
TO nokshighor_opening_stock_poster;


-- ============================================================
-- 7. STOCK ADJUSTMENT POSTER: MINIMUM READ PERMISSIONS
-- ============================================================

GRANT SELECT (
    business_id, user_id, status
)
ON public.business_users
TO nokshighor_stock_adjustment_poster;

GRANT SELECT (
    id, status, deleted_at
)
ON public.businesses
TO nokshighor_stock_adjustment_poster;

GRANT SELECT (
    id, business_id, warehouse_id,
    adjustment_type, adjustment_status, deleted_at
)
ON public.stock_adjustments
TO nokshighor_stock_adjustment_poster;

GRANT SELECT (
    id, business_id, stock_adjustment_id,
    product_id, system_quantity, counted_quantity,
    adjustment_quantity, unit_id, unit_cost_snapshot,
    reason, notes, deleted_at
)
ON public.stock_adjustment_items
TO nokshighor_stock_adjustment_poster;

GRANT SELECT (
    id, business_id, product_type, track_inventory,
    is_active, deleted_at, unit_id
)
ON public.products
TO nokshighor_stock_adjustment_poster;

GRANT SELECT (
    id, decimal_places, is_active
)
ON public.units
TO nokshighor_stock_adjustment_poster;

GRANT SELECT (
    business_id, product_id, warehouse_id,
    movement_type, movement_direction, quantity
)
ON public.stock_ledger
TO nokshighor_stock_adjustment_poster;


-- ============================================================
-- 8. STOCK ADJUSTMENT POSTER: MINIMUM WRITE PERMISSIONS
-- ============================================================

GRANT INSERT (
    business_id, product_id, warehouse_id,
    movement_type, movement_direction, quantity,
    unit_id, unit_cost, total_cost,
    stock_adjustment_item_id, movement_at, notes, created_by
)
ON public.stock_ledger
TO nokshighor_stock_adjustment_poster;

GRANT UPDATE (
    adjustment_status, posted_at, posted_by,
    updated_at, updated_by
)
ON public.stock_adjustments
TO nokshighor_stock_adjustment_poster;


-- ============================================================
-- 9. SECURE OPENING STOCK POSTING FUNCTION
-- ============================================================

-- The opening date is needed by the posting function.
GRANT SELECT (opening_date)
ON public.opening_stock_documents
TO nokshighor_opening_stock_poster;


CREATE OR REPLACE FUNCTION public.fn_post_opening_stock(
    p_business_id UUID,
    p_user_id UUID,
    p_document_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_document RECORD;
    v_item RECORD;
    v_item_count BIGINT;
    v_has_movement BOOLEAN;
BEGIN
    IF p_business_id IS NULL
       OR p_user_id IS NULL
       OR p_document_id IS NULL THEN
        RAISE EXCEPTION 'Required identifiers cannot be null'
            USING ERRCODE = 'P0001';
    END IF;

    -- Verify active business membership.
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_user_id
          AND bu.status = 'active'
    ) THEN
        RAISE EXCEPTION 'Active business membership required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Verify business is active.
    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses b
        WHERE b.id = p_business_id
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Business is not active'
            USING ERRCODE = 'P0001';
    END IF;

    -- Lock the document to prevent duplicate posting.
    SELECT
        d.id,
        d.business_id,
        d.warehouse_id,
        d.opening_date,
        d.opening_status,
        d.deleted_at,
        d.notes
    INTO v_document
    FROM public.opening_stock_documents d
    WHERE d.id = p_document_id
      AND d.business_id = p_business_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Opening stock document not found'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_document.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Deleted opening stock document cannot be posted'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_document.opening_status <> 'draft' THEN
        RAISE EXCEPTION 'Only draft opening stock documents can be posted'
            USING ERRCODE = 'P0001';
    END IF;

    SELECT COUNT(*)
    INTO v_item_count
    FROM public.opening_stock_items i
    WHERE i.business_id = p_business_id
      AND i.opening_stock_document_id = p_document_id;

    IF v_item_count = 0 THEN
        RAISE EXCEPTION 'Opening stock document has no items'
            USING ERRCODE = 'P0001';
    END IF;

    -- Process products in deterministic order.
    FOR v_item IN
        SELECT
            i.id AS item_id,
            i.product_id,
            i.quantity,
            i.unit_id,
            i.unit_cost,
            i.notes AS item_notes,
            p.product_type,
            p.track_inventory,
            p.is_active AS product_active,
            p.deleted_at AS product_deleted_at,
            p.unit_id AS product_unit_id,
            u.decimal_places,
            u.is_active AS unit_active
        FROM public.opening_stock_items i
        JOIN public.products p
          ON p.business_id = i.business_id
         AND p.id = i.product_id
        JOIN public.units u
          ON u.id = i.unit_id
        WHERE i.business_id = p_business_id
          AND i.opening_stock_document_id = p_document_id
        ORDER BY i.product_id, i.id
    LOOP
        IF v_item.product_type <> 'goods'
           OR v_item.track_inventory IS NOT TRUE
           OR v_item.product_active IS NOT TRUE
           OR v_item.product_deleted_at IS NOT NULL THEN
            RAISE EXCEPTION 'Invalid or inactive inventory product: %',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

        IF v_item.unit_active IS NOT TRUE
           OR v_item.unit_id <> v_item.product_unit_id THEN
            RAISE EXCEPTION 'Invalid or mismatched product unit: %',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

        IF v_item.quantity <> ROUND(
            v_item.quantity,
            v_item.decimal_places
        ) THEN
            RAISE EXCEPTION 'Quantity exceeds product unit precision: %',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

        -- Use the same advisory lock convention as sale posting.
        PERFORM pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                p_business_id::TEXT || ':' ||
                v_document.warehouse_id::TEXT || ':' ||
                v_item.product_id::TEXT,
                0
            )
        );

        -- Opening stock must be the first stock movement
        -- for this product in this warehouse.
        SELECT EXISTS (
            SELECT 1
            FROM public.stock_ledger sl
            WHERE sl.business_id = p_business_id
              AND sl.warehouse_id = v_document.warehouse_id
              AND sl.product_id = v_item.product_id
        )
        INTO v_has_movement;

        IF v_has_movement THEN
            RAISE EXCEPTION
                'Opening stock is not allowed after existing stock movements for product %',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

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
            opening_stock_item_id,
            movement_at,
            notes,
            created_by
        )
        VALUES (
            p_business_id,
            v_item.product_id,
            v_document.warehouse_id,
            'opening_in',
            'IN',
            v_item.quantity,
            v_item.unit_id,
            v_item.unit_cost,
            v_item.quantity * v_item.unit_cost,
            v_item.item_id,
            v_document.opening_date::TIMESTAMP AT TIME ZONE 'UTC',
            COALESCE(v_item.item_notes, v_document.notes),
            p_user_id
        );
    END LOOP;

    -- Mark the document as posted.
    UPDATE public.opening_stock_documents
    SET
        opening_status = 'posted',
        posted_at = CURRENT_TIMESTAMP,
        posted_by = p_user_id,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_user_id
    WHERE id = p_document_id
      AND business_id = p_business_id;

END;
$function$;


-- Restrict function ownership and execution.
GRANT CREATE ON SCHEMA public
TO nokshighor_opening_stock_poster;

ALTER FUNCTION public.fn_post_opening_stock(UUID, UUID, UUID)
OWNER TO nokshighor_opening_stock_poster;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_opening_stock_poster;

REVOKE ALL
ON FUNCTION public.fn_post_opening_stock(UUID, UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.fn_post_opening_stock(UUID, UUID, UUID)
TO nokshighor_app;

-- ============================================================
-- 10. STOCK ADJUSTMENT POSTING FUNCTION
-- ============================================================

-- The function also needs the adjustment document date.
GRANT SELECT (adjustment_date)
ON public.stock_adjustments
TO nokshighor_stock_adjustment_poster;


CREATE OR REPLACE FUNCTION public.fn_post_stock_adjustment(
    p_business_id UUID,
    p_user_id UUID,
    p_adjustment_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_adjustment RECORD;
    v_item RECORD;
    v_item_count BIGINT;
    v_distinct_count BIGINT;
    v_current_quantity NUMERIC(14,3);
    v_new_quantity NUMERIC(14,3);
    v_movement_type TEXT;
    v_movement_direction TEXT;
BEGIN
    IF p_business_id IS NULL
       OR p_user_id IS NULL
       OR p_adjustment_id IS NULL THEN
        RAISE EXCEPTION 'Required identifiers cannot be null'
            USING ERRCODE = 'P0001';
    END IF;

    -- Verify active business membership.
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_user_id
          AND bu.status = 'active'
    ) THEN
        RAISE EXCEPTION 'Active business membership required'
            USING ERRCODE = 'P0001';
    END IF;

    -- Verify business is active.
    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses b
        WHERE b.id = p_business_id
          AND b.status = 'active'
          AND b.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Business is not active'
            USING ERRCODE = 'P0001';
    END IF;

    -- Lock the adjustment header.
    SELECT
        sa.id,
        sa.business_id,
        sa.warehouse_id,
        sa.adjustment_date,
        sa.adjustment_type,
        sa.adjustment_status,
        sa.deleted_at,
        sa.notes
    INTO v_adjustment
    FROM public.stock_adjustments sa
    WHERE sa.id = p_adjustment_id
      AND sa.business_id = p_business_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock adjustment not found'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_adjustment.deleted_at IS NOT NULL THEN
        RAISE EXCEPTION 'Deleted stock adjustment cannot be posted'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_adjustment.adjustment_status <> 'draft' THEN
        RAISE EXCEPTION 'Only draft stock adjustments can be posted'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_adjustment.adjustment_type NOT IN (
        'increase', 'decrease', 'count_correction'
    ) THEN
        RAISE EXCEPTION 'Invalid stock adjustment type'
            USING ERRCODE = 'P0001';
    END IF;

    -- Validate item count and duplicate products.
    SELECT
        COUNT(*),
        COUNT(DISTINCT product_id)
    INTO
        v_item_count,
        v_distinct_count
    FROM public.stock_adjustment_items i
    WHERE i.business_id = p_business_id
      AND i.stock_adjustment_id = p_adjustment_id
      AND i.deleted_at IS NULL;

    IF v_item_count = 0 THEN
        RAISE EXCEPTION 'Stock adjustment has no active items'
            USING ERRCODE = 'P0001';
    END IF;

    IF v_item_count <> v_distinct_count THEN
        RAISE EXCEPTION 'Duplicate products exist in stock adjustment'
            USING ERRCODE = 'P0001';
    END IF;

    -- Process products in deterministic order.
    FOR v_item IN
        SELECT
            i.id AS item_id,
            i.product_id,
            i.system_quantity,
            i.counted_quantity,
            i.adjustment_quantity,
            i.unit_id,
            i.unit_cost_snapshot,
            i.reason,
            i.notes AS item_notes,
            p.product_type,
            p.track_inventory,
            p.is_active AS product_active,
            p.deleted_at AS product_deleted_at,
            p.unit_id AS product_unit_id,
            u.decimal_places,
            u.is_active AS unit_active
        FROM public.stock_adjustment_items i
        JOIN public.products p
          ON p.business_id = i.business_id
         AND p.id = i.product_id
        JOIN public.units u
          ON u.id = i.unit_id
        WHERE i.business_id = p_business_id
          AND i.stock_adjustment_id = p_adjustment_id
          AND i.deleted_at IS NULL
        ORDER BY i.product_id, i.id
    LOOP
        IF v_item.product_type <> 'goods'
           OR v_item.track_inventory IS NOT TRUE
           OR v_item.product_active IS NOT TRUE
           OR v_item.product_deleted_at IS NOT NULL THEN
            RAISE EXCEPTION 'Invalid or inactive inventory product: %',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

        IF v_item.unit_active IS NOT TRUE
           OR v_item.unit_id <> v_item.product_unit_id THEN
            RAISE EXCEPTION 'Invalid or mismatched product unit: %',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

        IF v_item.counted_quantity <> ROUND(
               v_item.counted_quantity, v_item.decimal_places
           )
           OR v_item.system_quantity <> ROUND(
               v_item.system_quantity, v_item.decimal_places
           ) THEN
            RAISE EXCEPTION 'Quantity exceeds product unit precision: %',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

        IF v_item.adjustment_quantity = 0 THEN
            RAISE EXCEPTION 'Zero quantity adjustment is not allowed'
                USING ERRCODE = 'P0001';
        END IF;

        -- Validate adjustment direction.
        IF v_adjustment.adjustment_type = 'increase'
           AND v_item.adjustment_quantity < 0 THEN
            RAISE EXCEPTION 'Increase adjustment must have positive quantity'
                USING ERRCODE = 'P0001';
        END IF;

        IF v_adjustment.adjustment_type = 'decrease'
           AND v_item.adjustment_quantity > 0 THEN
            RAISE EXCEPTION 'Decrease adjustment must have negative quantity'
                USING ERRCODE = 'P0001';
        END IF;

        -- Use the same advisory lock convention as sale posting.
        PERFORM pg_catalog.pg_advisory_xact_lock(
            pg_catalog.hashtextextended(
                p_business_id::TEXT || ':' ||
                v_adjustment.warehouse_id::TEXT || ':' ||
                v_item.product_id::TEXT,
                0
            )
        );

        -- Calculate current stock from the ledger.
        SELECT COALESCE(
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
        )
        INTO v_current_quantity
        FROM public.stock_ledger sl
        WHERE sl.business_id = p_business_id
          AND sl.warehouse_id = v_adjustment.warehouse_id
          AND sl.product_id = v_item.product_id;

        -- Reject stale system quantity snapshots.
        IF v_item.system_quantity <> v_current_quantity THEN
            RAISE EXCEPTION
                'Stock changed after adjustment was created for product %. Refresh and recount.',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

        v_new_quantity :=
            v_current_quantity + v_item.adjustment_quantity;

        IF v_new_quantity < 0 THEN
            RAISE EXCEPTION
                'Adjustment would create negative stock for product %',
                v_item.product_id
                USING ERRCODE = 'P0001';
        END IF;

        IF v_item.adjustment_quantity > 0 THEN
            v_movement_type := 'adjustment_in';
            v_movement_direction := 'IN';
        ELSE
            v_movement_type := 'adjustment_out';
            v_movement_direction := 'OUT';
        END IF;

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
            stock_adjustment_item_id,
            movement_at,
            notes,
            created_by
        )
        VALUES (
            p_business_id,
            v_item.product_id,
            v_adjustment.warehouse_id,
            v_movement_type,
            v_movement_direction,
            ABS(v_item.adjustment_quantity),
            v_item.unit_id,
            COALESCE(v_item.unit_cost_snapshot, 0),
            ABS(v_item.adjustment_quantity)
                * COALESCE(v_item.unit_cost_snapshot, 0),
            v_item.item_id,
            v_adjustment.adjustment_date::TIMESTAMP
                AT TIME ZONE 'UTC',
            COALESCE(
                v_item.reason,
                v_item.item_notes,
                v_adjustment.notes
            ),
            p_user_id
        );
    END LOOP;

    -- Mark adjustment as posted.
    UPDATE public.stock_adjustments
    SET
        adjustment_status = 'posted',
        posted_at = CURRENT_TIMESTAMP,
        posted_by = p_user_id,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_user_id
    WHERE id = p_adjustment_id
      AND business_id = p_business_id;

END;
$function$;


-- Restrict function ownership and execution.
-- Restrict function ownership and execution.
GRANT CREATE ON SCHEMA public
TO nokshighor_stock_adjustment_poster;

ALTER FUNCTION public.fn_post_stock_adjustment(UUID, UUID, UUID)
OWNER TO nokshighor_stock_adjustment_poster;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_stock_adjustment_poster;

REVOKE ALL
ON FUNCTION public.fn_post_stock_adjustment(UUID, UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.fn_post_stock_adjustment(UUID, UUID, UUID)
TO nokshighor_app;

-- ============================================================
-- 11. FUNCTION DOCUMENTATION
-- ============================================================

COMMENT ON FUNCTION public.fn_post_opening_stock(UUID, UUID, UUID)
IS 'Securely posts an opening stock document into the append-only stock ledger.';

COMMENT ON FUNCTION public.fn_post_stock_adjustment(UUID, UUID, UUID)
IS 'Securely posts stock adjustments into the append-only stock ledger after validating current stock balances.';


-- ============================================================
-- 12. COMMIT MIGRATION
-- ============================================================

COMMIT;
