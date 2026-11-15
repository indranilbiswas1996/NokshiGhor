
BEGIN;

-- =====================================================
-- NOKSHIGHOR
-- Migration: 001_core_foundation
-- Database: PostgreSQL 17
-- =====================================================

-- 1. USERS
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    password_hash TEXT NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'locked')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX uq_users_email_active
ON users (LOWER(email))
WHERE deleted_at IS NULL;

-- 2. ROLES
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    role_name VARCHAR(80) NOT NULL UNIQUE,
    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL
);

-- 3. PERMISSIONS
CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    permission_key VARCHAR(120) NOT NULL UNIQUE,
    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL
);

-- 4. BUSINESSES
CREATE TABLE businesses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_name VARCHAR(200) NOT NULL,

    business_type VARCHAR(40) NOT NULL
        CHECK (
            business_type IN (
                'electrical',
                'interior',
                'both',
                'other'
            )
        ),

    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'suspended')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    deleted_at TIMESTAMPTZ
);

-- 5. BUSINESS SETTINGS
CREATE TABLE business_settings (
    business_id UUID PRIMARY KEY
        REFERENCES businesses(id) ON DELETE RESTRICT,

    shop_name VARCHAR(200) NOT NULL,
    logo_url TEXT,

    address TEXT,
    phone VARCHAR(20),
    email VARCHAR(255),
    gstin VARCHAR(20),

    currency VARCHAR(3) NOT NULL DEFAULT 'INR',

    settings JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL
);

-- 6. BUSINESS USERS
CREATE TABLE business_users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID NOT NULL
        REFERENCES businesses(id) ON DELETE RESTRICT,

    user_id UUID NOT NULL
        REFERENCES users(id) ON DELETE RESTRICT,

    role_id UUID NOT NULL
        REFERENCES roles(id) ON DELETE RESTRICT,

    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL,

    CONSTRAINT uq_business_users
        UNIQUE (business_id, user_id),

    CONSTRAINT uq_business_users_id_business
        UNIQUE (id, business_id)
);

-- 7. ROLE PERMISSIONS
CREATE TABLE role_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    role_id UUID NOT NULL
        REFERENCES roles(id) ON DELETE CASCADE,

    permission_id UUID NOT NULL
        REFERENCES permissions(id) ON DELETE CASCADE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    CONSTRAINT uq_role_permissions
        UNIQUE (role_id, permission_id)
);

-- 8. APPLICATION BRANDING
CREATE TABLE app_branding (
    id SMALLINT PRIMARY KEY DEFAULT 1
        CHECK (id = 1),

    app_name VARCHAR(150) NOT NULL DEFAULT 'NokshiGhor',
    app_logo_url TEXT,
    favicon_url TEXT,

    theme_settings JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,

    updated_at TIMESTAMPTZ,
    updated_by UUID REFERENCES users(id) ON DELETE SET NULL
);

-- 9. AUDIT LOGS
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    business_id UUID
        REFERENCES businesses(id) ON DELETE RESTRICT,

    user_id UUID
        REFERENCES users(id) ON DELETE SET NULL,

    action VARCHAR(30) NOT NULL,
    table_name VARCHAR(120) NOT NULL,
    record_id UUID,

    old_values JSONB,
    new_values JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =====================================================
-- INDEXES
-- =====================================================

CREATE INDEX idx_business_users_user
ON business_users (user_id);

CREATE INDEX idx_business_users_business
ON business_users (business_id);

CREATE INDEX idx_audit_logs_business_date
ON audit_logs (business_id, created_at DESC);

CREATE INDEX idx_audit_logs_record
ON audit_logs (table_name, record_id);

CREATE INDEX idx_businesses_status
ON businesses (status);

COMMIT;
