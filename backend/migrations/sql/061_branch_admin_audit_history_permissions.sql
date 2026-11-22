
BEGIN;

GRANT SELECT ON TABLE
    public.roles,
    public.users,
    public.audit_logs
TO nokshighor_branch_manager;

COMMIT;
