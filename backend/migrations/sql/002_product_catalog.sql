
BEGIN;

-- ============================================
-- NOKSHIGHOR
-- MIGRATION 002: PRODUCT CATALOG
-- PostgreSQL 17
-- ============================================


-- 1. UNITS
-- Global measurement units shared across businesses

CREATE TABLE units (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    unit_code VARCHAR(30) NOT NULL UNIQUE,
    unit_name VARCHAR(80) NOT NULL,
    unit_symbol VARCHAR(20) NOT NULL,

    decimal_places SMALLINT NOT NULL DEFAULT 2
        CHECK (decimal_places BETWEEN 0 AND 6),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL
);


-- Default measurement units

INSERT INTO units (unit_code, unit_name, unit_symbol, decimal_places)
VALUES
    ('PCS', 'Pieces', 'pcs', 0),
    ('BOX', 'Box', 'box', 2),
    ('SET', 'Set', 'set', 2),
    ('KG', 'Kilogram', 'kg', 3),
    ('GM', 'Gram', 'g', 2),
    ('LTR', 'Litre', 'ltr', 3),
    ('MTR', 'Meter', 'm', 3),
    ('FT', 'Feet', 'ft', 2),
    ('SQFT', 'Square Feet', 'sq.ft', 2),
    ('SQM', 'Square Meter', 'sq.m', 2),
    ('ROLL', 'Roll', 'roll', 2),
    ('BAG', 'Bag', 'bag', 2),
    ('PAIR', 'Pair', 'pair', 2)
ON CONFLICT (unit_code) DO NOTHING;


-- 2. CATEGORIES
-- Categories belong to individual businesses.
-- Supports parent-child category hierarchy.

CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL
        REFERENCES businesses(id) ON DELETE RESTRICT,

    parent_id UUID,

    category_name VARCHAR(120) NOT NULL,

    category_type VARCHAR(20) NOT NULL DEFAULT 'general'
        CHECK (
            category_type IN ('electrical', 'interior', 'general')
        ),

    description TEXT,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_categories_business_id
        UNIQUE (business_id, id),

    CONSTRAINT fk_categories_parent_same_business
        FOREIGN KEY (business_id, parent_id)
        REFERENCES categories (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_categories_not_own_parent
        CHECK (parent_id IS NULL OR parent_id <> id)
);


-- Unique root category names per business

CREATE UNIQUE INDEX uq_categories_root_name
ON categories (business_id, LOWER(category_name))
WHERE parent_id IS NULL AND deleted_at IS NULL;


-- Unique subcategory names under the same parent

CREATE UNIQUE INDEX uq_categories_child_name
ON categories (business_id, parent_id, LOWER(category_name))
WHERE parent_id IS NOT NULL AND deleted_at IS NULL;


CREATE INDEX idx_categories_business
ON categories (business_id);

CREATE INDEX idx_categories_parent
ON categories (business_id, parent_id);


-- 3. PRODUCTS
-- Supports electrical products, interior materials and services.

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL
        REFERENCES businesses(id) ON DELETE RESTRICT,

    category_id UUID,

    unit_id UUID NOT NULL
        REFERENCES units(id) ON DELETE RESTRICT,

    product_name VARCHAR(200) NOT NULL,

    product_type VARCHAR(20) NOT NULL DEFAULT 'goods'
        CHECK (product_type IN ('goods', 'service')),

    business_line VARCHAR(20) NOT NULL DEFAULT 'both'
        CHECK (business_line IN ('electrical', 'interior', 'both')),

    sku VARCHAR(80) NOT NULL,

    barcode VARCHAR(100),

    brand VARCHAR(100),

    model VARCHAR(100),

    description TEXT,

    hsn_sac_code VARCHAR(20),

    purchase_price NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (purchase_price >= 0),

    selling_price NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (selling_price >= 0),

    tax_rate NUMERIC(7,4) NOT NULL DEFAULT 0
        CHECK (tax_rate BETWEEN 0 AND 100),

    track_inventory BOOLEAN NOT NULL DEFAULT TRUE,

    min_stock_level NUMERIC(14,3) NOT NULL DEFAULT 0
        CHECK (min_stock_level >= 0),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_products_business_id
        UNIQUE (business_id, id),

    CONSTRAINT fk_products_category_same_business
        FOREIGN KEY (business_id, category_id)
        REFERENCES categories (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_service_inventory
        CHECK (product_type <> 'service' OR track_inventory = FALSE)
);


-- SKU must be unique within an active business catalog

CREATE UNIQUE INDEX uq_products_business_sku
ON products (business_id, LOWER(sku))
WHERE deleted_at IS NULL;


-- Barcode must be unique within an active business catalog

CREATE UNIQUE INDEX uq_products_business_barcode
ON products (business_id, barcode)
WHERE barcode IS NOT NULL AND deleted_at IS NULL;


CREATE INDEX idx_products_business
ON products (business_id);

CREATE INDEX idx_products_category
ON products (business_id, category_id);

CREATE INDEX idx_products_name
ON products (business_id, LOWER(product_name));

CREATE INDEX idx_products_active
ON products (business_id, is_active)
WHERE deleted_at IS NULL;


-- 4. PRODUCT IMAGES
-- One product can have multiple images.

CREATE TABLE product_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,

    product_id UUID NOT NULL,

    image_url TEXT NOT NULL,

    alt_text VARCHAR(200),

    sort_order INTEGER NOT NULL DEFAULT 0,

    is_primary BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_product_images_same_business
        FOREIGN KEY (business_id, product_id)
        REFERENCES products (business_id, id)
        ON DELETE RESTRICT
);


-- Only one active primary image per product

CREATE UNIQUE INDEX uq_product_images_primary
ON product_images (business_id, product_id)
WHERE is_primary = TRUE AND deleted_at IS NULL;


CREATE INDEX idx_product_images_product
ON product_images (business_id, product_id);


COMMIT;
