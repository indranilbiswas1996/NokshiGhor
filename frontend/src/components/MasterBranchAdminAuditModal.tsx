
import { useEffect, useState } from 'react'
import { isAxiosError } from 'axios'
import {
  X,
  RefreshCw,
  UserRound,
  Building2,
  CalendarDays,
  History,
  ShieldCheck,
  Mail,
  Phone,
} from 'lucide-react'
import {
  branchApi,
  type BranchAdminAuditHistoryResponse,
} from '../api/branch'

interface MasterBranchAdminAuditModalProps {
  businessUserId: string
  onClose: () => void
}

function formatDate(value: string | null | undefined) {
  if (!value) return '—'

  const date = new Date(value)

  if (Number.isNaN(date.getTime())) return '—'

  return date.toLocaleString('en-IN', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

function formatAction(action: string) {
  return action
    .replaceAll('_', ' ')
    .toLowerCase()
    .replace(/\b\w/g, (char) => char.toUpperCase())
}

export default function MasterBranchAdminAuditModal({
  businessUserId,
  onClose,
}: MasterBranchAdminAuditModalProps) {
  const [data, setData] =
    useState<BranchAdminAuditHistoryResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const loadHistory = async () => {
    setLoading(true)
    setError('')

    try {
      const response =
        await branchApi.getBranchAdminAuditHistory(businessUserId)

      setData(response)
    } catch (err) {
      if (isAxiosError(err)) {
        setError(
          err.response?.data?.detail ||
            'Unable to load Admin audit history.',
        )
      } else {
        setError('Unable to load Admin audit history.')
      }
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void loadHistory()
  }, [businessUserId])

  return (
    <div
      className="owner-modal-overlay"
      onClick={onClose}
    >
      <div
        className="owner-profile-modal branch-admin-list-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="master-admin-audit-title"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="owner-modal-header">
          <div>
            <h2 id="master-admin-audit-title">
              Admin Audit Details
            </h2>
            <p>Admin profile, Branch assignments and activity history</p>
          </div>

          <button
            type="button"
            className="owner-close-button"
            onClick={onClose}
            aria-label="Close"
          >
            <X size={20} />
          </button>
        </div>

        <div className="owner-modal-body">
          {loading ? (
            <div className="branch-admin-loading">
              <RefreshCw size={20} className="spin" />
              Loading Admin audit history...
            </div>
          ) : error ? (
            <div className="branch-admin-error">
              <p>{error}</p>
              <button
                type="button"
                className="owner-profile-cancel"
                onClick={() => void loadHistory()}
              >
                Retry
              </button>
            </div>
          ) : data ? (
            <>
              <section className="master-admin-audit-section">
                <h3>
                  <UserRound size={18} />
                  Admin Profile
                </h3>

                <div className="master-admin-audit-profile">
                  <div>
                    <strong>{data.admin.full_name}</strong>
                    {data.admin.email && (
                      <span className="master-admin-audit-contact">
                        <Mail size={15} />
                        <span>{data.admin.email}</span>
                      </span>
                    )}

                    {data.admin.phone && (
                      <span className="master-admin-audit-contact">
                        <Phone size={15} />
                        <span>{data.admin.phone}</span>
                      </span>
                    )}
                  </div>

                  <span className="master-admin-audit-status">
                    {data.admin.membership_status}
                  </span>
                </div>
              </section>

              <section className="master-admin-audit-section">
                <h3>
                  <Building2 size={18} />
                  Current Branch Assignments
                </h3>

                {data.current_branch_assignments.length === 0 ? (
                  <p>No active Branch assignments.</p>
                ) : (
                  <div className="master-admin-audit-list">
                    {data.current_branch_assignments.map(
                      (assignment) => (
                        <div
                          className="master-admin-audit-item"
                          key={assignment.assignment_id}
                        >
                          <strong>{assignment.branch_name}</strong>
                          <span>
                            Status: {assignment.assignment_status}
                          </span>
                          <span>
                            Assigned: {formatDate(assignment.assigned_at)}
                          </span>
                        </div>
                      ),
                    )}
                  </div>
                )}
              </section>

              <section className="master-admin-audit-section">
                <h3>
                  <History size={18} />
                  Complete Audit History
                </h3>

                {data.history.length === 0 ? (
                  <p>No audit history available.</p>
                ) : (
                  <div className="master-admin-audit-list">
                    {data.history.map((event) => (
                      <article
                        className={`master-admin-audit-item ${
                          event.action === 'BRANCH_ADMIN_REVOKED'
                            ? 'master-admin-audit-revoked'
                            : event.action === 'BRANCH_ADMIN_ASSIGNED'
                              ? 'master-admin-audit-assigned'
                              : ''
                        }`}
                        key={event.audit_id}
                      >
                        <div className="master-admin-audit-event-header">
                          <strong>{formatAction(event.action)}</strong>
                          <span>{event.branch_name || 'Business Level'}</span>
                        </div>

                        <div className="master-admin-audit-meta">
                          <span>
                            <ShieldCheck size={14} />
                            Performed by: {event.performed_by_name || 'Unknown'}
                          </span>

                          <span>
                            <CalendarDays size={14} />
                            {formatDate(event.performed_at)}
                          </span>
                        </div>

                        {(event.previous_status || event.new_status) && (
                          <p>
                            Status {event.previous_status || ''}
                            {' → '}
                            {event.new_status || ''}
                          </p>
                        )}

                        {event.revocation_reason && (
                          <p>
                            Reason: {event.revocation_reason}
                          </p>
                        )}

                        {event.notes && (
                          <p>Notes: {event.notes}</p>
                        )}
                      </article>
                    ))}
                  </div>
                )}
              </section>
            </>
          ) : null}
        </div>

        <div className="owner-profile-actions">
          <button
            type="button"
            className="owner-profile-cancel"
            onClick={onClose}
          >
            Close
          </button>
        </div>
      </div>
    </div>
  )
}
