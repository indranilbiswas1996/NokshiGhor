BEGIN;

GRANT SELECT (business_id, unit_id)
ON public.business_unit_access
TO nokshighor_super_admin_manager;

GRANT SELECT (role_id, permission_id)
ON public.role_permissions
TO nokshighor_super_admin_manager;

COMMIT;
