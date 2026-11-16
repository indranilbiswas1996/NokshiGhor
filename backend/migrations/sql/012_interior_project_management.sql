-- Migration 012: Interior Project Management
-- NokshiGhor | PostgreSQL 17
-- Requires migrations 001-011.
-- Run once only. Do not rerun after successful COMMIT.

BEGIN;

-- ---------------------------------------------------------------------------
-- 0. Supporting composite unique key: product + its unit within a business.
--    This guarantees that a project material uses the product's actual unit.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS uq_products_business_id_unit
    ON products (business_id, id, unit_id);

-- ---------------------------------------------------------------------------
-- 1. Interior projects
-- ---------------------------------------------------------------------------
CREATE TABLE interior_projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    customer_id UUID,
    project_code VARCHAR(50) NOT NULL,
    project_name VARCHAR(200) NOT NULL,
    project_type VARCHAR(30) NOT NULL DEFAULT 'other',
    project_status VARCHAR(30) NOT NULL DEFAULT 'draft',
    project_description TEXT,
    site_address TEXT,
    site_city VARCHAR(100),
    site_district VARCHAR(100),
    site_state VARCHAR(100),
    site_postal_code VARCHAR(20),
    start_date DATE,
    expected_end_date DATE,
    actual_end_date DATE,
    estimated_budget NUMERIC(14,2) NOT NULL DEFAULT 0,
    quoted_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    contract_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    notes TEXT,
    internal_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_interior_projects_business
        FOREIGN KEY (business_id) REFERENCES businesses(id),
    CONSTRAINT fk_interior_projects_customer_same_business
        FOREIGN KEY (business_id, customer_id)
        REFERENCES customers (business_id, id),
    CONSTRAINT uq_interior_projects_business_id
        UNIQUE (business_id, id),
    CONSTRAINT uq_interior_projects_business_code
        UNIQUE (business_id, project_code),
    CONSTRAINT chk_interior_projects_type
        CHECK (project_type IN ('residential', 'commercial', 'office', 'retail', 'other')),
    CONSTRAINT chk_interior_projects_status
        CHECK (project_status IN ('draft', 'quoted', 'approved', 'in_progress', 'on_hold', 'completed', 'cancelled')),
    CONSTRAINT chk_interior_projects_budget
        CHECK (estimated_budget >= 0 AND quoted_amount >= 0 AND contract_amount >= 0),
    CONSTRAINT chk_interior_projects_dates
        CHECK (
            (start_date IS NULL OR expected_end_date IS NULL OR expected_end_date >= start_date)
            AND
            (actual_end_date IS NULL OR start_date IS NULL OR actual_end_date >= start_date)
        )
);

CREATE INDEX idx_interior_projects_business_status
    ON interior_projects (business_id, project_status)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_interior_projects_business_customer
    ON interior_projects (business_id, customer_id)
    WHERE customer_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_interior_projects_business_dates
    ON interior_projects (business_id, start_date, expected_end_date)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 2. Project materials
--    Planned quantities and estimates are stored here.
--    Actual stock issues/returns are recorded in stock_ledger.
-- ---------------------------------------------------------------------------
CREATE TABLE project_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    project_id UUID NOT NULL,
    product_id UUID NOT NULL,
    warehouse_id UUID NOT NULL,
    unit_id UUID NOT NULL,
    planned_quantity NUMERIC(14,3) NOT NULL,
    issued_quantity NUMERIC(14,3) NOT NULL DEFAULT 0,
    returned_quantity NUMERIC(14,3) NOT NULL DEFAULT 0,
    estimated_unit_cost NUMERIC(14,2) NOT NULL DEFAULT 0,
    notes TEXT,
    material_status VARCHAR(25) NOT NULL DEFAULT 'planned',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_project_materials_project_same_business
        FOREIGN KEY (business_id, project_id)
        REFERENCES interior_projects (business_id, id),
    CONSTRAINT fk_project_materials_product_same_business_unit
        FOREIGN KEY (business_id, product_id, unit_id)
        REFERENCES products (business_id, id, unit_id),
    CONSTRAINT fk_project_materials_warehouse_same_business
        FOREIGN KEY (business_id, warehouse_id)
        REFERENCES warehouses (business_id, id),
    CONSTRAINT uq_project_materials_business_id_product
        UNIQUE (business_id, id, product_id),
    CONSTRAINT chk_project_materials_planned_quantity
        CHECK (planned_quantity > 0),
    CONSTRAINT chk_project_materials_issued_quantity
        CHECK (issued_quantity >= 0),
    CONSTRAINT chk_project_materials_returned_quantity
        CHECK (returned_quantity >= 0 AND returned_quantity <= issued_quantity),
    CONSTRAINT chk_project_materials_estimated_unit_cost
        CHECK (estimated_unit_cost >= 0),
    CONSTRAINT chk_project_materials_status
        CHECK (material_status IN ('planned', 'partially_issued', 'issued', 'partially_returned', 'returned', 'cancelled'))
);

CREATE INDEX idx_project_materials_project
    ON project_materials (business_id, project_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_project_materials_product_warehouse
    ON project_materials (business_id, product_id, warehouse_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_project_materials_status
    ON project_materials (business_id, material_status)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 3. Extend stock ledger for project material issue and return.
--    Existing source and movement constraints are replaced to include the
--    project_material_id source and the two new movement types.
-- ---------------------------------------------------------------------------
ALTER TABLE stock_ledger
    ADD COLUMN project_material_id UUID;

ALTER TABLE stock_ledger
    DROP CONSTRAINT chk_stock_ledger_exactly_one_source;

ALTER TABLE stock_ledger
    DROP CONSTRAINT chk_stock_ledger_movement_direction;

ALTER TABLE stock_ledger
    DROP CONSTRAINT stock_ledger_movement_type_check;

ALTER TABLE stock_ledger
    ADD CONSTRAINT fk_stock_ledger_project_material_same_business
    FOREIGN KEY (business_id, project_material_id, product_id)
    REFERENCES project_materials (business_id, id, product_id);

ALTER TABLE stock_ledger
    ADD CONSTRAINT chk_stock_ledger_exactly_one_source
    CHECK (
        (
            num_nonnulls(
                purchase_item_id,
                purchase_return_item_id,
                sale_item_id,
                sales_return_item_id,
                stock_adjustment_item_id,
                project_material_id
            ) = 1
        )
        OR
        (
            movement_type IN (
                'opening_in',
                'opening_out',
                'transfer_in',
                'transfer_out',
                'reversal'
            )
            AND
            num_nonnulls(
                purchase_item_id,
                purchase_return_item_id,
                sale_item_id,
                sales_return_item_id,
                stock_adjustment_item_id,
                project_material_id
            ) = 0
        )
    );

ALTER TABLE stock_ledger
    ADD CONSTRAINT chk_stock_ledger_movement_direction
    CHECK (
        (
            movement_type IN (
                'purchase_in',
                'sales_return_in',
                'adjustment_in',
                'opening_in',
                'transfer_in',
                'project_material_return_in'
            )
            AND movement_direction = 'IN'
        )
        OR
        (
            movement_type IN (
                'purchase_return_out',
                'sale_out',
                'adjustment_out',
                'opening_out',
                'transfer_out',
                'project_material_out'
            )
            AND movement_direction = 'OUT'
        )
        OR movement_type = 'reversal'
    );

ALTER TABLE stock_ledger
    ADD CONSTRAINT stock_ledger_movement_type_check
    CHECK (
        movement_type IN (
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
            'reversal',
            'project_material_out',
            'project_material_return_in'
        )
    );

CREATE INDEX idx_stock_ledger_project_material
    ON stock_ledger (business_id, project_material_id, movement_at)
    WHERE project_material_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 4. Project labour
--    Labour cost is project cost. Actual payments, when applicable, should
--    also be recorded through expenses/payments and linked using project_expenses.
-- ---------------------------------------------------------------------------
CREATE TABLE project_labour (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    project_id UUID NOT NULL,
    worker_party_id UUID,
    worker_name VARCHAR(150) NOT NULL,
    work_role VARCHAR(100),
    work_date DATE NOT NULL DEFAULT CURRENT_DATE,
    work_description TEXT,
    work_quantity NUMERIC(14,3) NOT NULL DEFAULT 1,
    quantity_unit VARCHAR(20) NOT NULL DEFAULT 'day',
    rate_per_unit NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_cost NUMERIC(14,2) NOT NULL,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_project_labour_project_same_business
        FOREIGN KEY (business_id, project_id)
        REFERENCES interior_projects (business_id, id),
    CONSTRAINT fk_project_labour_worker_same_business
        FOREIGN KEY (business_id, worker_party_id)
        REFERENCES parties (business_id, id),
    CONSTRAINT chk_project_labour_quantity
        CHECK (work_quantity > 0),
    CONSTRAINT chk_project_labour_rate
        CHECK (rate_per_unit >= 0),
    CONSTRAINT chk_project_labour_total_cost
        CHECK (total_cost >= 0)
);

CREATE INDEX idx_project_labour_project_date
    ON project_labour (business_id, project_id, work_date)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_project_labour_worker
    ON project_labour (business_id, worker_party_id)
    WHERE worker_party_id IS NOT NULL AND deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 5. Allocate existing expenses to projects.
--    Expense and payment records remain in the existing accounting tables.
-- ---------------------------------------------------------------------------
CREATE TABLE project_expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    project_id UUID NOT NULL,
    expense_id UUID NOT NULL,
    allocated_amount NUMERIC(14,2) NOT NULL,
    allocation_date DATE NOT NULL DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_project_expenses_project_same_business
        FOREIGN KEY (business_id, project_id)
        REFERENCES interior_projects (business_id, id),
    CONSTRAINT fk_project_expenses_expense_same_business
        FOREIGN KEY (business_id, expense_id)
        REFERENCES expenses (business_id, id),
    CONSTRAINT chk_project_expenses_allocated_amount
        CHECK (allocated_amount > 0)
);

CREATE UNIQUE INDEX uq_project_expenses_active
    ON project_expenses (business_id, project_id, expense_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_project_expenses_project
    ON project_expenses (business_id, project_id)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_project_expenses_expense
    ON project_expenses (business_id, expense_id)
    WHERE deleted_at IS NULL;

-- ---------------------------------------------------------------------------
-- 6. Project milestones and billing references.
--    A milestone may optionally be linked to a sales invoice.
-- ---------------------------------------------------------------------------
CREATE TABLE project_milestones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    project_id UUID NOT NULL,
    milestone_name VARCHAR(150) NOT NULL,
    description TEXT,
    sequence_number SMALLINT NOT NULL DEFAULT 0,
    due_date DATE,
    milestone_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
    milestone_status VARCHAR(20) NOT NULL DEFAULT 'planned',
    sale_id UUID,
    completed_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id),
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_project_milestones_project_same_business
        FOREIGN KEY (business_id, project_id)
        REFERENCES interior_projects (business_id, id),
    CONSTRAINT fk_project_milestones_sale_same_business
        FOREIGN KEY (business_id, sale_id)
        REFERENCES sales (business_id, id),
    CONSTRAINT chk_project_milestones_sequence
        CHECK (sequence_number >= 0),
    CONSTRAINT chk_project_milestones_amount
        CHECK (milestone_amount >= 0),
    CONSTRAINT chk_project_milestones_status
        CHECK (milestone_status IN ('planned', 'invoiced', 'paid', 'overdue', 'completed', 'cancelled'))
);

CREATE INDEX idx_project_milestones_project_sequence
    ON project_milestones (business_id, project_id, sequence_number)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_project_milestones_due_date
    ON project_milestones (business_id, due_date, milestone_status)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_project_milestones_sale
    ON project_milestones (business_id, sale_id)
    WHERE sale_id IS NOT NULL;

COMMIT;

-- ---------------------------------------------------------------------------
-- REQUIRED BACKEND TRANSACTION / BUSINESS RULES
-- ---------------------------------------------------------------------------
-- 1. Only interior_projects belonging to the authenticated business may be
--    read or modified. Never trust business_id supplied by the client.
-- 2. Project materials must reference active inventory goods suitable for
--    the Interior business line ('interior' or 'both') and a warehouse in
--    the same business. Services/non-inventory products cannot be issued.
-- 3. Before issue, lock the product/warehouse stock balance and verify
--    available stock. Stock balance is calculated from stock_ledger.
-- 4. On material issue, in one DB transaction:
--      a. lock project_materials and relevant stock rows;
--      b. validate quantity and available stock;
--      c. insert stock_ledger movement_type='project_material_out',
--         movement_direction='OUT', project_material_id=<line id>,
--         quantity=<issued quantity>, unit_id=<product unit>,
--         unit_cost=<costing policy>, total_cost=quantity*unit_cost;
--      d. update project_materials.issued_quantity/material_status cache.
-- 5. On material return, in one DB transaction insert
--    movement_type='project_material_return_in',
--    movement_direction='IN', with the same project_material_id and
--    original issue cost basis; update returned_quantity/status cache.
-- 6. Total returned quantity must never exceed total issued quantity.
-- 7. The net project material cost is the sum of OUT total_cost minus IN
--    total_cost for project_material_id. Ledger rows are the source of truth.
-- 8. Reversal movements must reference the original ledger row through
--    reverses_ledger_id and must be validated to avoid duplicate reversal.
-- 9. Project expense allocations must reference posted expenses. The sum of
--    active allocations for one expense must not exceed expenses.total_amount.
-- 10. Project labour and project expense allocations must not be double-counted.
--     If a labour cost is also represented by an expense, define one as the
--     financial cost source and treat the other as supporting detail.
-- 11. A milestone sale_id must reference a posted sale for the same business;
--     verify customer/project consistency in backend transaction logic.
-- 12. Project cost/profit reports should aggregate net material ledger cost,
--     active labour total_cost, and active project_expenses allocated_amount.
-- 13. Do not edit/delete posted stock movements. Correct them with reversals.
-- 14. All issue/return operations must be idempotent for offline sync.
