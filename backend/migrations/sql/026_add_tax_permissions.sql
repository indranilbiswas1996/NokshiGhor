BEGIN;

-- 1. Create Tax permissions
INSERT INTO public.permissions (
    permission_key,
    description
)
VALUES
    (
        'tax.manage',
        'Create and manage tax types, components, profiles, mappings and schedules'
    ),
    (
        'tax.view',
        'View tax types, components, profiles, mappings and schedules'
    )
ON CONFLICT (permission_key) DO NOTHING;


-- 2. Assign Tax permissions to active Owner roles
INSERT INTO public.role_permissions (
    role_id,
    permission_id,
    created_by
)
SELECT
    bu.role_id,
    p.id,
    bu.user_id
FROM public.business_users bu
JOIN public.roles r
    ON r.id = bu.role_id
   AND r.business_id = bu.business_id
JOIN public.permissions p
    ON p.permission_key IN ('tax.manage', 'tax.view')
WHERE
    bu.status = 'active'
    AND r.role_name = 'Owner'
ON CONFLICT (role_id, permission_id) DO NOTHING;


COMMIT;