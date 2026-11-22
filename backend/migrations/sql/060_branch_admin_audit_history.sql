
BEGIN;

CREATE OR REPLACE FUNCTION public.fn_branch_admin_audit_history(
    p_business_id UUID,
    p_requester_user_id UUID,
    p_business_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_result JSONB;
    v_admin JSONB;
BEGIN
    -- Validate active Business and Owner access
    IF NOT EXISTS (
        SELECT 1
        FROM businesses b
        JOIN business_users bu
            ON bu.business_id = b.id
        JOIN roles r
            ON r.id = bu.role_id
        WHERE b.id = p_business_id
          AND b.status = 'active'
          AND bu.user_id = p_requester_user_id
          AND bu.status = 'active'
          AND LOWER(r.role_name) = 'owner'
    ) THEN
        RAISE EXCEPTION 'Only an active Business Owner can view Admin audit history.';
    END IF;

    -- Validate target Branch Admin membership
    SELECT jsonb_build_object(
        'business_user_id', bu.id,
        'user_id', u.id,
        'full_name', u.full_name,
        'email', u.email,
        'phone', u.phone,
        'role_name', r.role_name,
        'membership_status', bu.status
    )
    INTO v_admin
    FROM business_users bu
    JOIN users u
        ON u.id = bu.user_id
    JOIN roles r
        ON r.id = bu.role_id
    WHERE bu.id = p_business_user_id
      AND bu.business_id = p_business_id
      AND LOWER(r.role_name) = 'branch admin';

    IF v_admin IS NULL THEN
        RAISE EXCEPTION 'Branch Admin not found in this Business.';
    END IF;

    SELECT jsonb_build_object(
        'admin', v_admin,

        -- Current active Branch assignments
        'current_branch_assignments',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'assignment_id', a.id,
                        'branch_id', a.branch_id,
                        'branch_name', br.branch_name,
                        'assignment_status', a.assignment_status,
                        'assigned_at', a.assigned_at,
                        'effective_from', a.effective_from,
                        'notes', a.notes
                    )
                    ORDER BY a.assigned_at DESC
                )
                FROM branch_user_assignments a
                JOIN branches br
                    ON br.id = a.branch_id
                   AND br.business_id = a.business_id
                WHERE a.business_id = p_business_id
                  AND a.business_user_id = p_business_user_id
                  AND a.assignment_type = 'branch_admin'
                  AND a.assignment_status = 'active'
            ),
            '[]'::JSONB
        ),

        -- Complete assignment and creation audit history
        'history',
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'audit_id', al.id,
                        'action', al.action,
                        'table_name', al.table_name,
                        'record_id', al.record_id,
                        'branch_id',
                            COALESCE(
                                al.new_values->>'branch_id',
                                al.old_values->>'branch_id',
                                a.branch_id::TEXT
                            ),
                        'branch_name', br.branch_name,
                        'performed_by_user_id', al.user_id,
                        'performed_by_name', actor.full_name,
                        'performed_at', al.created_at,
                        'old_values', al.old_values,
                        'new_values', al.new_values,
                        'previous_status',
                            al.old_values->>'assignment_status',
                        'new_status',
                            al.new_values->>'assignment_status',
                        'revocation_reason',
                            COALESCE(
                                al.new_values->>'revocation_reason',
                                al.old_values->>'revocation_reason'
                            ),
                        'notes',
                            COALESCE(
                                al.new_values->>'notes',
                                al.old_values->>'notes'
                            )
                    )
                    ORDER BY al.created_at DESC
                )
                FROM audit_logs al
                LEFT JOIN branch_user_assignments a
                    ON al.table_name = 'branch_user_assignments'
                   AND a.id = al.record_id
                   AND a.business_id = p_business_id
                LEFT JOIN branches br
                    ON br.id = COALESCE(
                        NULLIF(al.new_values->>'branch_id', '')::UUID,
                        NULLIF(al.old_values->>'branch_id', '')::UUID,
                        a.branch_id
                    )
                   AND br.business_id = p_business_id
                LEFT JOIN users actor
                    ON actor.id = al.user_id
                WHERE al.business_id = p_business_id
                  AND (
                      (
                          al.table_name = 'branch_user_assignments'
                          AND a.business_user_id = p_business_user_id
                      )
                      OR
                      (
                          al.table_name = 'business_users'
                          AND al.record_id = p_business_user_id
                          AND al.action = 'BRANCH_ADMIN_CREATED'
                      )
                  )
            ),
            '[]'::JSONB
        )
    )
    INTO v_result;

    RETURN v_result;
END;
$$;

ALTER FUNCTION public.fn_branch_admin_audit_history(
    UUID, UUID, UUID
) OWNER TO nokshighor_branch_manager;

REVOKE ALL ON FUNCTION public.fn_branch_admin_audit_history(
    UUID, UUID, UUID
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_branch_admin_audit_history(
    UUID, UUID, UUID
) TO nokshighor_app;

COMMIT;
