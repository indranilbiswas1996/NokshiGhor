
BEGIN;

-- ============================================
-- NOKSHIGHOR
-- MIGRATION 004: CUSTOMER & SUPPLIER MANAGEMENT
-- PostgreSQL 17
-- ============================================


-- 1. PARTIES
-- Common identity for customers and suppliers.
-- One party can be both a customer and supplier.

CREATE TABLE parties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL
        REFERENCES businesses(id) ON DELETE RESTRICT,

    party_name VARCHAR(200) NOT NULL,

    party_type VARCHAR(20) NOT NULL DEFAULT 'individual'
        CHECK (party_type IN ('individual', 'business')),

    phone VARCHAR(20),
    alternate_phone VARCHAR(20),
    email VARCHAR(255),

    gstin VARCHAR(20),
    pan_number VARCHAR(20),

    opening_balance NUMERIC(14,2) NOT NULL DEFAULT 0,

    opening_balance_type VARCHAR(10) NOT NULL DEFAULT 'none'
        CHECK (opening_balance_type IN ('none', 'receivable', 'payable')),

    notes TEXT,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_parties_business_id
        UNIQUE (business_id, id),

    CONSTRAINT chk_party_opening_balance
        CHECK (
            (opening_balance = 0 AND opening_balance_type = 'none')
            OR
            (opening_balance <> 0 AND opening_balance_type <> 'none')
        )
);


CREATE INDEX idx_parties_business_name
ON parties (business_id, LOWER(party_name))
WHERE deleted_at IS NULL;

CREATE INDEX idx_parties_business_phone
ON parties (business_id, phone)
WHERE deleted_at IS NULL;

CREATE INDEX idx_parties_business_gstin
ON parties (business_id, gstin)
WHERE gstin IS NOT NULL AND deleted_at IS NULL;


-- 2. CUSTOMERS
-- Customer-specific financial and business settings.

CREATE TABLE customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,

    party_id UUID NOT NULL,

    customer_code VARCHAR(50),

    credit_limit NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (credit_limit >= 0),

    credit_days INTEGER NOT NULL DEFAULT 0
        CHECK (credit_days >= 0),

    loyalty_points NUMERIC(14,2) NOT NULL DEFAULT 0
        CHECK (loyalty_points >= 0),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_customers_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_customers_party
        UNIQUE (business_id, party_id),

    CONSTRAINT fk_customers_party_same_business
        FOREIGN KEY (business_id, party_id)
        REFERENCES parties (business_id, id)
        ON DELETE RESTRICT
);


CREATE UNIQUE INDEX uq_customers_code
ON customers (business_id, LOWER(customer_code))
WHERE customer_code IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_customers_business
ON customers (business_id);


-- 3. SUPPLIERS
-- Supplier-specific purchasing and payment settings.

CREATE TABLE suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,

    party_id UUID NOT NULL,

    supplier_code VARCHAR(50),

    payment_terms_days INTEGER NOT NULL DEFAULT 0
        CHECK (payment_terms_days >= 0),

    bank_name VARCHAR(120),
    bank_account_name VARCHAR(150),
    bank_account_number VARCHAR(50),
    bank_ifsc VARCHAR(20),

    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT uq_suppliers_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_suppliers_party
        UNIQUE (business_id, party_id),

    CONSTRAINT fk_suppliers_party_same_business
        FOREIGN KEY (business_id, party_id)
        REFERENCES parties (business_id, id)
        ON DELETE RESTRICT
);


CREATE UNIQUE INDEX uq_suppliers_code
ON suppliers (business_id, LOWER(supplier_code))
WHERE supplier_code IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_suppliers_business
ON suppliers (business_id);


-- 4. CUSTOMER ADDRESSES
-- One customer can have multiple addresses.

CREATE TABLE customer_addresses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,

    customer_id UUID NOT NULL,

    address_type VARCHAR(20) NOT NULL DEFAULT 'billing'
        CHECK (
            address_type IN ('billing', 'shipping', 'home', 'office', 'other')
        ),

    contact_name VARCHAR(150),
    contact_phone VARCHAR(20),

    address_line1 VARCHAR(250) NOT NULL,
    address_line2 VARCHAR(250),

    city VARCHAR(100),
    district VARCHAR(100),
    state VARCHAR(100),
    postal_code VARCHAR(12),
    country VARCHAR(100) NOT NULL DEFAULT 'India',

    is_default BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_customer_addresses_same_business
        FOREIGN KEY (business_id, customer_id)
        REFERENCES customers (business_id, id)
        ON DELETE RESTRICT
);


CREATE INDEX idx_customer_addresses_customer
ON customer_addresses (business_id, customer_id);

CREATE UNIQUE INDEX uq_customer_default_address
ON customer_addresses (business_id, customer_id)
WHERE is_default = TRUE AND deleted_at IS NULL;


-- 5. SUPPLIER CONTACTS
-- Multiple contacts for one supplier.

CREATE TABLE supplier_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,

    supplier_id UUID NOT NULL,

    contact_name VARCHAR(150) NOT NULL,

    designation VARCHAR(100),

    phone VARCHAR(20) NOT NULL,
    alternate_phone VARCHAR(20),
    email VARCHAR(255),

    is_primary BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_supplier_contacts_same_business
        FOREIGN KEY (business_id, supplier_id)
        REFERENCES suppliers (business_id, id)
        ON DELETE RESTRICT
);


CREATE INDEX idx_supplier_contacts_supplier
ON supplier_contacts (business_id, supplier_id);

CREATE UNIQUE INDEX uq_supplier_primary_contact
ON supplier_contacts (business_id, supplier_id)
WHERE is_primary = TRUE AND deleted_at IS NULL;


COMMIT;
