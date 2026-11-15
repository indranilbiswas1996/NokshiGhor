BEGIN;

-- ============================================
-- NOKSHIGHOR
-- MIGRATION 007: SALES MANAGEMENT
-- PostgreSQL 17
-- ============================================

-- 1. SALES (INVOICE HEADER)

CREATE TABLE sales (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL
        REFERENCES businesses(id) ON DELETE RESTRICT,

    customer_id UUID,
    warehouse_id UUID,

    sale_number VARCHAR(80) NOT NULL,

    sale_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE,

    sale_status VARCHAR(24) NOT NULL DEFAULT 'draft'
        CHECK (
            sale_status IN (
                'draft', 'posted', 'partially_returned',
                'returned', 'cancelled'
            )
        ),

    -- Cached payment summary.
    -- payments/payment_allocations will be the source of truth.
    -- Keep these fields synchronized in the same database transaction.
    payment_status VARCHAR(20) NOT NULL DEFAULT 'unpaid'
        CHECK (
            payment_status IN ('unpaid', 'partially_paid', 'paid')
        ),

    subtotal NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (subtotal >= 0),

    discount_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (discount_amount >= 0),

    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (tax_amount >= 0),

    shipping_charge NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (shipping_charge >= 0),

    other_charges NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (other_charges >= 0),

    round_off NUMERIC(14,2) NOT NULL DEFAULT 0,

    total_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (total_amount >= 0),

    paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (paid_amount >= 0),

    notes TEXT,

    -- Customer details snapshot at sale time.
    -- For walk-in sales, the application should store a suitable label
    -- such as 'Walk-in Customer' and leave customer_id NULL.
    customer_name_snapshot VARCHAR(200) NOT NULL,
    customer_phone_snapshot VARCHAR(20),
    customer_gstin_snapshot VARCHAR(20),

    -- Business/shop details snapshot at sale time.
    shop_name_snapshot VARCHAR(200) NOT NULL,
    shop_address_snapshot TEXT,
    shop_gstin_snapshot VARCHAR(20),

    posted_at TIMESTAMPTZ,
    posted_by UUID REFERENCES users(id) ON DELETE SET NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_sales_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_sales_number
        UNIQUE (business_id, sale_number),

    CONSTRAINT fk_sales_customer_same_business
        FOREIGN KEY (business_id, customer_id)
        REFERENCES customers (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_sales_warehouse_same_business
        FOREIGN KEY (business_id, warehouse_id)
        REFERENCES warehouses (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_sales_due_date
        CHECK (due_date IS NULL OR due_date >= sale_date),

    CONSTRAINT chk_sales_paid_amount
        CHECK (paid_amount <= total_amount),

    -- A posted sale cannot be directly cancelled.
    -- Correct posted documents through return/reversal workflows.
    CONSTRAINT chk_sales_posted_at
        CHECK (
            (sale_status IN ('draft', 'cancelled') AND posted_at IS NULL)
            OR
            (sale_status IN ('posted', 'partially_returned', 'returned')
                AND posted_at IS NOT NULL)
        )
);

CREATE INDEX idx_sales_business_date
    ON sales (business_id, sale_date DESC);

CREATE INDEX idx_sales_customer
    ON sales (business_id, customer_id);

CREATE INDEX idx_sales_warehouse
    ON sales (business_id, warehouse_id);

CREATE INDEX idx_sales_status
    ON sales (business_id, sale_status, payment_status);


-- 2. SALE ITEMS (INVOICE LINE ITEMS)

CREATE TABLE sale_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,
    sale_id UUID NOT NULL,
    product_id UUID NOT NULL,

    -- Historical product details snapshot at sale time.
    product_name_snapshot VARCHAR(200) NOT NULL,
    sku_snapshot VARCHAR(80),
    hsn_sac_snapshot VARCHAR(20),

    -- Snapshot whether this product was inventory tracked at sale time.
    -- Backend posting logic will use this to decide stock movement.
    track_inventory_snapshot BOOLEAN NOT NULL DEFAULT TRUE,

    quantity NUMERIC(14,3) NOT NULL
        CHECK (quantity > 0),

    unit_id UUID NOT NULL
        REFERENCES units(id) ON DELETE RESTRICT,

    unit_price NUMERIC(14,2) NOT NULL
        CHECK (unit_price >= 0),

    -- Cost snapshot is required for historical gross-profit reporting.
    cost_price_snapshot NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (cost_price_snapshot >= 0),

    discount_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (discount_amount >= 0),

    tax_rate NUMERIC(7,4) NOT NULL DEFAULT 0
        CHECK (tax_rate BETWEEN 0 AND 100),

    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (tax_amount >= 0),

    line_total NUMERIC(14,2) NOT NULL
        CHECK (line_total >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_sale_items_business_id
        UNIQUE (business_id, id),

    -- Composite keys support strict same-sale validation in future
    -- sales-return item relationships.
    CONSTRAINT uq_sale_items_business_sale_item
        UNIQUE (business_id, sale_id, id),

    CONSTRAINT uq_sale_items_business_sale_item_product
        UNIQUE (business_id, sale_id, id, product_id),

    CONSTRAINT fk_sale_items_sale_same_business
        FOREIGN KEY (business_id, sale_id)
        REFERENCES sales (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_sale_items_product_same_business
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX idx_sale_items_sale
    ON sale_items (business_id, sale_id);

CREATE INDEX idx_sale_items_product
    ON sale_items (business_id, product_id);

COMMIT;
