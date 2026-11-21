BEGIN;

GRANT SELECT, INSERT
ON TABLE public.business_users
TO nokshighor_owner_manager;

GRANT INSERT
ON TABLE public.audit_logs
TO nokshighor_owner_manager;

COMMIT;