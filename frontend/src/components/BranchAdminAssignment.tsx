
import { useEffect, useState } from 'react'
import { isAxiosError } from 'axios'
import { X, UserPlus, UserRoundPlus, MapPin, Mail } from 'lucide-react'
import {
  branchApi,
  type BranchAdminCandidate,
} from '../api/branch'
interface BranchAdminAssignmentProps {
  branchId: string
  branchName: string
  branchCode: string | null
  branchAddress: string | null
  branchEmail: string | null
  onClose: () => void
  onAssigned: () => void
}

export default function BranchAdminAssignment({
  branchId,
  branchName,
  branchCode,
  branchAddress,
  branchEmail,
  onClose,
  onAssigned,
}: BranchAdminAssignmentProps) {
  const [candidates, setCandidates] = useState<BranchAdminCandidate[]>([])
  const [selectedUser, setSelectedUser] = useState('')
  const [notes, setNotes] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [creating, setCreating] = useState(false)
  const [error, setError] = useState('')

  const [fullName, setFullName] = useState('')
  const [email, setEmail] = useState('')
  const [phone, setPhone] = useState('')
  const [password, setPassword] = useState('')
  
  useEffect(() => {
    let mounted = true

    const loadCandidates = async () => {
      try {
        setLoading(true)
        setError('')

        const response =
          await branchApi.getBranchAdminCandidates(branchId)

        if (mounted) {
          setCandidates(response.candidates)
        }
      } catch (err) {
        if (mounted) {
          const message = isAxiosError(err)
            ? err.response?.data?.detail
            : null

          setError(
            typeof message === 'string'
              ? message
              : 'Unable to load Branch Admin candidates.'
          )
        }
      } finally {
        if (mounted) setLoading(false)
      }
    }

    void loadCandidates()

    return () => {
      mounted = false
    }
  }, [branchId])

  const handleAssign = async () => {
    if (!selectedUser) {
      setError('Please select a Branch Admin.')
      return
    }

    try {
      setSaving(true)
      setError('')

      await branchApi.assignBranchAdmin(branchId, {
        business_user_id: selectedUser,
        notes: notes.trim() || null,
      })

      onAssigned()
      onClose()
    } catch (err) {
      const message = isAxiosError(err)
        ? err.response?.data?.detail
        : null

      setError(
        typeof message === 'string'
          ? message
          : 'Unable to assign Branch Admin.'
      )
    } finally {
      setSaving(false)
    }
  }
    
  const handleCreateAndAssign = async () => {
    if (!fullName.trim() || !email.trim() || !password) {
      setError('Name, email and password are required.')
      return
    }

    if (password.length < 8) {
      setError('Password must contain at least 8 characters.')
      return
    }

    try {
      setSaving(true)
      setError('')

      const response = await branchApi.createBranchAdmin({
        full_name: fullName.trim(),
        email: email.trim(),
        phone: phone.trim() || null,
        password,
      })

      await branchApi.assignBranchAdmin(branchId, {
        business_user_id: response.admin.business_user_id,
        notes: notes.trim() || 'Created and assigned from Branch Management.',
      })

    onAssigned()
    onClose()
    } catch (err) {
      const message = isAxiosError(err)
        ? err.response?.data?.detail
        : null

      setError(
        typeof message === 'string'
          ? message
          : 'Unable to create and assign Branch Admin.'
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
        aria-labelledby="branch-admin-title"
      >
        <div className="owner-modal-header">
          <div>
            <h2 id="branch-admin-title">Assign Branch Admin</h2>
            <div className="branch-admin-assignment-details">
              <h3>
                {branchName}
                {branchCode && <span> ({branchCode})</span>}
              </h3>

              {branchAddress && (
                <p>
                  <MapPin size={14} />
                  {branchAddress}
                </p>
              )}

              {branchEmail && (
                <p>
                  <Mail size={14} />
                  {branchEmail}
                </p>
              )}
            </div>
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
            
            <div className="owner-profile-actions">
              <button
                type="button"
                className="owner-profile-cancel"
                onClick={() => {
                  setCreating(false)
                  setError('')
                }}
                disabled={saving || !creating}
              >
                Existing Admin
              </button>

              <button
                type="button"
                className="owner-profile-save"
                onClick={() => {
                  setCreating(true)
                  setError('')
                }}
                disabled={saving || creating}
              >
                <UserPlus size={16} />
                Create New Admin
              </button>
            </div>
          </div>

          {creating ? (
            <>
              <div>
                <label htmlFor="branch-admin-name">Full Name</label>
                <input
                  id="branch-admin-name"
                  type="text"
                  value={fullName}
                  onChange={(event) => setFullName(event.target.value)}
                  placeholder="Enter full name"
                  disabled={saving}
                />
              </div>

              <div>
                <label htmlFor="branch-admin-email">Email</label>
                <input
                  id="branch-admin-email"
                  type="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  placeholder="Enter email address"
                  disabled={saving}
                />
              </div>

              <div>
                <label htmlFor="branch-admin-phone">Phone (Optional)</label>
                <input
                  id="branch-admin-phone"
                  type="tel"
                  value={phone}
                  onChange={(event) => setPhone(event.target.value)}
                  placeholder="Enter phone number"
                  disabled={saving}
                />
              </div>

              <div>
                <label htmlFor="branch-admin-password">Password</label>
                <input
                  id="branch-admin-password"
                  type="password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  placeholder="Minimum 8 characters"
                  autoComplete="new-password"
                  disabled={saving}
                />
              </div>
            </>
            ) : (
              <>
                <div>
                  {loading ? (
                    <p>Loading available Branch Admins...</p>
                  ) : candidates.length > 0 ? (
                    <select
                      id="branch-admin-select"
                      value={selectedUser}
                      onChange={(event) => setSelectedUser(event.target.value)}
                      disabled={saving}
                    >
                      <option value="">Choose a Branch Admin</option>

                      {candidates.map((candidate) => (
                        <option
                          key={candidate.business_user_id}
                          value={candidate.business_user_id}
                        >
                          {candidate.full_name}
                          {candidate.email ? ` (${candidate.email})` : ''}
                        </option>
                      ))}
                    </select>
                  ) : null}

                  {!loading && candidates.length === 0 && !error && (
                    <p className="page-notice">
                      No available Branch Admins found for this Branch. Create new Admin.
                    </p>
                  )}
                </div>

                {candidates.length > 0 && (
                  <div>
                    <label htmlFor="branch-admin-notes">
                      Notes (Optional)
                    </label>

                    <textarea
                      id="branch-admin-notes"
                      value={notes}
                      onChange={(event) => setNotes(event.target.value)}
                      placeholder="Enter assignment notes"
                      rows={3}
                      disabled={saving}
                    />
                  </div>
                )}
              </>
            )}

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

          {(creating || (!loading && candidates.length > 0)) && (
            <button
              type="button"
              className="owner-profile-save"
              onClick={creating ? handleCreateAndAssign : handleAssign}
              disabled={
                saving ||
                (creating
                  ? !fullName.trim() || !email.trim() || !password
                  : loading || !selectedUser)
              }
            >
              {saving ? (
                'Please wait...'
              ) : creating ? (
                <>
                  <UserRoundPlus size={16} />
                  Create & Assign
                </>
              ) : (
                'Assign Admin'
              )}
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
