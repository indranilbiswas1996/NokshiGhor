BEGIN;

-- ============================================
-- NOKSHIGHOR
-- MIGRATION 006: PURCHASE MANAGEMENT
-- PostgreSQL 17
-- ============================================

-- 1. WAREHOUSES

CREATE TABLE warehouses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL
        REFERENCES businesses(id) ON DELETE RESTRICT,

    warehouse_name VARCHAR(150) NOT NULL,
    warehouse_code VARCHAR(50),

    address TEXT,
    phone VARCHAR(20),

    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_warehouses_business_id
        UNIQUE (business_id, id)
);

CREATE UNIQUE INDEX uq_warehouses_name
    ON warehouses (business_id, LOWER(warehouse_name))
    WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_warehouses_code
    ON warehouses (business_id, LOWER(warehouse_code))
    WHERE warehouse_code IS NOT NULL AND deleted_at IS NULL;

CREATE UNIQUE INDEX uq_warehouses_default
    ON warehouses (business_id)
    WHERE is_default = TRUE AND deleted_at IS NULL;

CREATE INDEX idx_warehouses_business
    ON warehouses (business_id);


-- 2. PURCHASES

CREATE TABLE purchases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,
    supplier_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,

    purchase_number VARCHAR(80) NOT NULL,
    supplier_invoice_number VARCHAR(100),

    purchase_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE,

    purchase_status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (
            purchase_status IN (
                'draft', 'posted', 'partially_returned',
                'returned', 'cancelled'
            )
        ),

    -- Cached payment summary.
    -- The payments/payment_allocations module will be the source of truth.
    -- Update these two fields atomically with payment allocation changes.
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

    transport_charge NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (transport_charge >= 0),

    other_charges NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (other_charges >= 0),

    round_off NUMERIC(14,2) NOT NULL DEFAULT 0,

    total_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (total_amount >= 0),

    paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (paid_amount >= 0),

    notes TEXT,

    -- Supplier details snapshot at purchase time
    supplier_name_snapshot VARCHAR(200) NOT NULL,
    supplier_phone_snapshot VARCHAR(20),
    supplier_gstin_snapshot VARCHAR(20),

    -- Business/shop details snapshot at purchase time
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

    CONSTRAINT uq_purchases_business_id
        UNIQUE (business_id, id),

    -- Required to enforce that a purchase return uses this purchase's supplier.
    CONSTRAINT uq_purchases_business_id_supplier
        UNIQUE (business_id, id, supplier_id),

    CONSTRAINT uq_purchases_number
        UNIQUE (business_id, purchase_number),

    CONSTRAINT fk_purchases_supplier_same_business
        FOREIGN KEY (business_id, supplier_id)
        REFERENCES suppliers (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_purchases_warehouse_same_business
        FOREIGN KEY (business_id, warehouse_id)
        REFERENCES warehouses (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_purchase_due_date
        CHECK (due_date IS NULL OR due_date >= purchase_date),

    CONSTRAINT chk_purchase_paid_amount
        CHECK (paid_amount <= total_amount),

    -- A posted purchase cannot be directly cancelled.
    -- Correct posted documents through a return/reversal workflow.
    CONSTRAINT chk_purchase_posted_at
        CHECK (
            (purchase_status IN ('draft', 'cancelled') AND posted_at IS NULL)
            OR
            (purchase_status IN ('posted', 'partially_returned', 'returned')
                AND posted_at IS NOT NULL)
        )
);

CREATE INDEX idx_purchases_business_date
    ON purchases (business_id, purchase_date DESC);

CREATE INDEX idx_purchases_supplier
    ON purchases (business_id, supplier_id);

CREATE INDEX idx_purchases_status
    ON purchases (business_id, purchase_status, payment_status);


-- 3. PURCHASE ITEMS

CREATE TABLE purchase_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,
    purchase_id UUID NOT NULL,
    product_id UUID NOT NULL,

    -- Historical product snapshot
    product_name_snapshot VARCHAR(200) NOT NULL,
    sku_snapshot VARCHAR(80),
    hsn_sac_snapshot VARCHAR(20),

    quantity NUMERIC(14,3) NOT NULL
        CHECK (quantity > 0),

    unit_id UUID NOT NULL
        REFERENCES units(id) ON DELETE RESTRICT,

    unit_cost NUMERIC(14,2) NOT NULL
        CHECK (unit_cost >= 0),

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

    CONSTRAINT uq_purchase_items_business_id
        UNIQUE (business_id, id),

    -- Composite keys below allow return rows to prove that the selected
    -- item and product belong to the same original purchase.
    CONSTRAINT uq_purchase_items_purchase_item
        UNIQUE (business_id, purchase_id, id),

    CONSTRAINT uq_purchase_items_purchase_item_product
        UNIQUE (business_id, purchase_id, id, product_id),

    CONSTRAINT fk_purchase_items_purchase_same_business
        FOREIGN KEY (business_id, purchase_id)
        REFERENCES purchases (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_purchase_items_product_same_business
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id)
        ON DELETE RESTRICT
);

CREATE INDEX idx_purchase_items_purchase
    ON purchase_items (business_id, purchase_id);

CREATE INDEX idx_purchase_items_product
    ON purchase_items (business_id, product_id);


-- 4. PURCHASE RETURNS

CREATE TABLE purchase_returns (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,
    purchase_id UUID NOT NULL,
    supplier_id UUID NOT NULL,

    return_number VARCHAR(80) NOT NULL,
    return_date DATE NOT NULL DEFAULT CURRENT_DATE,

    return_status VARCHAR(20) NOT NULL DEFAULT 'draft'
        CHECK (return_status IN ('draft', 'posted', 'cancelled')),

    subtotal NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (subtotal >= 0),

    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (tax_amount >= 0),

    total_amount NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (total_amount >= 0),

    reason TEXT,

    supplier_name_snapshot VARCHAR(200) NOT NULL,

    posted_at TIMESTAMPTZ,
    posted_by UUID REFERENCES users(id) ON DELETE SET NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_purchase_returns_business_id
        UNIQUE (business_id, id),

    -- Required for the return-items composite relationship.
    CONSTRAINT uq_purchase_returns_business_purchase
        UNIQUE (business_id, id, purchase_id),

    CONSTRAINT uq_purchase_returns_number
        UNIQUE (business_id, return_number),

    -- Ensures the return's supplier is exactly the supplier on its purchase.
    CONSTRAINT fk_purchase_returns_purchase_supplier
        FOREIGN KEY (business_id, purchase_id, supplier_id)
        REFERENCES purchases (business_id, id, supplier_id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_purchase_return_posted_at
        CHECK (
            (return_status IN ('draft', 'cancelled') AND posted_at IS NULL)
            OR
            (return_status = 'posted' AND posted_at IS NOT NULL)
        )
);

CREATE INDEX idx_purchase_returns_purchase
    ON purchase_returns (business_id, purchase_id);

CREATE INDEX idx_purchase_returns_supplier
    ON purchase_returns (business_id, supplier_id);


-- 5. PURCHASE RETURN ITEMS

CREATE TABLE purchase_return_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,
    purchase_return_id UUID NOT NULL,
    purchase_id UUID NOT NULL,
    purchase_item_id UUID NOT NULL,
    product_id UUID NOT NULL,

    product_name_snapshot VARCHAR(200) NOT NULL,

    quantity NUMERIC(14,3) NOT NULL
        CHECK (quantity > 0),

    unit_cost NUMERIC(14,2) NOT NULL
        CHECK (unit_cost >= 0),

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

    -- The return and its original purchase must match.
    CONSTRAINT fk_purchase_return_items_return_purchase
        FOREIGN KEY (business_id, purchase_return_id, purchase_id)
        REFERENCES purchase_returns (business_id, id, purchase_id)
        ON DELETE RESTRICT,

    -- The selected purchase item and product must belong to that same purchase.
    CONSTRAINT fk_purchase_return_items_original_purchase_item
        FOREIGN KEY (business_id, purchase_id, purchase_item_id, product_id)
        REFERENCES purchase_items (business_id, purchase_id, id, product_id)
        ON DELETE RESTRICT
);

CREATE INDEX idx_purchase_return_items_return
    ON purchase_return_items (business_id, purchase_return_id);

CREATE INDEX idx_purchase_return_items_purchase_item
    ON purchase_return_items (business_id, purchase_id, purchase_item_id);

COMMIT;
