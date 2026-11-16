-- Migration 011: Expense Management
-- NokshiGhor | PostgreSQL 17
-- Run once only after migrations 001-010 have been successfully committed.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Expense categories
-- ---------------------------------------------------------------------------
CREATE TABLE expense_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    category_name VARCHAR(100) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order SMALLINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT fk_expense_categories_business
        FOREIGN KEY (business_id) REFERENCES businesses(id),
    CONSTRAINT uq_expense_categories_business_id
        UNIQUE (business_id, id),
    CONSTRAINT chk_expense_categories_display_order
        CHECK (display_order >= 0)
);

CREATE UNIQUE INDEX uq_expense_categories_business_name
    ON expense_categories (business_id, LOWER(category_name))
    WHERE deleted_at IS NULL;

CREATE INDEX idx_expense_categories_business_active
    ON expense_categories (business_id, is_active)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 2. Expenses
-- ---------------------------------------------------------------------------
CREATE TABLE expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    expense_number VARCHAR(50) NOT NULL,
    expense_category_id UUID NOT NULL,
    payee_party_id UUID,
    expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
    description VARCHAR(250) NOT NULL,
    reference_number VARCHAR(100),
    subtotal NUMERIC(14,2) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    tax_rate NUMERIC(7,4) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_amount NUMERIC(14,2) NOT NULL,
    paid_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    payment_status VARCHAR(20) NOT NULL DEFAULT 'unpaid',
    expense_status VARCHAR(20) NOT NULL DEFAULT 'draft',
    notes TEXT,
    internal_notes TEXT,
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

    CONSTRAINT fk_expenses_business
        FOREIGN KEY (business_id) REFERENCES businesses(id),
    CONSTRAINT fk_expenses_category_same_business
        FOREIGN KEY (business_id, expense_category_id)
        REFERENCES expense_categories (business_id, id),
    CONSTRAINT fk_expenses_payee_same_business
        FOREIGN KEY (business_id, payee_party_id)
        REFERENCES parties (business_id, id),
    CONSTRAINT uq_expenses_business_id
        UNIQUE (business_id, id),
    CONSTRAINT uq_expenses_business_number
        UNIQUE (business_id, expense_number),

    CONSTRAINT chk_expenses_subtotal
        CHECK (subtotal >= 0),
    CONSTRAINT chk_expenses_discount
        CHECK (discount_amount >= 0 AND discount_amount <= subtotal),
    CONSTRAINT chk_expenses_tax_rate
        CHECK (tax_rate >= 0 AND tax_rate <= 100),
    CONSTRAINT chk_expenses_tax_amount
        CHECK (tax_amount >= 0),
    CONSTRAINT chk_expenses_total
        CHECK (total_amount > 0 AND total_amount = subtotal - discount_amount + tax_amount),
    CONSTRAINT chk_expenses_paid_amount
        CHECK (paid_amount >= 0 AND paid_amount <= total_amount),
    CONSTRAINT chk_expenses_payment_status
        CHECK (payment_status IN ('unpaid', 'partial', 'paid')),
    CONSTRAINT chk_expenses_status
        CHECK (expense_status IN ('draft', 'posted', 'cancelled')),
    CONSTRAINT chk_expenses_posted_state
        CHECK (
            expense_status <> 'posted'
            OR (posted_at IS NOT NULL AND posted_by IS NOT NULL)
        ),
    CONSTRAINT chk_expenses_cancelled_state
        CHECK (
            expense_status <> 'cancelled'
            OR (
                cancelled_at IS NOT NULL
                AND cancelled_by IS NOT NULL
                AND cancellation_reason IS NOT NULL
            )
        )
);

CREATE INDEX idx_expenses_business_date
    ON expenses (business_id, expense_date DESC);

CREATE INDEX idx_expenses_business_category
    ON expenses (business_id, expense_category_id, expense_date DESC);

CREATE INDEX idx_expenses_business_payee
    ON expenses (business_id, payee_party_id)
    WHERE payee_party_id IS NOT NULL;

CREATE INDEX idx_expenses_business_payment_status
    ON expenses (business_id, payment_status, expense_date DESC);

CREATE INDEX idx_expenses_business_status
    ON expenses (business_id, expense_status, expense_date DESC);

-- ---------------------------------------------------------------------------
-- 3. Expense payment allocations
--    Payments must be OUT + OTHER + POSTED.
--    Party matching and allocation totals are enforced by backend transactions.
-- ---------------------------------------------------------------------------
CREATE TABLE expense_payment_allocations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    expense_id UUID NOT NULL,
    payment_id UUID NOT NULL,
    allocated_amount NUMERIC(14,2) NOT NULL,
    allocation_date DATE NOT NULL DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_expense_payment_allocations_business
        FOREIGN KEY (business_id) REFERENCES businesses(id),
    CONSTRAINT fk_expense_payment_allocations_expense_same_business
        FOREIGN KEY (business_id, expense_id)
        REFERENCES expenses (business_id, id),
    CONSTRAINT fk_expense_payment_allocations_payment_same_business
        FOREIGN KEY (business_id, payment_id)
        REFERENCES payments (business_id, id),
    CONSTRAINT chk_expense_payment_allocations_amount
        CHECK (allocated_amount > 0)
);

CREATE UNIQUE INDEX uq_expense_payment_allocations_active
    ON expense_payment_allocations (business_id, expense_id, payment_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_expense_payment_allocations_expense
    ON expense_payment_allocations (business_id, expense_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_expense_payment_allocations_payment
    ON expense_payment_allocations (business_id, payment_id)
    WHERE deleted_at IS NULL;

COMMIT;

-- ---------------------------------------------------------------------------
-- REQUIRED BACKEND TRANSACTION RULES
-- ---------------------------------------------------------------------------
-- 1. Only posted expenses can receive payment allocations.
-- 2. An allocation may reference only a payment with:
--      payment_direction = 'out'
--      payment_category  = 'other'
--      payment_status    = 'posted'
-- 3. If an expense has an allocation, payee_party_id must be non-NULL and
--    must equal payments.party_id.
-- 4. SUM(active allocations for a payment) must not exceed payments.amount.
-- 5. SUM(active allocations for an expense) must not exceed expenses.total_amount.
-- 6. Lock the expense and payment rows FOR UPDATE before creating allocations.
-- 7. Recalculate expenses.paid_amount and payment_status from active allocations:
--      0                         => unpaid
--      0 < paid_amount < total   => partial
--      paid_amount = total      => paid
-- 8. Only posted payments affect expense balances.
-- 9. Do not hard-delete posted expenses or allocations. Use reversal/correction
--    workflows and preserve audit history.
-- 10. A payment can be allocated across multiple expenses; an expense can be
--     settled by multiple payments.
