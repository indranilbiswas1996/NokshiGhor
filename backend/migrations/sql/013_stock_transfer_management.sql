-- NokshiGhor
-- Migration 013: Stock Transfer Management
-- PostgreSQL 17
--
-- Purpose:
--   Manage immediate, atomic stock transfers between two warehouses
--   belonging to the same business.
--
-- IMPORTANT APPLICATION RULES:
--   1. Draft transfers do not affect stock.
--   2. Posting must run in one DB transaction:
--        - lock the transfer header and relevant stock rows
--        - validate source available stock
--        - insert one transfer_out ledger row per item at the source warehouse
--        - insert one transfer_in ledger row per item at the destination warehouse
--        - mark the transfer posted
--   3. Both ledger rows for an item use the same stock_transfer_item_id.
--   4. A posted transfer must never be edited or hard-deleted.
--   5. Only a draft transfer may be cancelled directly.
--   6. Reversing a posted transfer must append opposite-direction reversal
--      ledger entries and mark the header reversed, all in one transaction.
--   7. The backend must verify that transfer_out uses source_warehouse_id,
--      transfer_in uses destination_warehouse_id, and that both rows have
--      the correct product, quantity and unit cost.
--   8. The backend must validate available stock under row/advisory locking.
--
-- Run with:
--   psql -v ON_ERROR_STOP=1 ... -f 013_stock_transfer_management.sql

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Transfer header
-- ---------------------------------------------------------------------------

CREATE TABLE public.stock_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    transfer_number VARCHAR(50) NOT NULL,
    transfer_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    source_warehouse_id UUID NOT NULL,
    destination_warehouse_id UUID NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    notes TEXT,

    posted_at TIMESTAMPTZ,
    posted_by UUID,

    cancelled_at TIMESTAMPTZ,
    cancelled_by UUID,
    cancellation_reason TEXT,

    reversed_at TIMESTAMPTZ,
    reversed_by UUID,
    reversal_reason TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,

    CONSTRAINT uq_stock_transfers_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_stock_transfers_business_number
        UNIQUE (business_id, transfer_number),

    CONSTRAINT chk_stock_transfers_different_warehouses
        CHECK (source_warehouse_id <> destination_warehouse_id),

    CONSTRAINT chk_stock_transfers_status
        CHECK (status IN ('draft', 'posted', 'cancelled', 'reversed')),

    CONSTRAINT chk_stock_transfers_posted_metadata
        CHECK (
            status NOT IN ('posted', 'reversed')
            OR (posted_at IS NOT NULL AND posted_by IS NOT NULL)
        ),

    CONSTRAINT chk_stock_transfers_cancelled_metadata
        CHECK (
            status <> 'cancelled'
            OR (
                cancelled_at IS NOT NULL
                AND cancelled_by IS NOT NULL
                AND cancellation_reason IS NOT NULL
                AND length(trim(cancellation_reason)) > 0
            )
        ),

    CONSTRAINT chk_stock_transfers_reversed_metadata
        CHECK (
            status <> 'reversed'
            OR (
                reversed_at IS NOT NULL
                AND reversed_by IS NOT NULL
                AND reversal_reason IS NOT NULL
                AND length(trim(reversal_reason)) > 0
            )
        ),

    CONSTRAINT fk_stock_transfers_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_stock_transfers_source_warehouse_same_business
        FOREIGN KEY (business_id, source_warehouse_id)
        REFERENCES public.warehouses(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_stock_transfers_destination_warehouse_same_business
        FOREIGN KEY (business_id, destination_warehouse_id)
        REFERENCES public.warehouses(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_stock_transfers_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_stock_transfers_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_stock_transfers_posted_by
        FOREIGN KEY (posted_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_stock_transfers_cancelled_by
        FOREIGN KEY (cancelled_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_stock_transfers_reversed_by
        FOREIGN KEY (reversed_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL
);

CREATE INDEX idx_stock_transfers_business_date
    ON public.stock_transfers (business_id, transfer_date DESC);

CREATE INDEX idx_stock_transfers_source_status
    ON public.stock_transfers (business_id, source_warehouse_id, status);

CREATE INDEX idx_stock_transfers_destination_status
    ON public.stock_transfers (business_id, destination_warehouse_id, status);

-- ---------------------------------------------------------------------------
-- 2. Transfer items
-- ---------------------------------------------------------------------------

CREATE TABLE public.stock_transfer_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    transfer_id UUID NOT NULL,
    product_id UUID NOT NULL,
    unit_id UUID NOT NULL,

    quantity NUMERIC(14,3) NOT NULL,
    unit_cost NUMERIC(14,2) NOT NULL DEFAULT 0,
    total_cost NUMERIC(14,2) NOT NULL DEFAULT 0,

    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,

    CONSTRAINT uq_stock_transfer_items_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_stock_transfer_items_business_id_product
        UNIQUE (business_id, id, product_id),

    CONSTRAINT uq_stock_transfer_items_transfer_product
        UNIQUE (business_id, transfer_id, product_id),

    CONSTRAINT chk_stock_transfer_items_quantity
        CHECK (quantity > 0),

    CONSTRAINT chk_stock_transfer_items_unit_cost
        CHECK (unit_cost >= 0),

    CONSTRAINT chk_stock_transfer_items_total_cost
        CHECK (total_cost >= 0),

    CONSTRAINT fk_stock_transfer_items_transfer_same_business
        FOREIGN KEY (business_id, transfer_id)
        REFERENCES public.stock_transfers(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_stock_transfer_items_product_same_business
        FOREIGN KEY (business_id, product_id)
        REFERENCES public.products(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_stock_transfer_items_unit
        FOREIGN KEY (unit_id)
        REFERENCES public.units(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_stock_transfer_items_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_stock_transfer_items_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL
);

CREATE INDEX idx_stock_transfer_items_transfer
    ON public.stock_transfer_items (business_id, transfer_id);

CREATE INDEX idx_stock_transfer_items_product
    ON public.stock_transfer_items (business_id, product_id);

-- ---------------------------------------------------------------------------
-- 3. Link stock ledger movements to transfer items
-- ---------------------------------------------------------------------------

ALTER TABLE public.stock_ledger
    ADD COLUMN stock_transfer_item_id UUID;

-- Replace the original source rule so transfer movements must identify
-- their transfer item. Opening and reversal entries may remain source-less.
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
            stock_transfer_item_id
        ) = 1
        OR (
            movement_type IN (
                'opening_in',
                'opening_out',
                'reversal'
            )
            AND num_nonnulls(
                purchase_item_id,
                purchase_return_item_id,
                sale_item_id,
                sales_return_item_id,
                stock_adjustment_item_id,
                project_material_id,
                stock_transfer_item_id
            ) = 0
        )
    );

ALTER TABLE public.stock_ledger
    ADD CONSTRAINT fk_stock_ledger_transfer_item_same_business
    FOREIGN KEY (business_id, stock_transfer_item_id, product_id)
    REFERENCES public.stock_transfer_items(business_id, id, product_id)
    ON DELETE RESTRICT;

CREATE INDEX idx_stock_ledger_transfer_item
    ON public.stock_ledger (business_id, stock_transfer_item_id, movement_at)
    WHERE stock_transfer_item_id IS NOT NULL;

COMMIT;

-- ---------------------------------------------------------------------------
-- POST-MIGRATION APPLICATION VALIDATION CHECKLIST
-- ---------------------------------------------------------------------------
-- A. Before posting:
--    - header status must be draft
--    - source and destination warehouses must be active and not deleted
--    - both warehouses must belong to the header business (FK enforced)
--    - source and destination must differ (CHECK enforced)
--    - items must be inventory-tracked goods, not services
--    - product must be active and belong to the same business
--    - item quantity must be positive
--    - available source stock must be sufficient
--
-- B. Posting transaction:
--    - SELECT header FOR UPDATE
--    - lock stock balance rows in deterministic product/warehouse order
--    - insert transfer_out / OUT at source warehouse
--    - insert transfer_in / IN at destination warehouse
--    - use the same stock_transfer_item_id for both ledger rows
--    - use identical quantity, unit and valuation cost on both rows
--    - update header status='posted', posted_at, posted_by
--    - COMMIT only after every item and both ledger movements succeed
--
-- C. Reversal transaction:
--    - only a posted transfer can be reversed
--    - lock header and relevant stock balance rows
--    - append opposite-direction reversal ledger entries
--    - ensure destination has sufficient available stock to reverse
--    - set status='reversed', reversed_at, reversed_by, reversal_reason
--    - never edit/delete original ledger rows
--
-- D. The database enforces same-business references and valid movement
--    source linkage. Warehouse-side direction matching, stock sufficiency,
--    valuation and state-transition rules must be enforced by backend
--    transactional service logic.
