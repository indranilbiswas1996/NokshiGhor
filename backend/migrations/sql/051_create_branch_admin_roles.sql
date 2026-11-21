
BEGIN;

INSERT INTO public.roles (
    business_id,
    role_name,
    description,
    is_system
)
SELECT
    b.id,
    'Branch Admin',
    'Manages assigned branch operations and branch-level activities.',
    FALSE
FROM public.businesses b
WHERE b.status = 'active'
  AND NOT EXISTS (
      SELECT 1
      FROM public.roles r
      WHERE r.business_id = b.id
        AND LOWER(BTRIM(r.role_name)) = 'branch admin'
  );

COMMIT;
