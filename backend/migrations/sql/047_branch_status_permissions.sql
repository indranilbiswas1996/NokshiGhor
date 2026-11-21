
BEGIN;

GRANT SELECT
ON TABLE public.businesses
TO nokshighor_branch_manager;

GRANT UPDATE (id)
ON TABLE public.businesses
TO nokshighor_branch_manager;

COMMIT;
