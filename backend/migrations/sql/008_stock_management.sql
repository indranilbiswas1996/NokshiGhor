-- ============================================================
-- NokshiGhor
-- Migration 008: Stock Management & Stock Ledger
-- PostgreSQL 17
--
-- Design:
--   * stock_ledger is the append-only source of truth for stock.
--   * Every movement is IN or OUT and stores a positive quantity.
--   * Corrections are made with reversing movements, not by editing
--     or deleting posted ledger rows.
--   * All business-owned references are protected by composite FKs.
--   * Stock adjustment documents are editable while draft; posting
--     and ledger generation will be handled atomically by the backend.
--
-- IMPORTANT:
--   This migration intentionally does not create stock movements for
--   existing purchases/sales. The backend posting workflow will insert
--   ledger rows in the same DB transaction as document posting.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Stock Adjustments (header)
-- ------------------------------------------------------------
CREATE TABLE stock_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,

    adjustment_number VARCHAR(50) NOT NULL,
    adjustment_date DATE NOT NULL DEFAULT CURRENT_DATE,
    adjustment_type VARCHAR(20) NOT NULL
        CHECK (adjustment_type IN ('increase', 'decrease', 'count_correction')),
    adjustment_status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (adjustment_status IN ('draft', 'posted', 'cancelled')),

    reason VARCHAR(255),
    notes TEXT,

    posted_at TIMESTAMPTZ,
    posted_by UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_stock_adjustments_business_id
        UNIQUE (business_id, id),
    CONSTRAINT uq_stock_adjustments_number
        UNIQUE (business_id, adjustment_number),

    CONSTRAINT fk_stock_adjustments_warehouse_same_business
        FOREIGN KEY (business_id, warehouse_id)
        REFERENCES warehouses (business_id, id),

    CONSTRAINT stock_adjustments_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES users (id),
    CONSTRAINT stock_adjustments_updated_by_fkey
        FOREIGN KEY (updated_by) REFERENCES users (id),
    CONSTRAINT stock_adjustments_posted_by_fkey
        FOREIGN KEY (posted_by) REFERENCES users (id),

    CONSTRAINT chk_stock_adjustments_posted_state
        CHECK (
            (adjustment_status = 'draft' AND posted_at IS NULL)
            OR
            (adjustment_status = 'cancelled' AND posted_at IS NULL)
            OR
            (adjustment_status = 'posted' AND posted_at IS NOT NULL)
        )
);

CREATE INDEX idx_stock_adjustments_business_date
    ON stock_adjustments (business_id, adjustment_date DESC);

CREATE INDEX idx_stock_adjustments_status
    ON stock_adjustments (business_id, adjustment_status);

CREATE INDEX idx_stock_adjustments_warehouse
    ON stock_adjustments (business_id, warehouse_id);


-- ------------------------------------------------------------
-- 2. Stock Adjustment Items
-- ------------------------------------------------------------
CREATE TABLE stock_adjustment_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    stock_adjustment_id UUID NOT NULL,
    product_id UUID NOT NULL,

    system_quantity NUMERIC(14,3) NOT NULL DEFAULT 0
        CHECK (system_quantity >= 0),
    counted_quantity NUMERIC(14,3) NOT NULL
        CHECK (counted_quantity >= 0),
    adjustment_quantity NUMERIC(14,3)
        GENERATED ALWAYS AS (counted_quantity - system_quantity) STORED,

    unit_id UUID NOT NULL,
    unit_cost_snapshot NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (unit_cost_snapshot >= 0),
    reason VARCHAR(255),
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_stock_adjustment_items_business_id
        UNIQUE (business_id, id),
    CONSTRAINT uq_stock_adjustment_items_business_parent_id
        UNIQUE (business_id, stock_adjustment_id, id),

    CONSTRAINT fk_stock_adjustment_items_adjustment_same_business
        FOREIGN KEY (business_id, stock_adjustment_id)
        REFERENCES stock_adjustments (business_id, id),

    CONSTRAINT fk_stock_adjustment_items_product_same_business
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id),

    CONSTRAINT stock_adjustment_items_unit_id_fkey
        FOREIGN KEY (unit_id) REFERENCES units (id),
    CONSTRAINT stock_adjustment_items_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES users (id),
    CONSTRAINT stock_adjustment_items_updated_by_fkey
        FOREIGN KEY (updated_by) REFERENCES users (id),

    CONSTRAINT chk_stock_adjustment_items_nonzero
        CHECK (counted_quantity <> system_quantity)
);

CREATE INDEX idx_stock_adjustment_items_adjustment
    ON stock_adjustment_items (business_id, stock_adjustment_id);

CREATE INDEX idx_stock_adjustment_items_product
    ON stock_adjustment_items (business_id, product_id);


-- These composite unique constraints let the ledger enforce that
-- a source line and its product belong together, in the same business.
ALTER TABLE purchase_items
    ADD CONSTRAINT uq_purchase_items_business_id_product
    UNIQUE (business_id, id, product_id);

ALTER TABLE purchase_return_items
    ADD CONSTRAINT uq_purchase_return_items_business_id_product
    UNIQUE (business_id, id, product_id);

ALTER TABLE sale_items
    ADD CONSTRAINT uq_sale_items_business_id_product
    UNIQUE (business_id, id, product_id);

ALTER TABLE stock_adjustment_items
    ADD CONSTRAINT uq_stock_adjustment_items_business_id_product
    UNIQUE (business_id, id, product_id);


-- ------------------------------------------------------------
-- 3. Stock Ledger (append-only movement history)
-- ------------------------------------------------------------
CREATE TABLE stock_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    product_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,

    movement_type VARCHAR(30) NOT NULL
        CHECK (movement_type IN (
            'purchase_in',
            'purchase_return_out',
            'sale_out',
            'sales_return_in',
            'adjustment_in',
            'adjustment_out',
            'opening_in',
            'opening_out',
            'transfer_in',
            'transfer_out',
            'reversal'
        )),
    movement_direction VARCHAR(3) NOT NULL
        CHECK (movement_direction IN ('IN', 'OUT')),
    quantity NUMERIC(14,3) NOT NULL
        CHECK (quantity > 0),

    unit_id UUID NOT NULL,
    unit_cost NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (unit_cost >= 0),
    total_cost NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (total_cost >= 0),

    -- Typed source references preserve referential integrity.
    purchase_item_id UUID,
    purchase_return_item_id UUID,
    sale_item_id UUID,
    stock_adjustment_item_id UUID,

    -- Optional link to the movement this row reverses.
    reverses_ledger_id UUID,

    movement_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,

    -- Append-only audit metadata. No updated_at/updated_by by design.
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,

    CONSTRAINT uq_stock_ledger_business_id
        UNIQUE (business_id, id),

    CONSTRAINT fk_stock_ledger_product_same_business
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id),

    CONSTRAINT fk_stock_ledger_warehouse_same_business
        FOREIGN KEY (business_id, warehouse_id)
        REFERENCES warehouses (business_id, id),

    CONSTRAINT stock_ledger_unit_id_fkey
        FOREIGN KEY (unit_id) REFERENCES units (id),

    CONSTRAINT fk_stock_ledger_purchase_item_same_business
        FOREIGN KEY (business_id, purchase_item_id, product_id)
        REFERENCES purchase_items (business_id, id, product_id),

    CONSTRAINT fk_stock_ledger_purchase_return_item_same_business
        FOREIGN KEY (business_id, purchase_return_item_id, product_id)
        REFERENCES purchase_return_items (business_id, id, product_id),

    CONSTRAINT fk_stock_ledger_sale_item_same_business
        FOREIGN KEY (business_id, sale_item_id, product_id)
        REFERENCES sale_items (business_id, id, product_id),

    CONSTRAINT fk_stock_ledger_adjustment_item_same_business
        FOREIGN KEY (business_id, stock_adjustment_item_id, product_id)
        REFERENCES stock_adjustment_items (business_id, id, product_id),

    CONSTRAINT fk_stock_ledger_reversal_same_business
        FOREIGN KEY (business_id, reverses_ledger_id)
        REFERENCES stock_ledger (business_id, id),

    CONSTRAINT stock_ledger_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES users (id),

    CONSTRAINT chk_stock_ledger_exactly_one_source
        CHECK (
            num_nonnulls(
                purchase_item_id,
                purchase_return_item_id,
                sale_item_id,
                stock_adjustment_item_id
            ) = 1
            OR
            (
                movement_type IN ('opening_in', 'opening_out', 'transfer_in', 'transfer_out', 'reversal')
                AND num_nonnulls(
                    purchase_item_id,
                    purchase_return_item_id,
                    sale_item_id,
                    stock_adjustment_item_id
                ) = 0
            )
        ),

    CONSTRAINT chk_stock_ledger_movement_direction
        CHECK (
            (movement_type IN ('purchase_in', 'sales_return_in', 'adjustment_in', 'opening_in', 'transfer_in')
                AND movement_direction = 'IN')
            OR
            (movement_type IN ('purchase_return_out', 'sale_out', 'adjustment_out', 'opening_out', 'transfer_out')
                AND movement_direction = 'OUT')
            OR movement_type = 'reversal'
        )
);

CREATE INDEX idx_stock_ledger_product_warehouse_time
    ON stock_ledger (business_id, product_id, warehouse_id, movement_at DESC);

CREATE INDEX idx_stock_ledger_warehouse_time
    ON stock_ledger (business_id, warehouse_id, movement_at DESC);

CREATE INDEX idx_stock_ledger_purchase_item
    ON stock_ledger (business_id, purchase_item_id)
    WHERE purchase_item_id IS NOT NULL;

CREATE INDEX idx_stock_ledger_purchase_return_item
    ON stock_ledger (business_id, purchase_return_item_id)
    WHERE purchase_return_item_id IS NOT NULL;

CREATE INDEX idx_stock_ledger_sale_item
    ON stock_ledger (business_id, sale_item_id)
    WHERE sale_item_id IS NOT NULL;

CREATE INDEX idx_stock_ledger_adjustment_item
    ON stock_ledger (business_id, stock_adjustment_item_id)
    WHERE stock_adjustment_item_id IS NOT NULL;

CREATE INDEX idx_stock_ledger_reversal
    ON stock_ledger (business_id, reverses_ledger_id)
    WHERE reverses_ledger_id IS NOT NULL;

COMMIT;
