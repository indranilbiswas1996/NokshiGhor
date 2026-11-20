
BEGIN;

-- Dedicated role for secure token revocation operations.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_roles
        WHERE rolname = 'nokshighor_auth_token_manager'
    ) THEN
        CREATE ROLE nokshighor_auth_token_manager
            NOLOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOBYPASSRLS
            NOINHERIT;
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.auth_revoked_tokens (
    token_id UUID PRIMARY KEY,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

GRANT USAGE ON SCHEMA public
TO nokshighor_auth_token_manager;

GRANT CREATE ON SCHEMA public
TO nokshighor_auth_token_manager;

GRANT INSERT (
    token_id,
    expires_at
)
ON public.auth_revoked_tokens
TO nokshighor_auth_token_manager;

GRANT SELECT (
    token_id,
    expires_at
)
ON public.auth_revoked_tokens
TO nokshighor_auth_token_manager;

-- Securely revoke an access token.
CREATE OR REPLACE FUNCTION public.fn_auth_revoke_token(
    p_token_id UUID,
    p_expires_at TIMESTAMPTZ
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    INSERT INTO public.auth_revoked_tokens (token_id, expires_at)
    VALUES (p_token_id, p_expires_at)
    ON CONFLICT (token_id) DO NOTHING;

    RETURN TRUE;
END;
$$;

-- Check whether an access token has been revoked.
CREATE OR REPLACE FUNCTION public.fn_auth_is_token_revoked(
    p_token_id UUID
)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.auth_revoked_tokens
        WHERE token_id = p_token_id
          AND expires_at > CURRENT_TIMESTAMP
    );
$$;

ALTER FUNCTION public.fn_auth_revoke_token(UUID, TIMESTAMPTZ)
OWNER TO nokshighor_auth_token_manager;

ALTER FUNCTION public.fn_auth_is_token_revoked(UUID)
OWNER TO nokshighor_auth_token_manager;

REVOKE CREATE ON SCHEMA public
FROM nokshighor_auth_token_manager;

REVOKE ALL ON TABLE public.auth_revoked_tokens
FROM PUBLIC, nokshighor_app;

REVOKE ALL ON FUNCTION public.fn_auth_revoke_token(UUID, TIMESTAMPTZ)
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_auth_is_token_revoked(UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_auth_revoke_token(UUID, TIMESTAMPTZ)
TO nokshighor_app;

GRANT EXECUTE ON FUNCTION public.fn_auth_is_token_revoked(UUID)
TO nokshighor_app;

COMMIT;
