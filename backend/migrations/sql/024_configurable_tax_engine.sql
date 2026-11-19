
-- ============================================================
-- NokshiGhor Migration 024
-- Configurable, Versioned and Scheduled Tax Engine
-- PostgreSQL 17
--
-- IMPORTANT:
-- This migration creates the tax-engine foundation only.
-- Existing product.tax_rate and sale_items tax fields remain
-- unchanged for backward compatibility.
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. TAX TYPES
-- ------------------------------------------------------------

CREATE TABLE public.tax_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    tax_code VARCHAR(40) NOT NULL,
    tax_name VARCHAR(120) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_tax_types_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_tax_types_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_tax_types_code
        UNIQUE (business_id, tax_code)
);

-- ------------------------------------------------------------
-- 2. TAX COMPONENTS
-- ------------------------------------------------------------

CREATE TABLE public.tax_components (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    component_code VARCHAR(40) NOT NULL,
    component_name VARCHAR(120) NOT NULL,
    jurisdiction_level VARCHAR(30) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_tax_components_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_tax_components_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_tax_components_code
        UNIQUE (business_id, component_code),

    CONSTRAINT chk_tax_component_jurisdiction
        CHECK (
            jurisdiction_level IN (
                'central',
                'state',
                'integrated',
                'local',
                'other'
            )
        )
);

-- ------------------------------------------------------------
-- 3. TAX PROFILES
-- Stable logical identity of a tax profile.
-- Actual tax configuration is stored in immutable versions.
-- ------------------------------------------------------------

CREATE TABLE public.tax_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    profile_code VARCHAR(60) NOT NULL,
    profile_name VARCHAR(150) NOT NULL,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,
    deleted_at TIMESTAMPTZ,

    CONSTRAINT fk_tax_profiles_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_tax_profiles_business_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_tax_profiles_code
        UNIQUE (business_id, profile_code)
);

-- ------------------------------------------------------------
-- 4. TAX PROFILE VERSIONS
-- Each legal/configuration change gets a new version.
-- ------------------------------------------------------------

CREATE TABLE public.tax_profile_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    tax_profile_id UUID NOT NULL,
    version_number INTEGER NOT NULL,
    tax_type_id UUID NOT NULL,

    calculation_mode VARCHAR(20) NOT NULL DEFAULT 'exclusive',
    rounding_mode VARCHAR(30) NOT NULL DEFAULT 'half_up',
    rounding_precision SMALLINT NOT NULL DEFAULT 2,

    effective_from TIMESTAMPTZ,
    effective_to TIMESTAMPTZ,

    version_status VARCHAR(20) NOT NULL DEFAULT 'draft',
    version_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,

    CONSTRAINT fk_tax_version_profile
        FOREIGN KEY (business_id, tax_profile_id)
        REFERENCES public.tax_profiles(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_tax_version_type
        FOREIGN KEY (business_id, tax_type_id)
        REFERENCES public.tax_types(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_tax_profile_version
        UNIQUE (business_id, tax_profile_id, version_number),

    CONSTRAINT uq_tax_profile_version_id
        UNIQUE (business_id, id),

    CONSTRAINT chk_tax_version_number
        CHECK (version_number > 0),

    CONSTRAINT chk_tax_calculation_mode
        CHECK (calculation_mode IN ('exclusive', 'inclusive')),

    CONSTRAINT chk_tax_rounding_mode
        CHECK (
            rounding_mode IN (
                'half_up',
                'half_even',
                'down',
                'up'
            )
        ),

    CONSTRAINT chk_tax_rounding_precision
        CHECK (rounding_precision BETWEEN 0 AND 4),

    CONSTRAINT chk_tax_version_status
        CHECK (
            version_status IN (
                'draft',
                'scheduled',
                'active',
                'retired',
                'cancelled'
            )
        ),

    CONSTRAINT chk_tax_version_period
        CHECK (
            effective_to IS NULL
            OR effective_from IS NULL
            OR effective_to > effective_from
        )
);

-- ------------------------------------------------------------
-- 5. TAX PROFILE VERSION COMPONENTS
-- Names and codes are snapshotted so later component renaming
-- cannot change historical profile configuration.
-- ------------------------------------------------------------

CREATE TABLE public.tax_profile_version_components (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    tax_profile_version_id UUID NOT NULL,
    tax_component_id UUID NOT NULL,

    component_code_snapshot VARCHAR(40) NOT NULL,
    component_name_snapshot VARCHAR(120) NOT NULL,
    jurisdiction_snapshot VARCHAR(30) NOT NULL,

    tax_rate NUMERIC(7,4) NOT NULL,
    calculation_order SMALLINT NOT NULL DEFAULT 1,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,

    CONSTRAINT fk_tax_version_component_version
        FOREIGN KEY (business_id, tax_profile_version_id)
        REFERENCES public.tax_profile_versions(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_tax_version_component_master
        FOREIGN KEY (business_id, tax_component_id)
        REFERENCES public.tax_components(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_tax_version_component_order
        UNIQUE (
            business_id,
            tax_profile_version_id,
            calculation_order
        ),

    CONSTRAINT chk_tax_component_rate
        CHECK (tax_rate BETWEEN 0 AND 100),

    CONSTRAINT chk_tax_component_order
        CHECK (calculation_order > 0)
);

-- ------------------------------------------------------------
-- 6. TAX MAPPING RULE SETS
-- A rule set represents one complete version of product tax
-- mapping. New mapping changes create a new rule set.
-- ------------------------------------------------------------

CREATE TABLE public.tax_mapping_rule_sets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    rule_set_code VARCHAR(60) NOT NULL,
    version_number INTEGER NOT NULL,

    rule_set_status VARCHAR(20) NOT NULL DEFAULT 'draft',

    effective_from TIMESTAMPTZ,
    effective_to TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,

    CONSTRAINT fk_tax_rule_set_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_tax_rule_set_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_tax_rule_set_version
        UNIQUE (business_id, rule_set_code, version_number),

    CONSTRAINT chk_tax_rule_set_version
        CHECK (version_number > 0),

    CONSTRAINT chk_tax_rule_set_status
        CHECK (
            rule_set_status IN (
                'draft',
                'scheduled',
                'active',
                'retired',
                'cancelled'
            )
        ),

    CONSTRAINT chk_tax_rule_set_period
        CHECK (
            effective_to IS NULL
            OR effective_from IS NULL
            OR effective_to > effective_from
        )
);

-- ------------------------------------------------------------
-- 7. TAX MAPPING RULES
--
-- Priority:
-- 1 = product
-- 2 = HSN/SAC
-- 3 = subcategory
-- 4 = category
-- 5 = business default
--
-- Conflicts at the same priority must be detected by the
-- future Tax Resolver. This table does not silently choose.
-- ------------------------------------------------------------

CREATE TABLE public.tax_mapping_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    rule_set_id UUID NOT NULL,
    tax_profile_version_id UUID NOT NULL,

    match_scope VARCHAR(30) NOT NULL,

    product_id UUID,
    hsn_sac_code VARCHAR(20),
    category_id UUID,

    priority SMALLINT GENERATED ALWAYS AS (
        CASE match_scope
            WHEN 'product' THEN 1
            WHEN 'hsn_sac' THEN 2
            WHEN 'subcategory' THEN 3
            WHEN 'category' THEN 4
            WHEN 'business_default' THEN 5
        END
    ) STORED,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,

    CONSTRAINT uq_tax_mapping_rules_business_id
    UNIQUE (business_id, id),
    CONSTRAINT fk_tax_rule_set
        FOREIGN KEY (business_id, rule_set_id)
        REFERENCES public.tax_mapping_rule_sets(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_tax_rule_profile_version
        FOREIGN KEY (business_id, tax_profile_version_id)
        REFERENCES public.tax_profile_versions(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_tax_rule_product
        FOREIGN KEY (business_id, product_id)
        REFERENCES public.products(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_tax_rule_category
        FOREIGN KEY (business_id, category_id)
        REFERENCES public.categories(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_tax_mapping_scope
        CHECK (
            match_scope IN (
                'product',
                'hsn_sac',
                'subcategory',
                'category',
                'business_default'
            )
        ),

    CONSTRAINT chk_tax_mapping_target
        CHECK (
            (
                match_scope = 'product'
                AND product_id IS NOT NULL
                AND hsn_sac_code IS NULL
                AND category_id IS NULL
            )
            OR
            (
                match_scope = 'hsn_sac'
                AND product_id IS NULL
                AND hsn_sac_code IS NOT NULL
                AND category_id IS NULL
            )
            OR
            (
                match_scope IN ('category', 'subcategory')
                AND product_id IS NULL
                AND hsn_sac_code IS NULL
                AND category_id IS NOT NULL
            )
            OR
            (
                match_scope = 'business_default'
                AND product_id IS NULL
                AND hsn_sac_code IS NULL
                AND category_id IS NULL
            )
        )
);

CREATE INDEX idx_tax_mapping_rules_lookup
ON public.tax_mapping_rules (
    business_id,
    rule_set_id,
    priority
)
WHERE is_active = TRUE;

CREATE INDEX idx_tax_mapping_rules_product
ON public.tax_mapping_rules (
    business_id,
    rule_set_id,
    product_id
)
WHERE match_scope = 'product' AND is_active = TRUE;

CREATE INDEX idx_tax_mapping_rules_hsn
ON public.tax_mapping_rules (
    business_id,
    rule_set_id,
    hsn_sac_code
)
WHERE match_scope = 'hsn_sac' AND is_active = TRUE;

CREATE INDEX idx_tax_mapping_rules_category
ON public.tax_mapping_rules (
    business_id,
    rule_set_id,
    category_id
)
WHERE match_scope IN ('category', 'subcategory')
AND is_active = TRUE;

-- ------------------------------------------------------------
-- 8. TAX SCHEDULES
-- Schedules are stored in UTC as TIMESTAMPTZ.
-- timezone_name preserves the intended local timezone.
-- Transaction-time resolution will use effective_at even if
-- the activation worker was offline at the scheduled time.
-- ------------------------------------------------------------

CREATE TABLE public.tax_schedules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    rule_set_id UUID NOT NULL,

    effective_at TIMESTAMPTZ NOT NULL,
    timezone_name VARCHAR(64) NOT NULL DEFAULT 'Asia/Kolkata',

    schedule_status VARCHAR(20) NOT NULL DEFAULT 'pending',

    scheduled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    scheduled_by UUID,

    activated_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancelled_by UUID,

    last_error TEXT,

    CONSTRAINT fk_tax_schedule_rule_set
        FOREIGN KEY (business_id, rule_set_id)
        REFERENCES public.tax_mapping_rule_sets(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT uq_tax_schedule_id
        UNIQUE (business_id, id),

    CONSTRAINT uq_tax_schedule_rule_set
        UNIQUE (business_id, rule_set_id),

    CONSTRAINT chk_tax_schedule_status
        CHECK (
            schedule_status IN (
                'pending',
                'activated',
                'cancelled',
                'failed'
            )
        )
);

CREATE INDEX idx_tax_schedules_pending
ON public.tax_schedules (effective_at)
WHERE schedule_status = 'pending';

-- ------------------------------------------------------------
-- 9. TAX ACTIVATION LOGS
-- ------------------------------------------------------------

CREATE TABLE public.tax_activation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,
    schedule_id UUID NOT NULL,

    action VARCHAR(30) NOT NULL,
    activation_status VARCHAR(20) NOT NULL,

    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ,

    error_message TEXT,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT fk_tax_activation_schedule
        FOREIGN KEY (business_id, schedule_id)
        REFERENCES public.tax_schedules(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_tax_activation_action
        CHECK (
            action IN (
                'activate',
                'cancel',
                'retry',
                'reconcile'
            )
        ),

    CONSTRAINT chk_tax_activation_status
        CHECK (
            activation_status IN (
                'success',
                'failed',
                'skipped'
            )
        )
);

CREATE INDEX idx_tax_activation_logs_schedule
ON public.tax_activation_logs (
    business_id,
    schedule_id,
    attempted_at DESC
);

-- ------------------------------------------------------------
-- 10. SALE ITEM TAX DETAILS
-- Immutable tax component snapshots for invoice history.
-- Existing sale_items tax_rate/tax_amount are retained.
-- ------------------------------------------------------------

CREATE TABLE public.sale_item_tax_details (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,

    sale_id UUID NOT NULL,
    sale_item_id UUID NOT NULL,
    product_id UUID,

    tax_profile_id UUID,
    tax_profile_version_id UUID,
    tax_rule_set_id UUID,
    tax_mapping_rule_id UUID,

    profile_code_snapshot VARCHAR(60),
    profile_name_snapshot VARCHAR(150),
    profile_version_snapshot INTEGER,

    tax_type_code_snapshot VARCHAR(40) NOT NULL,
    tax_type_name_snapshot VARCHAR(120) NOT NULL,

    component_code_snapshot VARCHAR(40) NOT NULL,
    component_name_snapshot VARCHAR(120) NOT NULL,
    jurisdiction_snapshot VARCHAR(30) NOT NULL,

    taxable_amount NUMERIC(14,2) NOT NULL,
    tax_rate NUMERIC(7,4) NOT NULL,
    tax_amount NUMERIC(14,2) NOT NULL,

    calculation_order SMALLINT NOT NULL DEFAULT 1,

    calculation_mode_snapshot VARCHAR(20) NOT NULL,
    effective_at_snapshot TIMESTAMPTZ NOT NULL,
    timezone_snapshot VARCHAR(64) NOT NULL DEFAULT 'Asia/Kolkata',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,

    CONSTRAINT fk_sale_tax_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_sale_tax_product
        FOREIGN KEY (business_id, product_id)
        REFERENCES public.products(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_sale_tax_profile
        FOREIGN KEY (business_id, tax_profile_id)
        REFERENCES public.tax_profiles(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_sale_tax_profile_version
        FOREIGN KEY (business_id, tax_profile_version_id)
        REFERENCES public.tax_profile_versions(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_sale_tax_rule_set
        FOREIGN KEY (business_id, tax_rule_set_id)
        REFERENCES public.tax_mapping_rule_sets(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_sale_tax_mapping_rule
        FOREIGN KEY (business_id, tax_mapping_rule_id)
        REFERENCES public.tax_mapping_rules(business_id, id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_sale_tax_amounts
        CHECK (
            taxable_amount >= 0
            AND tax_rate BETWEEN 0 AND 100
            AND tax_amount >= 0
        ),

    CONSTRAINT chk_sale_tax_calculation_mode
        CHECK (
            calculation_mode_snapshot IN (
                'exclusive',
                'inclusive'
            )
        ),

    CONSTRAINT chk_sale_tax_order
        CHECK (calculation_order > 0)
);

CREATE INDEX idx_sale_item_tax_details_sale
ON public.sale_item_tax_details (
    business_id,
    sale_id,
    sale_item_id
);

CREATE INDEX idx_sale_item_tax_details_profile
ON public.sale_item_tax_details (
    business_id,
    tax_profile_version_id
);

-- ------------------------------------------------------------
-- 11. TAX AUDIT LOG
-- ------------------------------------------------------------

CREATE TABLE public.tax_audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    business_id UUID NOT NULL,

    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID NOT NULL,
    action VARCHAR(40) NOT NULL,

    old_values JSONB,
    new_values JSONB,

    changed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    changed_by UUID,

    source VARCHAR(30) NOT NULL DEFAULT 'application',
    remarks TEXT,

    CONSTRAINT fk_tax_audit_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT chk_tax_audit_source
        CHECK (
            source IN (
                'application',
                'scheduler',
                'migration',
                'system'
            )
        )
);

CREATE INDEX idx_tax_audit_entity
ON public.tax_audit_logs (
    business_id,
    entity_type,
    entity_id,
    changed_at DESC
);

CREATE INDEX idx_tax_audit_changed_at
ON public.tax_audit_logs (
    business_id,
    changed_at DESC
);

-- ------------------------------------------------------------
-- 12. TIMEZONE CONFIGURATION
-- Business timezone will be configurable.
-- Default is Asia/Kolkata.
-- ------------------------------------------------------------

CREATE TABLE public.business_tax_settings (
    business_id UUID PRIMARY KEY,

    timezone_name VARCHAR(64) NOT NULL DEFAULT 'Asia/Kolkata',

    default_tax_profile_version_id UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by UUID,
    updated_at TIMESTAMPTZ,
    updated_by UUID,

    CONSTRAINT fk_business_tax_settings_business
        FOREIGN KEY (business_id)
        REFERENCES public.businesses(id)
        ON DELETE RESTRICT,

    CONSTRAINT fk_business_tax_default_profile
        FOREIGN KEY (business_id, default_tax_profile_version_id)
        REFERENCES public.tax_profile_versions(business_id, id)
        ON DELETE RESTRICT
);

-- ------------------------------------------------------------
-- 13. COMMENTS
-- ------------------------------------------------------------

COMMENT ON TABLE public.tax_profiles IS
'Stable business-specific tax profile identities. Configuration is versioned separately.';

COMMENT ON TABLE public.tax_profile_versions IS
'Versioned tax configurations with effective periods and status.';

COMMENT ON TABLE public.tax_mapping_rule_sets IS
'Versioned sets of product-to-tax-profile mapping rules.';

COMMENT ON TABLE public.tax_mapping_rules IS
'Product, HSN/SAC, category, subcategory and business-default mapping rules.';

COMMENT ON TABLE public.tax_schedules IS
'Future-dated tax mapping activation schedules.';

COMMENT ON TABLE public.sale_item_tax_details IS
'Component-level tax snapshots retained for historical invoice accuracy.';

COMMENT ON TABLE public.tax_activation_logs IS
'Idempotent scheduler and activation processing history.';

COMMENT ON TABLE public.tax_audit_logs IS
'Audit history for tax configuration and mapping changes.';


-- ============================================================
-- MIGRATION 024 - FINAL CONSTRAINT HARDENING
-- ============================================================

-- 1. Each tax snapshot must reference its exact sale.
ALTER TABLE public.sale_item_tax_details
    ALTER COLUMN product_id SET NOT NULL;

ALTER TABLE public.sale_item_tax_details
    ADD CONSTRAINT fk_sale_tax_details_sale
    FOREIGN KEY (business_id, sale_id)
    REFERENCES public.sales (business_id, id)
    ON DELETE RESTRICT;

-- 2. Each tax snapshot must reference its exact sale item
-- and matching product within the same business and sale.
ALTER TABLE public.sale_item_tax_details
    ADD CONSTRAINT fk_sale_tax_details_sale_item
    FOREIGN KEY (business_id, sale_id, sale_item_id, product_id)
    REFERENCES public.sale_items (business_id, sale_id, id, product_id)
    ON DELETE RESTRICT;

-- 3. Prevent duplicate product-specific rules.
CREATE UNIQUE INDEX uq_tax_rule_product_target
ON public.tax_mapping_rules (
    business_id,
    rule_set_id,
    product_id
)
WHERE match_scope = 'product' AND is_active = TRUE;

-- 4. Prevent duplicate HSN/SAC rules for the same code.
CREATE UNIQUE INDEX uq_tax_rule_hsn_target
ON public.tax_mapping_rules (
    business_id,
    rule_set_id,
    upper(trim(hsn_sac_code))
)
WHERE match_scope = 'hsn_sac' AND is_active = TRUE;

-- 5. Prevent duplicate category rules at the same scope.
CREATE UNIQUE INDEX uq_tax_rule_category_target
ON public.tax_mapping_rules (
    business_id,
    rule_set_id,
    match_scope,
    category_id
)
WHERE match_scope IN ('category', 'subcategory')
AND is_active = TRUE;

-- 6. Only one active business-default rule per rule set.
CREATE UNIQUE INDEX uq_tax_rule_business_default
ON public.tax_mapping_rules (
    business_id,
    rule_set_id
)
WHERE match_scope = 'business_default'
AND is_active = TRUE;

-- 7. Validate category/subcategory hierarchy.
CREATE OR REPLACE FUNCTION public.fn_validate_tax_category_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_parent_id UUID;
BEGIN
    IF NEW.match_scope NOT IN ('category', 'subcategory') THEN
        RETURN NEW;
    END IF;

    SELECT c.parent_id
    INTO v_parent_id
    FROM public.categories c
    WHERE c.business_id = NEW.business_id
      AND c.id = NEW.category_id
      AND c.deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'Tax mapping category does not exist or is deleted';
    END IF;

    IF NEW.match_scope = 'category' AND v_parent_id IS NOT NULL THEN
        RAISE EXCEPTION
            'Category rule requires a root category';
    END IF;

    IF NEW.match_scope = 'subcategory' AND v_parent_id IS NULL THEN
        RAISE EXCEPTION
            'Subcategory rule requires a child category';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_tax_category_scope
BEFORE INSERT OR UPDATE OF
    business_id,
    category_id,
    match_scope
ON public.tax_mapping_rules
FOR EACH ROW
EXECUTE FUNCTION public.fn_validate_tax_category_scope();

-- 8. Lookup index for effective tax profile versions.
CREATE INDEX idx_tax_profile_versions_effective
ON public.tax_profile_versions (
    business_id,
    tax_profile_id,
    effective_from,
    effective_to
);

-- 9. Lookup index for active mapping rule sets.
CREATE INDEX idx_tax_rule_sets_effective
ON public.tax_mapping_rule_sets (
    business_id,
    effective_from,
    effective_to
);

-- 10. Audit index for tax schedule processing.
CREATE INDEX idx_tax_schedules_business_status_time
ON public.tax_schedules (
    business_id,
    schedule_status,
    effective_at
);

-- ============================================================
-- END FINAL CONSTRAINT HARDENING
-- ============================================================

-- 11. Ensure profile ID and version ID always match.
ALTER TABLE public.tax_profile_versions
    ADD CONSTRAINT uq_tax_profile_version_profile_reference
    UNIQUE (business_id, id, tax_profile_id);

ALTER TABLE public.sale_item_tax_details
    ADD CONSTRAINT fk_sale_tax_profile_version_consistency
    FOREIGN KEY (
        business_id,
        tax_profile_version_id,
        tax_profile_id
    )
    REFERENCES public.tax_profile_versions (
        business_id,
        id,
        tax_profile_id
    )
    ON DELETE RESTRICT;

-- 12. Historical invoice tax snapshots are append-only.
CREATE OR REPLACE FUNCTION public.fn_prevent_tax_snapshot_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $$
BEGIN
    RAISE EXCEPTION
        'Historical tax snapshots cannot be updated or deleted. Use a correction or reversal record.';
END;
$$;

CREATE TRIGGER trg_sale_item_tax_details_immutable
BEFORE UPDATE OR DELETE
ON public.sale_item_tax_details
FOR EACH ROW
EXECUTE FUNCTION public.fn_prevent_tax_snapshot_mutation();

-- 13. Prevent duplicate successful activation records.
CREATE UNIQUE INDEX uq_tax_activation_success
ON public.tax_activation_logs (
    business_id,
    schedule_id,
    action
)
WHERE activation_status = 'success'
AND action = 'activate';

-- 14. Tax profile and version references must be paired.
ALTER TABLE public.sale_item_tax_details
    ADD CONSTRAINT chk_sale_tax_profile_reference_pair
    CHECK (
        (
            tax_profile_id IS NULL
            AND tax_profile_version_id IS NULL
        )
        OR
        (
            tax_profile_id IS NOT NULL
            AND tax_profile_version_id IS NOT NULL
        )
    );

COMMIT;
