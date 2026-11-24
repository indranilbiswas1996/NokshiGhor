BEGIN;

CREATE OR REPLACE FUNCTION public.fn_super_admin_business_set_status(
    p_actor_user_id UUID,
    p_business_id UUID,
    p_status VARCHAR
)
RETURNS JSONB
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_old_status VARCHAR(20);
    v_name VARCHAR(200);
    v_type VARCHAR(40);
BEGIN
    IF NOT public.fn_is_super_admin(p_actor_user_id) THEN
        RAISE EXCEPTION 'Super Admin access is required';
    END IF;

    IF p_status NOT IN ('active', 'inactive') THEN
        RAISE EXCEPTION 'Business status must be active or inactive';
    END IF;

    SELECT b.business_name, b.business_type, b.status
    INTO v_name, v_type, v_old_status
    FROM public.businesses b
    WHERE b.id = p_business_id
      AND b.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Business not found';
    END IF;

    UPDATE public.businesses
    SET status = p_status,
        updated_at = CURRENT_TIMESTAMP,
        updated_by = p_actor_user_id
    WHERE id = p_business_id;

    INSERT INTO public.audit_logs (
        business_id, user_id, action, table_name, record_id,
        old_values, new_values
    ) VALUES (
        p_business_id,
        p_actor_user_id,
        'BUSINESS_STATUS_CHANGED',
        'businesses',
        p_business_id,
        jsonb_build_object('status', v_old_status),
        jsonb_build_object('status', p_status)
    );

    RETURN jsonb_build_object(
        'id', p_business_id,
        'business_name', v_name,
        'business_type', v_type,
        'status', p_status
    );
END;
$$;

ALTER FUNCTION public.fn_super_admin_business_set_status(UUID, UUID, VARCHAR)
OWNER TO nokshighor_super_admin_manager;
REVOKE ALL ON FUNCTION public.fn_super_admin_business_set_status(UUID, UUID, VARCHAR)
FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_super_admin_business_set_status(UUID, UUID, VARCHAR)
TO nokshighor_app;

COMMIT;
