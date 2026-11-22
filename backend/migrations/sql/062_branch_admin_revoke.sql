
BEGIN;

-- Required privileges for the SECURITY DEFINER function owner
GRANT SELECT ON public.businesses,
                public.business_users,
                public.roles,
                public.branches,
                public.branch_user_assignments
TO nokshighor_branch_manager;

GRANT UPDATE ON public.branch_user_assignments
TO nokshighor_branch_manager;

GRANT INSERT ON public.audit_logs
TO nokshighor_branch_manager;


CREATE OR REPLACE FUNCTION public.fn_branch_admin_revoke(
    p_business_id UUID,
    p_requester_user_id UUID,
    p_assignment_id UUID,
    p_revocation_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_assignment public.branch_user_assignments%ROWTYPE;
    v_old_values JSONB;
    v_new_values JSONB;
    v_now TIMESTAMPTZ;
    v_branch_name TEXT;
BEGIN
    -- Validate active Business
    IF NOT EXISTS (
        SELECT 1
        FROM public.businesses b
        WHERE b.id = p_business_id
          AND b.status = 'active'
    ) THEN
        RAISE EXCEPTION 'Business is not active or does not exist';
    END IF;

    -- Only an active Owner can revoke Branch Admin access
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r ON r.id = bu.role_id
        WHERE bu.business_id = p_business_id
          AND bu.user_id = p_requester_user_id
          AND bu.status = 'active'
          AND r.role_name = 'Owner'
    ) THEN
        RAISE EXCEPTION 'Only an active Business Owner can revoke Branch Admin access';
    END IF;

    -- Lock and retrieve the requested active assignment
    SELECT a.*
    INTO v_assignment
    FROM public.branch_user_assignments a
    WHERE a.id = p_assignment_id
      AND a.business_id = p_business_id
      AND a.assignment_type = 'branch_admin'
      AND a.assignment_status = 'active'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Active Branch Admin assignment not found';
    END IF;

    -- Validate that the target membership is a Branch Admin
    IF NOT EXISTS (
        SELECT 1
        FROM public.business_users bu
        JOIN public.roles r ON r.id = bu.role_id
        WHERE bu.id = v_assignment.business_user_id
          AND bu.business_id = p_business_id
          AND bu.status = 'active'
          AND r.role_name = 'Branch Admin'
    ) THEN
        RAISE EXCEPTION 'Target membership is not an active Branch Admin';
    END IF;

    SELECT br.branch_name
    INTO v_branch_name
    FROM public.branches br
    WHERE br.id = v_assignment.branch_id
      AND br.business_id = p_business_id;

    v_now := clock_timestamp();

    -- Preserve the original assignment details
    v_old_values := jsonb_build_object(
        'assignment_id', v_assignment.id,
        'business_id', v_assignment.business_id,
        'branch_id', v_assignment.branch_id,
        'branch_name', v_branch_name,
        'business_user_id', v_assignment.business_user_id,
        'assignment_type', v_assignment.assignment_type,
        'assignment_status', v_assignment.assignment_status,
        'effective_from', v_assignment.effective_from,
        'effective_to', v_assignment.effective_to,
        'revoked_at', v_assignment.revoked_at,
        'revoked_by', v_assignment.revoked_by,
        'revocation_reason', v_assignment.revocation_reason
    );

    -- Revoke only this Branch assignment.
    -- Never delete the assignment record.
    UPDATE public.branch_user_assignments
    SET assignment_status = 'revoked',
        effective_to = v_now,
        revoked_at = v_now,
        revoked_by = p_requester_user_id,
        revocation_reason = NULLIF(BTRIM(p_revocation_reason), '')
    WHERE id = v_assignment.id
    RETURNING * INTO v_assignment;

    v_new_values := jsonb_build_object(
        'assignment_id', v_assignment.id,
        'business_id', v_assignment.business_id,
        'branch_id', v_assignment.branch_id,
        'branch_name', v_branch_name,
        'business_user_id', v_assignment.business_user_id,
        'assignment_type', v_assignment.assignment_type,
        'previous_status', 'active',
        'assignment_status', v_assignment.assignment_status,
        'effective_from', v_assignment.effective_from,
        'effective_to', v_assignment.effective_to,
        'revoked_at', v_assignment.revoked_at,
        'revoked_by', v_assignment.revoked_by,
        'revocation_reason', v_assignment.revocation_reason
    );

    -- Immutable audit event
    INSERT INTO public.audit_logs (
        business_id,
        user_id,
        action,
        table_name,
        record_id,
        old_values,
        new_values,
        created_at
    )
    VALUES (
        p_business_id,
        p_requester_user_id,
        'BRANCH_ADMIN_REVOKED',
        'branch_user_assignments',
        v_assignment.id,
        v_old_values,
        v_new_values,
        v_now
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'message', 'Branch Admin access revoked successfully',
        'assignment_id', v_assignment.id,
        'branch_id', v_assignment.branch_id,
        'business_user_id', v_assignment.business_user_id,
        'assignment_status', v_assignment.assignment_status,
        'revoked_at', v_assignment.revoked_at,
        'revocation_reason', v_assignment.revocation_reason
    );
END;
$$;

ALTER FUNCTION public.fn_branch_admin_revoke(
    UUID, UUID, UUID, TEXT
) OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_branch_admin_revoke(
    UUID, UUID, UUID, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_branch_admin_revoke(
    UUID, UUID, UUID, TEXT
) TO nokshighor_app;

COMMIT;
