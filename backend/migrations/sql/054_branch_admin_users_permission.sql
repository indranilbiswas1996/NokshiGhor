BEGIN;

GRANT SELECT, INSERT
ON TABLE public.users
TO nokshighor_owner_manager;

COMMIT;