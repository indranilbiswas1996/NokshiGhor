-- Migration 014: Enforce stock ledger movement-to-source mapping
-- NokshiGhor
--
-- This migration hardens the stock ledger so each movement type can reference
-- only its corresponding source record. It complements the existing
-- chk_stock_ledger_exactly_one_source constraint.
--
-- Run only after Migration 013 has been successfully applied.

BEGIN;

ALTER TABLE stock_ledger
    ADD CONSTRAINT chk_stock_ledger_movement_source_mapping
    CHECK (
        CASE movement_type
            WHEN 'purchase_in' THEN
                purchase_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_return_item_id, sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, project_material_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'purchase_return_out' THEN
                purchase_return_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, sale_item_id, sales_return_item_id,
                    stock_adjustment_item_id, project_material_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'sale_out' THEN
                sale_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sales_return_item_id,
                    stock_adjustment_item_id, project_material_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'sales_return_in' THEN
                sales_return_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    stock_adjustment_item_id, project_material_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'adjustment_in' THEN
                stock_adjustment_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, project_material_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'adjustment_out' THEN
                stock_adjustment_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, project_material_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'project_material_out' THEN
                project_material_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'project_material_return_in' THEN
                project_material_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    stock_transfer_item_id
                ) = 0

            WHEN 'transfer_out' THEN
                stock_transfer_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    project_material_id
                ) = 0

            WHEN 'transfer_in' THEN
                stock_transfer_item_id IS NOT NULL
                AND num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    project_material_id
                ) = 0

            WHEN 'opening_in' THEN
                num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    project_material_id, stock_transfer_item_id
                ) = 0

            WHEN 'opening_out' THEN
                num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    project_material_id, stock_transfer_item_id
                ) = 0

            WHEN 'reversal' THEN
                num_nonnulls(
                    purchase_item_id, purchase_return_item_id, sale_item_id,
                    sales_return_item_id, stock_adjustment_item_id,
                    project_material_id, stock_transfer_item_id
                ) = 0

            ELSE FALSE
        END
    );

COMMENT ON CONSTRAINT chk_stock_ledger_movement_source_mapping
ON stock_ledger IS
'Ensures each stock movement type references only its corresponding source record. Opening and reversal entries are source-less and use the reversal relationship where applicable.';

COMMIT;
