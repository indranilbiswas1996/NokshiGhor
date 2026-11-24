import { useState } from 'react'
import { isAxiosError } from 'axios'
import { LoaderCircle, UserRoundPlus, X } from 'lucide-react'
import { branchApi } from '../api/branch'

interface CreateUnassignedBranchAdminProps {
  onClose: () => void
  onCreated: () => void
}

export default function CreateUnassignedBranchAdmin({
  onClose,
  onCreated,
}: CreateUnassignedBranchAdminProps) {
  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const handleCreate = async () => {
    const trimmedEmail = email.trim()
    const trimmedPhone = phone.trim()

    if (!fullName.trim() || !trimmedEmail || !password) {
      setError('Name, email and password are required.')
      return
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail)) {
      setError('Enter a valid email address.')
      return
    }

    if (trimmedPhone && !/^[6-9]\d{9}$/.test(trimmedPhone)) {
      setError('Enter a valid 10-digit Indian mobile number.')
      return
    }

    if (password.length < 8) {
      setError('Password must contain at least 8 characters.')
      return
    }

    setSaving(true)
    setError('')

    try {
      await branchApi.createBranchAdmin({
        full_name: fullName.trim(),
        email: trimmedEmail,
        phone: trimmedPhone || null,
        password,
      })

      onCreated()
      onClose()
    } catch (err) {
      const message = isAxiosError(err)
        ? err.response?.data?.detail
        : null

      setError(
        typeof message === 'string'
          ? message
          : 'Unable to create Branch Admin.'
      )
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="owner-modal-overlay">
      <div
        className="owner-profile-modal branch-admin-list-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="create-unassigned-branch-admin-title"
      >
        <div className="owner-modal-header">
          <div>
            <h2 id="create-unassigned-branch-admin-title">
              Create Admin without Branch Assignment
            </h2>
            <p>This Branch Admin will not be assigned to a branch.</p>
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

        <div className="owner-profile-edit">
          <div>
            <label htmlFor="unassigned-branch-admin-name">Full Name</label>
            <input
              id="unassigned-branch-admin-name"
              type="text"
              value={fullName}
              onChange={(event) => setFullName(event.target.value)}
              autoComplete="name"
              disabled={saving}
            />
          </div>

          <div>
            <label htmlFor="unassigned-branch-admin-email">Email</label>
            <input
              id="unassigned-branch-admin-email"
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              autoComplete="email"
              required
              disabled={saving}
            />
          </div>

          <div>
            <label htmlFor="unassigned-branch-admin-phone">Phone (Optional)</label>
            <input
              id="unassigned-branch-admin-phone"
              type="tel"
              value={phone}
              onChange={(event) => setPhone(event.target.value)}
              autoComplete="tel"
              inputMode="numeric"
              maxLength={10}
              disabled={saving}
            />
          </div>

          <div>
            <label htmlFor="unassigned-branch-admin-password">Password</label>
            <input
              id="unassigned-branch-admin-password"
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              autoComplete="new-password"
              minLength={8}
              disabled={saving}
            />
          </div>

          {error && (
            <div className="page-notice error" role="alert">
              {error}
            </div>
          )}
        </div>

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
            className="owner-profile-save"
            onClick={() => void handleCreate()}
            disabled={saving || !fullName.trim() || !email.trim() || !password}
          >
            {saving ? (
              <LoaderCircle size={15} className="branch-spin" />
            ) : (
              <UserRoundPlus size={15} />
            )}
            {saving ? 'Creating...' : 'Create Admin'}
          </button>
        </div>
      </div>
    </div>
  )
}