
-- ============================================================
-- NokshiGhor
-- Migration 042: Branch Management Foundation
-- PostgreSQL 17
--
-- Existing transaction history remains unchanged.
-- Every existing warehouse is mapped to its Business Main Branch.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Dedicated Branch Manager role
-- ------------------------------------------------------------


DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = 'nokshighor_branch_manager'
    ) THEN
        CREATE ROLE nokshighor_branch_manager
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            NOINHERIT;
    END IF;
END;
$$;

GRANT USAGE ON SCHEMA public
TO nokshighor_branch_manager;

GRANT CREATE ON SCHEMA public
TO nokshighor_branch_manager;


-- ------------------------------------------------------------
-- 2. Branches
-- ------------------------------------------------------------

CREATE TABLE public.branches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,

    branch_name VARCHAR(150) NOT NULL,
    branch_code VARCHAR(50),

    address TEXT,
    phone VARCHAR(20),
    email VARCHAR(255),

    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,

    CONSTRAINT uq_branches_business_id
        UNIQUE (business_id, id),

    CONSTRAINT fk_branches_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_branches_created_by
        FOREIGN KEY (created_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_branches_updated_by
        FOREIGN KEY (updated_by)
        REFERENCES public.users(id)
        ON DELETE SET NULL
);

CREATE UNIQUE INDEX uq_branches_name
    ON public.branches (business_id, LOWER(branch_name));

CREATE UNIQUE INDEX uq_branches_code
    ON public.branches (business_id, LOWER(branch_code))
    WHERE branch_code IS NOT NULL;

CREATE UNIQUE INDEX uq_branches_default
    ON public.branches (business_id)
    WHERE is_default = TRUE;

CREATE INDEX idx_branches_business_status
    ON public.branches (business_id, is_active);


-- ------------------------------------------------------------
-- 3. Default Main Branch for every existing Business
-- ------------------------------------------------------------

INSERT INTO public.branches (
    business_id,
    branch_name,
    branch_code,
    is_default,
    is_active
)
SELECT
    b.id,
    'Main Branch',
    'MAIN',
    TRUE,
    TRUE
FROM public.businesses b;


-- ------------------------------------------------------------
-- 4. Map existing Warehouses to Main Branch
-- ------------------------------------------------------------

ALTER TABLE public.warehouses
    ADD COLUMN branch_id UUID;

UPDATE public.warehouses w
SET branch_id = b.id
FROM public.branches b
WHERE b.business_id = w.business_id
  AND b.is_default = TRUE;

ALTER TABLE public.warehouses
    ALTER COLUMN branch_id SET NOT NULL;

ALTER TABLE public.warehouses
    ADD CONSTRAINT fk_warehouses_branch_same_business
    FOREIGN KEY (business_id, branch_id)
    REFERENCES public.branches (business_id, id)
    ON DELETE RESTRICT;

CREATE INDEX idx_warehouses_branch
    ON public.warehouses (business_id, branch_id);


-- ------------------------------------------------------------
-- 5. Branch User Assignment History
-- ------------------------------------------------------------

CREATE TABLE public.branch_user_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL,
    branch_id UUID NOT NULL,
    business_user_id UUID NOT NULL,

    assignment_type VARCHAR(30) NOT NULL
        CHECK (
            assignment_type IN (
                'branch_admin',
                'employee'
            )
        ),

    assignment_status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (
            assignment_status IN (
                'active',
                'revoked'
            )
        ),

    effective_from TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    effective_to TIMESTAMPTZ,

    assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    assigned_by UUID NOT NULL,

    revoked_at TIMESTAMPTZ,
    revoked_by UUID,
    revocation_reason TEXT,

    notes TEXT,

    CONSTRAINT uq_branch_user_assignments_business_id
        UNIQUE (business_id, id),

    CONSTRAINT fk_branch_assignment_branch
        FOREIGN KEY (business_id, branch_id)
        REFERENCES public.branches (business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_branch_assignment_business_user
        FOREIGN KEY (business_user_id, business_id)
        REFERENCES public.business_users (id, business_id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_branch_assignment_assigned_by
        FOREIGN KEY (assigned_by)
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_branch_assignment_revoked_by
        FOREIGN KEY (revoked_by)
        REFERENCES public.users(id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_branch_assignment_dates
        CHECK (
            effective_to IS NULL
            OR effective_to >= effective_from
        ),

    CONSTRAINT chk_branch_assignment_status
        CHECK (
            (
                assignment_status = 'active'
                AND revoked_at IS NULL
                AND revoked_by IS NULL
                AND effective_to IS NULL
            )
            OR
            (
                assignment_status = 'revoked'
                AND revoked_at IS NOT NULL
                AND revoked_by IS NOT NULL
                AND effective_to IS NOT NULL
            )
        )
);

CREATE UNIQUE INDEX uq_branch_assignment_active
    ON public.branch_user_assignments (
        business_id,
        branch_id,
        business_user_id,
        assignment_type
    )
    WHERE assignment_status = 'active';

CREATE INDEX idx_branch_assignment_user
    ON public.branch_user_assignments (
        business_id,
        business_user_id,
        assignment_status
    );

CREATE INDEX idx_branch_assignment_branch
    ON public.branch_user_assignments (
        business_id,
        branch_id,
        assignment_status
    );

CREATE INDEX idx_branch_assignment_history
    ON public.branch_user_assignments (
        business_id,
        business_user_id,
        effective_from DESC
    );


-- ------------------------------------------------------------
-- 6. Least-privilege permissions for Branch Manager
-- ------------------------------------------------------------

GRANT SELECT (id, status, deleted_at)
ON public.businesses
TO nokshighor_branch_manager;

GRANT SELECT (id, business_id, role_name, is_system)
ON public.roles
TO nokshighor_branch_manager;

GRANT SELECT (
    id, business_id, user_id, role_id, status
)
ON public.business_users
TO nokshighor_branch_manager;

GRANT SELECT (
    id, full_name, email, phone, status, deleted_at
)
ON public.users
TO nokshighor_branch_manager;

GRANT SELECT, INSERT, UPDATE
ON public.branches
TO nokshighor_branch_manager;

GRANT SELECT, INSERT, UPDATE
ON public.branch_user_assignments
TO nokshighor_branch_manager;

GRANT SELECT (business_id, id, branch_id, warehouse_name, is_active, deleted_at)
ON public.warehouses
TO nokshighor_branch_manager;

GRANT UPDATE (branch_id)
ON public.warehouses
TO nokshighor_branch_manager;

GRANT INSERT (
    business_id, user_id, action, table_name,
    record_id, old_values, new_values
)
ON public.audit_logs
TO nokshighor_branch_manager;


-- ------------------------------------------------------------
-- 7. Prevent hard deletion of Branch records
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_prevent_branch_hard_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Branch records cannot be deleted. Deactivate the branch instead.';
END;
$$;

CREATE TRIGGER trg_prevent_branch_hard_delete
BEFORE DELETE ON public.branches
FOR EACH ROW
EXECUTE FUNCTION public.fn_prevent_branch_hard_delete();


-- ------------------------------------------------------------
-- 8. Prevent hard deletion of assignment history
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_prevent_branch_assignment_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'Branch assignment history cannot be deleted. Revoke the assignment instead.';
END;
$$;

CREATE TRIGGER trg_prevent_branch_assignment_delete
BEFORE DELETE ON public.branch_user_assignments
FOR EACH ROW
EXECUTE FUNCTION public.fn_prevent_branch_assignment_delete();


-- ------------------------------------------------------------
-- 9. Function ownership and access
-- ------------------------------------------------------------

ALTER FUNCTION public.fn_prevent_branch_hard_delete()
OWNER TO nokshighor_branch_manager;

ALTER FUNCTION public.fn_prevent_branch_assignment_delete()
OWNER TO nokshighor_branch_manager;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_prevent_branch_hard_delete()
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_prevent_branch_assignment_delete()
FROM PUBLIC;


-- ------------------------------------------------------------
-- 10. Documentation
-- ------------------------------------------------------------

COMMENT ON TABLE public.branches IS
    'Business branches. Branches are deactivated, never hard-deleted.';

COMMENT ON COLUMN public.warehouses.branch_id IS
    'Branch owning this warehouse. Existing warehouses are mapped to Main Branch.';

COMMENT ON TABLE public.branch_user_assignments IS
    'Branch Admin and Employee assignment history. Revoked assignments are preserved.';

COMMENT ON COLUMN public.branch_user_assignments.assignment_type IS
    'Branch-level assignment type: branch_admin or employee. Owner access is Business-wide.';

COMMIT;
