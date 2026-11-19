
BEGIN;

GRANT SELECT (id)
ON TABLE public.tax_profile_version_components
TO nokshighor_tax_writer;

COMMIT;
