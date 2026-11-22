
import { useState } from 'react'
import { isAxiosError } from 'axios'
import { X, ShieldOff, Loader2 } from 'lucide-react'
import { branchApi } from '../api/branch'

interface BranchAdminRevokeModalProps {
  assignmentId: string
  adminName: string
  branchName: string
  onClose: () => void
  onSuccess: () => void
}

export default function BranchAdminRevokeModal({
  assignmentId,
  adminName,
  branchName,
  onClose,
  onSuccess,
}: BranchAdminRevokeModalProps) {
  const [reason, setReason] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const handleRevoke = async () => {
    setSaving(true)
    setError('')

    try {
      await branchApi.revokeBranchAdmin(
        assignmentId,
        reason.trim() || undefined,
      )

      onSuccess()
      onClose()
    } catch (err) {
      if (isAxiosError(err)) {
        setError(
          err.response?.data?.detail ||
            'Unable to revoke Branch Admin access. Please try again.',
        )
      } else {
        setError('Something went wrong. Please try again.')
      }
    } finally {
      setSaving(false)
    }
  }

  return (
    <div
      className="owner-modal-overlay"
      onClick={saving ? undefined : onClose}
    >
      <div
        className="owner-profile-modal branch-admin-list-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="branch-admin-revoke-title"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="owner-modal-header">
          <div>
            <h2 id="branch-admin-revoke-title">
              Revoke Branch Access
            </h2>
            <p>
              Confirm removal of this Branch Admin assignment.
            </p>
          </div>

          <button
            type="button"
            className="owner-close-button"
            onClick={onClose}
            disabled={saving}
            aria-label="Close"
          >
            <X size={20} />
          </button>
        </div>

        <div className="owner-modal-body">
          <div className="branch-admin-revoke-summary">
            <ShieldOff size={22} />
            <div>
              <strong>{adminName}</strong>
              <span>{branchName}</span>
            </div>
          </div>

          <p className="branch-admin-revoke-warning">
            This Admin will lose access to this Branch. Other Branch
            assignments and Business membership will remain unchanged.
          </p>

          <div className="owner-form-group">
            <label htmlFor="branch-admin-revoke-reason">
              Revocation Reason (Optional)
            </label>
            <textarea
              id="branch-admin-revoke-reason"
              value={reason}
              onChange={(event) => setReason(event.target.value)}
              placeholder="Enter reason for revoking access..."
              rows={3}
              disabled={saving}
            />
          </div>

          {error && (
            <div className="branch-admin-revoke-error" role="alert">
              {error}
            </div>
          )}

          <div className="owner-profile-actions">
            <button
              type="button"
              className="owner-profile-cancel"
              onClick={onClose}
              disabled={saving}
            >
              Cancel
            </button>

            <button
              type="button"
              className="branch-admin-revoke-confirm"
              onClick={handleRevoke}
              disabled={saving}
            >
              {saving ? (
                <>
                  <Loader2 size={15} className="spin" />
                  Revoking...
                </>
              ) : (
                <>
                  <ShieldOff size={15} />
                  Revoke Access
                </>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
