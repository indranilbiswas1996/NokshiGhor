BEGIN;

-- Branch Admin creation function
GRANT SELECT, INSERT
ON TABLE public.business_users
TO nokshighor_owner_manager;

-- Branch Admin assignment function
GRANT SELECT
ON TABLE public.business_users
TO nokshighor_branch_manager;

GRANT UPDATE (id)
ON TABLE public.business_users
TO nokshighor_branch_manager;

COMMIT;