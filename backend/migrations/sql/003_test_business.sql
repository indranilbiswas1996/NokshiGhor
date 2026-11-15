
BEGIN;

-- TEST USER (inactive, cannot log in)
INSERT INTO users (
    id, full_name, email, password_hash, status
)
VALUES (
    '00000000-0000-4000-8000-000000000101',
    'NokshiGhor Test User',
    'test-user@nokshighor.local',
    '!TEST_ONLY_NO_REAL_PASSWORD!',
    'inactive'
);

-- TEST ROLE
INSERT INTO roles (id, role_name, description)
VALUES (
    '00000000-0000-4000-8000-000000000301',
    'test_business_owner',
    'Temporary role for database testing'
)
ON CONFLICT (role_name) DO NOTHING;

-- TEST BUSINESS
INSERT INTO businesses (
    id, business_name, business_type, created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000201',
    'NokshiGhor Test Business',
    'both',
    '00000000-0000-4000-8000-000000000101'
);

-- BUSINESS SETTINGS
INSERT INTO business_settings (
    business_id, shop_name, address, currency, created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000201',
    'NokshiGhor Demo Shop',
    'Test Address, West Bengal, India',
    'INR',
    '00000000-0000-4000-8000-000000000101'
);

-- BUSINESS USER MAPPING
INSERT INTO business_users (
    id, business_id, user_id, role_id, status, created_by
)
SELECT
    '00000000-0000-4000-8000-000000000401',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000101',
    id,
    'inactive',
    '00000000-0000-4000-8000-000000000101'
FROM roles
WHERE role_name = 'test_business_owner';

-- ELECTRICAL CATEGORY
INSERT INTO categories (
    id, business_id, category_name, category_type, created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000501',
    '00000000-0000-4000-8000-000000000201',
    'Electrical',
    'electrical',
    '00000000-0000-4000-8000-000000000101'
);

-- INTERIOR CATEGORY
INSERT INTO categories (
    id, business_id, category_name, category_type, created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000502',
    '00000000-0000-4000-8000-000000000201',
    'Interior',
    'interior',
    '00000000-0000-4000-8000-000000000101'
);

-- SAMPLE ELECTRICAL PRODUCT
INSERT INTO products (
    id,
    business_id,
    category_id,
    unit_id,
    product_name,
    product_type,
    business_line,
    sku,
    barcode,
    brand,
    purchase_price,
    selling_price,
    tax_rate,
    track_inventory,
    created_by
)
SELECT
    '00000000-0000-4000-8000-000000000601',
    '00000000-0000-4000-8000-000000000201',
    '00000000-0000-4000-8000-000000000501',
    id,
    'Test LED Bulb 9W',
    'goods',
    'electrical',
    'TEST-LED-001',
    'TEST-BARCODE-001',
    'Demo Brand',
    65.00,
    90.00,
    18.0000,
    TRUE,
    '00000000-0000-4000-8000-000000000101'
FROM units
WHERE unit_code = 'PCS';

-- VERIFY TEST RELATIONSHIPS
SELECT
    b.business_name,
    bs.shop_name,
    c.category_name,
    p.product_name,
    p.sku,
    u.unit_name,
    p.purchase_price,
    p.selling_price
FROM products p
JOIN businesses b ON b.id = p.business_id
JOIN business_settings bs ON bs.business_id = b.id
JOIN categories c
    ON c.id = p.category_id
    AND c.business_id = p.business_id
JOIN units u ON u.id = p.unit_id
WHERE p.sku = 'TEST-LED-001';

-- All test records are rolled back.
ROLLBACK;
