BEGIN;

-- Allow only ID column access required by INSERT ... RETURNING id.

GRANT SELECT (id)
ON TABLE public.opening_stock_documents
TO nokshighor_opening_stock_writer;

GRANT SELECT (id)
ON TABLE public.opening_stock_items
TO nokshighor_opening_stock_writer;

COMMIT;