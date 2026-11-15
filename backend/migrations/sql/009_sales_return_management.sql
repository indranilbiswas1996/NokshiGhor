-- ============================================================
-- NokshiGhor
-- Migration 009: Sales Return Management
-- PostgreSQL 17
--
-- Design:
--   * A return is always linked to an original posted sale.
--   * Return items must refer to the exact original sale item
--     and product within the same business.
--   * Returned quantities cannot exceed sold quantities. This
--     cumulative rule must be checked transactionally by backend
--     logic while locking the original sale item.
--   * Posted returns create stock_ledger sales_return_in rows
--     in the same database transaction.
--   * stock_ledger remains append-only.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Sales Returns (header)
-- ------------------------------------------------------------
CREATE TABLE sales_returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    sale_id UUID NOT NULL,

    return_number VARCHAR(50) NOT NULL,
    return_date DATE NOT NULL DEFAULT CURRENT_DATE,
    return_status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (return_status IN ('draft', 'posted', 'cancelled')),

    subtotal NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    discount_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    total_amount NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),

    refund_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (refund_status IN ('pending', 'partially_refunded', 'refunded', 'credit_note')),
    refunded_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (refunded_amount >= 0 AND refunded_amount <= total_amount),

    reason VARCHAR(255),
    notes TEXT,

    -- Preserve customer details as they appeared on the return.
    customer_name_snapshot VARCHAR(200),
    customer_phone_snapshot VARCHAR(20),

    posted_at TIMESTAMPTZ,
    posted_by UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_sales_returns_business_id
        UNIQUE (business_id, id),
    CONSTRAINT uq_sales_returns_business_sale
        UNIQUE (business_id, id, sale_id),
    CONSTRAINT uq_sales_returns_number
        UNIQUE (business_id, return_number),

    CONSTRAINT fk_sales_returns_sale_same_business
        FOREIGN KEY (business_id, sale_id)
        REFERENCES sales (business_id, id),

    CONSTRAINT sales_returns_posted_by_fkey
        FOREIGN KEY (posted_by) REFERENCES users (id),
    CONSTRAINT sales_returns_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES users (id),
    CONSTRAINT sales_returns_updated_by_fkey
        FOREIGN KEY (updated_by) REFERENCES users (id),

    CONSTRAINT chk_sales_returns_posted_state
        CHECK (
            (return_status IN ('draft', 'cancelled') AND posted_at IS NULL)
            OR
            (return_status = 'posted' AND posted_at IS NOT NULL)
        )
);

CREATE INDEX idx_sales_returns_business_date
    ON sales_returns (business_id, return_date DESC);

CREATE INDEX idx_sales_returns_sale
    ON sales_returns (business_id, sale_id);

CREATE INDEX idx_sales_returns_status
    ON sales_returns (business_id, return_status, refund_status);


-- ------------------------------------------------------------
-- 2. Sales Return Items
-- ------------------------------------------------------------
CREATE TABLE sales_return_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    sales_return_id UUID NOT NULL,
    sale_id UUID NOT NULL,
    sale_item_id UUID NOT NULL,
    product_id UUID NOT NULL,

    -- Historical snapshots from the original sale item.
    product_name_snapshot VARCHAR(200) NOT NULL,
    sku_snapshot VARCHAR(100),
    quantity NUMERIC(14,3) NOT NULL CHECK (quantity > 0),
    unit_id UUID NOT NULL,
    unit_price NUMERIC(14,2) NOT NULL CHECK (unit_price >= 0),
    cost_price_snapshot NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (cost_price_snapshot >= 0),
    discount_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (discount_amount >= 0),
    tax_rate NUMERIC(7,4) NOT NULL DEFAULT 0
        CHECK (tax_rate >= 0 AND tax_rate <= 100),
    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (tax_amount >= 0),
    line_total NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (line_total >= 0),

    restock_condition VARCHAR(20) NOT NULL DEFAULT 'restock'
        CHECK (restock_condition IN ('restock', 'damaged', 'write_off')),
    reason VARCHAR(255),
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_sales_return_items_business_id
        UNIQUE (business_id, id),
    CONSTRAINT uq_sales_return_items_business_sale_product
        UNIQUE (business_id, id, product_id),

    CONSTRAINT fk_sales_return_items_return_same_business
        FOREIGN KEY (business_id, sales_return_id, sale_id)
        REFERENCES sales_returns (business_id, id, sale_id),

    CONSTRAINT fk_sales_return_items_original_sale_item
        FOREIGN KEY (business_id, sale_id, sale_item_id, product_id)
        REFERENCES sale_items (business_id, sale_id, id, product_id),

    CONSTRAINT sales_return_items_unit_id_fkey
        FOREIGN KEY (unit_id) REFERENCES units (id),
    CONSTRAINT sales_return_items_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES users (id),
    CONSTRAINT sales_return_items_updated_by_fkey
        FOREIGN KEY (updated_by) REFERENCES users (id)
);

CREATE INDEX idx_sales_return_items_return
    ON sales_return_items (business_id, sales_return_id);

CREATE INDEX idx_sales_return_items_original_sale_item
    ON sales_return_items (business_id, sale_id, sale_item_id);

CREATE INDEX idx_sales_return_items_product
    ON sales_return_items (business_id, product_id);


-- ------------------------------------------------------------
-- 3. Extend stock ledger to record sales return movements.
--    This is required because Migration 008 intentionally
--    established typed source references before this table existed.
-- ------------------------------------------------------------
ALTER TABLE stock_ledger
    ADD COLUMN sales_return_item_id UUID;

ALTER TABLE stock_ledger
    ADD CONSTRAINT fk_stock_ledger_sales_return_item_same_business
    FOREIGN KEY (business_id, sales_return_item_id, product_id)
    REFERENCES sales_return_items (business_id, id, product_id);

ALTER TABLE stock_ledger
    DROP CONSTRAINT chk_stock_ledger_exactly_one_source;

ALTER TABLE stock_ledger
    ADD CONSTRAINT chk_stock_ledger_exactly_one_source
    CHECK (
        num_nonnulls(
            purchase_item_id,
            purchase_return_item_id,
            sale_item_id,
            sales_return_item_id,
            stock_adjustment_item_id
        ) = 1
        OR
        (
            movement_type IN ('opening_in', 'opening_out', 'transfer_in', 'transfer_out', 'reversal')
            AND num_nonnulls(
                purchase_item_id,
                purchase_return_item_id,
                sale_item_id,
                sales_return_item_id,
                stock_adjustment_item_id
            ) = 0
        )
    );

CREATE INDEX idx_stock_ledger_sales_return_item
    ON stock_ledger (business_id, sales_return_item_id)
    WHERE sales_return_item_id IS NOT NULL;

COMMIT;
