BEGIN;

-- ============================================
-- NOKSHIGHOR
-- MIGRATION 015: BUSINESS-SCOPED ROLES AND UNITS
-- PostgreSQL 17
--
-- Goals:
-- 1. Keep standard units global.
-- 2. Support business-specific custom units.
-- 3. Keep system roles global.
-- 4. Support business-specific custom roles.
-- 5. Enforce role/unit access using composite foreign keys.
-- 6. Provision global role/unit access automatically for new businesses.
-- 7. Preserve all existing unit IDs and data.
-- ============================================


-- =========================================================
-- 1. ROLE OWNERSHIP
-- =========================================================

ALTER TABLE roles
    ADD COLUMN business_id UUID,
    ADD COLUMN is_system BOOLEAN NOT NULL DEFAULT TRUE,
    ADD CONSTRAINT fk_roles_business
        FOREIGN KEY (business_id)
        REFERENCES businesses(id)
        ON DELETE RESTRICT,
    ADD CONSTRAINT chk_roles_system_scope
        CHECK ((business_id IS NULL) = is_system),
    ADD CONSTRAINT uq_roles_business_id_id
        UNIQUE (business_id, id);

-- Global roles have business_id IS NULL and is_system = TRUE.
-- Custom roles belong to exactly one business and is_system = FALSE.

ALTER TABLE roles
    DROP CONSTRAINT roles_role_name_key;

CREATE UNIQUE INDEX uq_roles_global_name
    ON roles (LOWER(role_name))
    WHERE business_id IS NULL;

CREATE UNIQUE INDEX uq_roles_business_name
    ON roles (business_id, LOWER(role_name))
    WHERE business_id IS NOT NULL;

CREATE INDEX idx_roles_business
    ON roles (business_id);

-- Role ownership is immutable. Moving a role between global and
-- business scope would invalidate existing access assignments.
CREATE OR REPLACE FUNCTION fn_prevent_role_scope_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.business_id IS DISTINCT FROM OLD.business_id THEN
        RAISE EXCEPTION 'Role ownership cannot be changed after creation'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_role_scope_change
BEFORE UPDATE OF business_id ON roles
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_role_scope_change();


-- =========================================================
-- 2. UNIT OWNERSHIP
-- =========================================================

ALTER TABLE units
    ADD COLUMN business_id UUID,
    ADD CONSTRAINT fk_units_business
        FOREIGN KEY (business_id)
        REFERENCES businesses(id)
        ON DELETE RESTRICT,
    ADD CONSTRAINT uq_units_business_id_id
        UNIQUE (business_id, id);

-- Existing 13 units remain global (business_id IS NULL).
-- New custom units must set business_id to their owning business.

ALTER TABLE units
    DROP CONSTRAINT units_unit_code_key;

CREATE UNIQUE INDEX uq_units_global_code
    ON units (LOWER(unit_code))
    WHERE business_id IS NULL;

CREATE UNIQUE INDEX uq_units_business_code
    ON units (business_id, LOWER(unit_code))
    WHERE business_id IS NOT NULL;

CREATE INDEX idx_units_business
    ON units (business_id);

-- Unit ownership is immutable for the same reason as role ownership.
CREATE OR REPLACE FUNCTION fn_prevent_unit_scope_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.business_id IS DISTINCT FROM OLD.business_id THEN
        RAISE EXCEPTION 'Unit ownership cannot be changed after creation'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_prevent_unit_scope_change
BEFORE UPDATE OF business_id ON units
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_unit_scope_change();


-- =========================================================
-- 3. BUSINESS ROLE ACCESS
-- =========================================================

CREATE TABLE business_role_access (
    business_id UUID NOT NULL,
    role_id UUID NOT NULL,

    -- NULL means a global system role.
    -- For a custom role this must equal business_id.
    role_owner_business_id UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    CONSTRAINT pk_business_role_access
        PRIMARY KEY (business_id, role_id),

    CONSTRAINT fk_business_role_access_business
        FOREIGN KEY (business_id)
        REFERENCES businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_business_role_access_role
        FOREIGN KEY (role_id)
        REFERENCES roles(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_business_role_access_role_owner
        FOREIGN KEY (role_owner_business_id, role_id)
        REFERENCES roles (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_business_role_access_owner
        CHECK (
            role_owner_business_id IS NULL
            OR role_owner_business_id = business_id
        )
);

CREATE INDEX idx_business_role_access_role
    ON business_role_access (role_id);


-- =========================================================
-- 4. BUSINESS UNIT ACCESS
-- =========================================================

CREATE TABLE business_unit_access (
    business_id UUID NOT NULL,
    unit_id UUID NOT NULL,

    -- NULL means a global standard unit.
    -- For a custom unit this must equal business_id.
    unit_owner_business_id UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    CONSTRAINT pk_business_unit_access
        PRIMARY KEY (business_id, unit_id),

    CONSTRAINT fk_business_unit_access_business
        FOREIGN KEY (business_id)
        REFERENCES businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_business_unit_access_unit
        FOREIGN KEY (unit_id)
        REFERENCES units(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_business_unit_access_unit_owner
        FOREIGN KEY (unit_owner_business_id, unit_id)
        REFERENCES units (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_business_unit_access_owner
        CHECK (
            unit_owner_business_id IS NULL
            OR unit_owner_business_id = business_id
        )
);

CREATE INDEX idx_business_unit_access_unit
    ON business_unit_access (unit_id);


-- =========================================================
-- 5. DATABASE-LEVEL OWNER VALIDATION
--
-- The composite owner FK validates custom ownership.
-- These triggers additionally validate the NULL/global case,
-- because PostgreSQL MATCH SIMPLE skips a composite FK when
-- one of its referencing columns is NULL.
-- =========================================================

CREATE OR REPLACE FUNCTION fn_validate_business_role_access_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_role_owner UUID;
BEGIN
    SELECT business_id
      INTO v_role_owner
      FROM roles
     WHERE id = NEW.role_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Role % does not exist', NEW.role_id
            USING ERRCODE = '23503';
    END IF;

    IF v_role_owner IS DISTINCT FROM NEW.role_owner_business_id THEN
        RAISE EXCEPTION
            'Role % ownership does not match the supplied role owner',
            NEW.role_id
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_business_role_access_owner
BEFORE INSERT OR UPDATE OF business_id, role_id, role_owner_business_id
ON business_role_access
FOR EACH ROW
EXECUTE FUNCTION fn_validate_business_role_access_owner();


CREATE OR REPLACE FUNCTION fn_validate_business_unit_access_owner()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_unit_owner UUID;
BEGIN
    SELECT business_id
      INTO v_unit_owner
      FROM units
     WHERE id = NEW.unit_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unit % does not exist', NEW.unit_id
            USING ERRCODE = '23503';
    END IF;

    IF v_unit_owner IS DISTINCT FROM NEW.unit_owner_business_id THEN
        RAISE EXCEPTION
            'Unit % ownership does not match the supplied unit owner',
            NEW.unit_id
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_business_unit_access_owner
BEFORE INSERT OR UPDATE OF business_id, unit_id, unit_owner_business_id
ON business_unit_access
FOR EACH ROW
EXECUTE FUNCTION fn_validate_business_unit_access_owner();


-- =========================================================
-- 6. AUTOMATIC ACCESS PROVISIONING
-- =========================================================

CREATE OR REPLACE FUNCTION fn_provision_business_global_access()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO business_role_access
        (business_id, role_id, role_owner_business_id)
    SELECT NEW.id, r.id, r.business_id
      FROM roles r
     WHERE r.business_id IS NULL
    ON CONFLICT (business_id, role_id) DO NOTHING;

    INSERT INTO business_unit_access
        (business_id, unit_id, unit_owner_business_id)
    SELECT NEW.id, u.id, u.business_id
      FROM units u
     WHERE u.business_id IS NULL
    ON CONFLICT (business_id, unit_id) DO NOTHING;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_business_provision_global_access
AFTER INSERT ON businesses
FOR EACH ROW
EXECUTE FUNCTION fn_provision_business_global_access();


CREATE OR REPLACE FUNCTION fn_provision_role_access()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.business_id IS NULL THEN
        -- A new global role is available to every existing business.
        INSERT INTO business_role_access
            (business_id, role_id, role_owner_business_id)
        SELECT b.id, NEW.id, NEW.business_id
          FROM businesses b
        ON CONFLICT (business_id, role_id) DO NOTHING;
    ELSE
        -- A custom role is available only to its owning business.
        INSERT INTO business_role_access
            (business_id, role_id, role_owner_business_id)
        VALUES (NEW.business_id, NEW.id, NEW.business_id)
        ON CONFLICT (business_id, role_id) DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_role_provision_business_access
AFTER INSERT ON roles
FOR EACH ROW
EXECUTE FUNCTION fn_provision_role_access();


CREATE OR REPLACE FUNCTION fn_provision_unit_access()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.business_id IS NULL THEN
        -- A new global standard unit is available to every business.
        INSERT INTO business_unit_access
            (business_id, unit_id, unit_owner_business_id)
        SELECT b.id, NEW.id, NEW.business_id
          FROM businesses b
        ON CONFLICT (business_id, unit_id) DO NOTHING;
    ELSE
        -- A custom unit is available only to its owning business.
        INSERT INTO business_unit_access
            (business_id, unit_id, unit_owner_business_id)
        VALUES (NEW.business_id, NEW.id, NEW.business_id)
        ON CONFLICT (business_id, unit_id) DO NOTHING;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_unit_provision_business_access
AFTER INSERT ON units
FOR EACH ROW
EXECUTE FUNCTION fn_provision_unit_access();


-- =========================================================
-- 7. BACKFILL ACCESS FOR EXISTING BUSINESSES
-- =========================================================

INSERT INTO business_role_access
    (business_id, role_id, role_owner_business_id)
SELECT b.id, r.id, r.business_id
  FROM businesses b
 CROSS JOIN roles r
 WHERE r.business_id IS NULL
    OR r.business_id = b.id
ON CONFLICT (business_id, role_id) DO NOTHING;

INSERT INTO business_unit_access
    (business_id, unit_id, unit_owner_business_id)
SELECT b.id, u.id, u.business_id
  FROM businesses b
 CROSS JOIN units u
 WHERE u.business_id IS NULL
    OR u.business_id = b.id
ON CONFLICT (business_id, unit_id) DO NOTHING;


-- =========================================================
-- 8. ENFORCE BUSINESS-SCOPED ROLE ASSIGNMENT
-- =========================================================

ALTER TABLE business_users
    DROP CONSTRAINT business_users_role_id_fkey;

ALTER TABLE business_users
    ADD CONSTRAINT fk_business_users_role_access
        FOREIGN KEY (business_id, role_id)
        REFERENCES business_role_access (business_id, role_id)
        ON DELETE RESTRICT;

CREATE INDEX idx_business_users_business_role
    ON business_users (business_id, role_id);


-- =========================================================
-- 9. ENFORCE BUSINESS-SCOPED UNIT USAGE
-- =========================================================

ALTER TABLE products
    DROP CONSTRAINT products_unit_id_fkey,
    ADD CONSTRAINT fk_products_business_unit_access
        FOREIGN KEY (business_id, unit_id)
        REFERENCES business_unit_access (business_id, unit_id)
        ON DELETE RESTRICT;

ALTER TABLE purchase_items
    DROP CONSTRAINT purchase_items_unit_id_fkey,
    ADD CONSTRAINT fk_purchase_items_business_unit_access
        FOREIGN KEY (business_id, unit_id)
        REFERENCES business_unit_access (business_id, unit_id)
        ON DELETE RESTRICT;

ALTER TABLE sale_items
    DROP CONSTRAINT sale_items_unit_id_fkey,
    ADD CONSTRAINT fk_sale_items_business_unit_access
        FOREIGN KEY (business_id, unit_id)
        REFERENCES business_unit_access (business_id, unit_id)
        ON DELETE RESTRICT;

ALTER TABLE sales_return_items
    DROP CONSTRAINT sales_return_items_unit_id_fkey,
    ADD CONSTRAINT fk_sales_return_items_business_unit_access
        FOREIGN KEY (business_id, unit_id)
        REFERENCES business_unit_access (business_id, unit_id)
        ON DELETE RESTRICT;

ALTER TABLE stock_adjustment_items
    DROP CONSTRAINT stock_adjustment_items_unit_id_fkey,
    ADD CONSTRAINT fk_stock_adjustment_items_business_unit_access
        FOREIGN KEY (business_id, unit_id)
        REFERENCES business_unit_access (business_id, unit_id)
        ON DELETE RESTRICT;

ALTER TABLE stock_ledger
    DROP CONSTRAINT stock_ledger_unit_id_fkey,
    ADD CONSTRAINT fk_stock_ledger_business_unit_access
        FOREIGN KEY (business_id, unit_id)
        REFERENCES business_unit_access (business_id, unit_id)
        ON DELETE RESTRICT;

ALTER TABLE stock_transfer_items
    DROP CONSTRAINT fk_stock_transfer_items_unit,
    ADD CONSTRAINT fk_stock_transfer_items_business_unit_access
        FOREIGN KEY (business_id, unit_id)
        REFERENCES business_unit_access (business_id, unit_id)
        ON DELETE RESTRICT;


-- Supporting indexes for business/unit lookup and FK maintenance.
CREATE INDEX idx_products_business_unit
    ON products (business_id, unit_id);

CREATE INDEX idx_purchase_items_business_unit
    ON purchase_items (business_id, unit_id);

CREATE INDEX idx_sale_items_business_unit
    ON sale_items (business_id, unit_id);

CREATE INDEX idx_sales_return_items_business_unit
    ON sales_return_items (business_id, unit_id);

CREATE INDEX idx_stock_adjustment_items_business_unit
    ON stock_adjustment_items (business_id, unit_id);

CREATE INDEX idx_stock_ledger_business_unit
    ON stock_ledger (business_id, unit_id);

CREATE INDEX idx_stock_transfer_items_business_unit
    ON stock_transfer_items (business_id, unit_id);


COMMIT;
