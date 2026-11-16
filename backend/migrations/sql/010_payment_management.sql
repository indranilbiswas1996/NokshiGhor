-- NokshiGhor | Migration 010: Payment Management
-- PostgreSQL 17; depends on migrations 001-009.
-- Cross-row payment validation must be performed by the backend
-- in a single transaction with SELECT ... FOR UPDATE.

BEGIN;

-- Exact composite FK targets required by the allocation tables.
CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_business_id_payment_fk
    ON sales (business_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_purchases_business_id_payment_fk
    ON purchases (business_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sales_returns_business_id_payment_fk
    ON sales_returns (business_id, id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_purchase_returns_business_id_payment_fk
    ON purchase_returns (business_id, id);

CREATE TABLE payment_methods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    method_code VARCHAR(30) NOT NULL,
    method_name VARCHAR(80) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order SMALLINT NOT NULL DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT uq_payment_methods_business_id UNIQUE (business_id, id),
    CONSTRAINT uq_payment_methods_business_code UNIQUE (business_id, method_code),
    CONSTRAINT fk_payment_methods_business FOREIGN KEY (business_id) REFERENCES businesses(id),
    CONSTRAINT chk_payment_methods_display_order CHECK (display_order >= 0)
);

CREATE INDEX idx_payment_methods_business_active
    ON payment_methods (business_id, is_active) WHERE deleted_at IS NULL;

CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    payment_number VARCHAR(50) NOT NULL,
    party_id UUID NOT NULL,
    payment_method_id UUID NOT NULL,
    payment_direction VARCHAR(10) NOT NULL,
    payment_category VARCHAR(20) NOT NULL DEFAULT 'invoice',
    payment_status VARCHAR(15) NOT NULL DEFAULT 'draft',
    payment_date DATE NOT NULL DEFAULT CURRENT_DATE,
    amount NUMERIC(14,2) NOT NULL,
    currency CHAR(3) NOT NULL DEFAULT 'INR',
    transaction_reference VARCHAR(120),
    bank_name VARCHAR(120),
    cheque_number VARCHAR(80),
    cheque_date DATE,
    notes TEXT,
    internal_notes TEXT,
    idempotency_key VARCHAR(120),
    posted_at TIMESTAMPTZ,
    posted_by UUID REFERENCES users(id),
    cancelled_at TIMESTAMPTZ,
    cancelled_by UUID REFERENCES users(id),
    cancellation_reason TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT uq_payments_business_id UNIQUE (business_id, id),
    CONSTRAINT uq_payments_business_number UNIQUE (business_id, payment_number),
    CONSTRAINT fk_payments_business FOREIGN KEY (business_id) REFERENCES businesses(id),
    CONSTRAINT fk_payments_party_same_business
        FOREIGN KEY (business_id, party_id) REFERENCES parties (business_id, id),
    CONSTRAINT fk_payments_method_same_business
        FOREIGN KEY (business_id, payment_method_id) REFERENCES payment_methods (business_id, id),
    CONSTRAINT chk_payments_direction CHECK (payment_direction IN ('in', 'out')),
    CONSTRAINT chk_payments_category CHECK (payment_category IN ('invoice', 'advance', 'refund', 'other')),
    CONSTRAINT chk_payments_status CHECK (payment_status IN ('draft', 'posted', 'cancelled')),
    CONSTRAINT chk_payments_amount CHECK (amount > 0),
    CONSTRAINT chk_payments_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT chk_payments_posted_state CHECK (
        payment_status <> 'posted' OR (posted_at IS NOT NULL AND posted_by IS NOT NULL)
    ),
    CONSTRAINT chk_payments_cancelled_state CHECK (
        payment_status <> 'cancelled'
        OR (cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL AND cancellation_reason IS NOT NULL)
    )
);

CREATE UNIQUE INDEX uq_payments_business_idempotency
    ON payments (business_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX idx_payments_business_date ON payments (business_id, payment_date DESC);
CREATE INDEX idx_payments_business_party_date ON payments (business_id, party_id, payment_date DESC);
CREATE INDEX idx_payments_business_status ON payments (business_id, payment_status, payment_direction);
CREATE INDEX idx_payments_method ON payments (business_id, payment_method_id);

CREATE TABLE sale_payment_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    payment_id UUID NOT NULL,
    sale_id UUID NOT NULL,
    allocated_amount NUMERIC(14,2) NOT NULL CHECK (allocated_amount > 0),
    allocation_date DATE NOT NULL DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT uq_sale_payment_allocations_business_id UNIQUE (business_id, id),
    CONSTRAINT uq_sale_payment_allocations_payment_sale UNIQUE (business_id, payment_id, sale_id),
    CONSTRAINT fk_sale_alloc_payment_same_business
        FOREIGN KEY (business_id, payment_id) REFERENCES payments (business_id, id),
    CONSTRAINT fk_sale_alloc_sale_same_business
        FOREIGN KEY (business_id, sale_id) REFERENCES sales (business_id, id)
);
CREATE INDEX idx_sale_payment_allocations_sale ON sale_payment_allocations (business_id, sale_id);
CREATE INDEX idx_sale_payment_allocations_payment ON sale_payment_allocations (business_id, payment_id);

CREATE TABLE purchase_payment_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    payment_id UUID NOT NULL,
    purchase_id UUID NOT NULL,
    allocated_amount NUMERIC(14,2) NOT NULL CHECK (allocated_amount > 0),
    allocation_date DATE NOT NULL DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT uq_purchase_payment_allocations_business_id UNIQUE (business_id, id),
    CONSTRAINT uq_purchase_payment_allocations_payment_purchase UNIQUE (business_id, payment_id, purchase_id),
    CONSTRAINT fk_purchase_alloc_payment_same_business
        FOREIGN KEY (business_id, payment_id) REFERENCES payments (business_id, id),
    CONSTRAINT fk_purchase_alloc_purchase_same_business
        FOREIGN KEY (business_id, purchase_id) REFERENCES purchases (business_id, id)
);
CREATE INDEX idx_purchase_payment_allocations_purchase ON purchase_payment_allocations (business_id, purchase_id);
CREATE INDEX idx_purchase_payment_allocations_payment ON purchase_payment_allocations (business_id, payment_id);

CREATE TABLE sales_return_refund_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    payment_id UUID NOT NULL,
    sales_return_id UUID NOT NULL,
    allocated_amount NUMERIC(14,2) NOT NULL CHECK (allocated_amount > 0),
    allocation_date DATE NOT NULL DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT uq_sales_return_refund_allocations_business_id UNIQUE (business_id, id),
    CONSTRAINT uq_sales_return_refund_allocations_payment_return UNIQUE (business_id, payment_id, sales_return_id),
    CONSTRAINT fk_sales_refund_alloc_payment_same_business
        FOREIGN KEY (business_id, payment_id) REFERENCES payments (business_id, id),
    CONSTRAINT fk_sales_refund_alloc_return_same_business
        FOREIGN KEY (business_id, sales_return_id) REFERENCES sales_returns (business_id, id)
);
CREATE INDEX idx_sales_return_refund_allocations_return
    ON sales_return_refund_allocations (business_id, sales_return_id);
CREATE INDEX idx_sales_return_refund_allocations_payment
    ON sales_return_refund_allocations (business_id, payment_id);

CREATE TABLE purchase_return_refund_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    payment_id UUID NOT NULL,
    purchase_return_id UUID NOT NULL,
    allocated_amount NUMERIC(14,2) NOT NULL CHECK (allocated_amount > 0),
    allocation_date DATE NOT NULL DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT uq_purchase_return_refund_allocations_business_id UNIQUE (business_id, id),
    CONSTRAINT uq_purchase_return_refund_allocations_payment_return UNIQUE (business_id, payment_id, purchase_return_id),
    CONSTRAINT fk_purchase_refund_alloc_payment_same_business
        FOREIGN KEY (business_id, payment_id) REFERENCES payments (business_id, id),
    CONSTRAINT fk_purchase_refund_alloc_return_same_business
        FOREIGN KEY (business_id, purchase_return_id) REFERENCES purchase_returns (business_id, id)
);
CREATE INDEX idx_purchase_return_refund_allocations_return
    ON purchase_return_refund_allocations (business_id, purchase_return_id);
CREATE INDEX idx_purchase_return_refund_allocations_payment
    ON purchase_return_refund_allocations (business_id, payment_id);

COMMIT;

-- Backend posting rules (must be atomic and concurrency-safe):
-- sale allocation: payment direction=in; category invoice/advance.
-- purchase allocation: direction=out; category invoice/advance.
-- sales-return refund: direction=out; category=refund.
-- purchase-return refund: direction=in; category=refund.
-- Match payment party to customer/supplier of target invoice or return.
-- Sum of active posted allocations <= payment.amount.
-- Allocation <= target invoice/return outstanding balance.
-- Lock payment and target documents FOR UPDATE before allocation.
-- Recompute sales/purchases paid_amount and payment_status from allocations.
-- Only posted payments affect balances; reverse posted entries instead of deleting.
