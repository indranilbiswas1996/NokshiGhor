
BEGIN;

-- ============================================
-- TEST: CUSTOMER & SUPPLIER MANAGEMENT
-- All test data will be rolled back.
-- ============================================

-- 1. TEST USER
INSERT INTO users (
    id, full_name, email, password_hash, status
)
VALUES (
    '00000000-0000-4000-8000-000000000111',
    'Party Test User',
    'party-test@nokshighor.local',
    '!TEST_ONLY_NO_REAL_PASSWORD!',
    'inactive'
);

-- 2. TEST BUSINESS
INSERT INTO businesses (
    id, business_name, business_type, created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000211',
    'Party Test Business',
    'both',
    '00000000-0000-4000-8000-000000000111'
);

-- 3. ONE PARTY
-- This person will be both customer and supplier.

INSERT INTO parties (
    id,
    business_id,
    party_name,
    party_type,
    phone,
    email,
    gstin,
    created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000311',
    '00000000-0000-4000-8000-000000000211',
    'Rahul Enterprise',
    'business',
    '9000000001',
    'rahul-test@example.local',
    NULL,
    '00000000-0000-4000-8000-000000000111'
);

-- 4. REGISTER AS CUSTOMER

INSERT INTO customers (
    id,
    business_id,
    party_id,
    customer_code,
    credit_limit,
    credit_days,
    created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000411',
    '00000000-0000-4000-8000-000000000211',
    '00000000-0000-4000-8000-000000000311',
    'CUST-001',
    10000.00,
    15,
    '00000000-0000-4000-8000-000000000111'
);

-- 5. REGISTER THE SAME PARTY AS SUPPLIER

INSERT INTO suppliers (
    id,
    business_id,
    party_id,
    supplier_code,
    payment_terms_days,
    notes,
    created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000511',
    '00000000-0000-4000-8000-000000000211',
    '00000000-0000-4000-8000-000000000311',
    'SUP-001',
    30,
    'Test supplier record',
    '00000000-0000-4000-8000-000000000111'
);

-- 6. CUSTOMER ADDRESS

INSERT INTO customer_addresses (
    id,
    business_id,
    customer_id,
    address_type,
    contact_name,
    contact_phone,
    address_line1,
    city,
    district,
    state,
    postal_code,
    is_default,
    created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000611',
    '00000000-0000-4000-8000-000000000211',
    '00000000-0000-4000-8000-000000000411',
    'billing',
    'Rahul',
    '9000000001',
    'Demo Market Road',
    'Kalyani',
    'Nadia',
    'West Bengal',
    '741235',
    TRUE,
    '00000000-0000-4000-8000-000000000111'
);

-- 7. SUPPLIER CONTACT

INSERT INTO supplier_contacts (
    id,
    business_id,
    supplier_id,
    contact_name,
    designation,
    phone,
    is_primary,
    created_by
)
VALUES (
    '00000000-0000-4000-8000-000000000711',
    '00000000-0000-4000-8000-000000000211',
    '00000000-0000-4000-8000-000000000511',
    'Rahul',
    'Owner',
    '9000000001',
    TRUE,
    '00000000-0000-4000-8000-000000000111'
);

-- 8. VERIFY SAME PARTY HAS BOTH ROLES

SELECT
    p.party_name,
    p.phone,
    c.customer_code,
    c.credit_limit,
    s.supplier_code,
    s.payment_terms_days,
    (
        SELECT COUNT(*)
        FROM customer_addresses ca
        WHERE ca.customer_id = c.id
    ) AS customer_address_count,
    (
        SELECT COUNT(*)
        FROM supplier_contacts sc
        WHERE sc.supplier_id = s.id
    ) AS supplier_contact_count
FROM parties p
JOIN customers c
    ON c.business_id = p.business_id
    AND c.party_id = p.id
JOIN suppliers s
    ON s.business_id = p.business_id
    AND s.party_id = p.id
WHERE p.party_name = 'Rahul Enterprise';

-- 9. ROLLBACK TEST DATA

ROLLBACK;
