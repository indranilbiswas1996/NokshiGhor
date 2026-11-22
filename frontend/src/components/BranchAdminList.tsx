
import { useCallback, useEffect, useMemo, useState } from 'react'
import { isAxiosError } from 'axios'
import {
  X,
  RefreshCw,
  Search,
  Users,
  Mail,
  Phone,
  CalendarDays,
  ShieldOff,
} from 'lucide-react'
import { branchApi, type BranchAdmin } from '../api/branch'
import './BranchAdminList.css'
import BranchAdminRevokeModal from './BranchAdminRevokeModal'

interface BranchAdminListProps {
  branchId: string
  branchName: string
  onClose: () => void
}

export default function BranchAdminList({
  branchId,
  branchName,
  onClose,
}: BranchAdminListProps) {
  const [admins, setAdmins] = useState<BranchAdmin[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [selectedRevoke, setSelectedRevoke] = useState<{
    assignmentId: string
    adminName: string
  } | null>(null)

  const loadAdmins = useCallback(async () => {
    setLoading(true)
    setError('')

    try {
      const response = await branchApi.getBranchAdmins(branchId)
      setAdmins(response.admins)
    } catch (err) {
      const message = isAxiosError(err)
        ? err.response?.data?.detail
        : null

      setError(
        typeof message === 'string'
          ? message
          : 'Unable to load Branch Admins.'
      )
    } finally {
      setLoading(false)
    }
  }, [branchId])

  useEffect(() => {
    void loadAdmins()
  }, [loadAdmins])

  const filteredAdmins = useMemo(() => {
    const query = search.trim().toLowerCase()

    if (!query) return admins

    return admins.filter((admin) =>
      [
        admin.full_name,
        admin.email,
        admin.phone,
        admin.assignment_status,
      ].some((value) => value?.toLowerCase().includes(query))
    )
  }, [admins, search])

  return (
    <div className="owner-modal-overlay">
      <div
        className="owner-profile-modal branch-admin-list-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="branch-admin-list-title"
      >
        <div className="owner-modal-header">
          <div>
            <h2 id="branch-admin-list-title">Branch Admins</h2>
            <p>{branchName}</p>
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

        <div className="branch-admin-list-body">
          <div className="branch-admin-list-toolbar">
            <div>
              <h3>Assigned Admins</h3>
              <span>
                {admins.length} {admins.length === 1 ? 'Admin' : 'Admins'} assigned
              </span>
            </div>

            <button
              type="button"
              className="owner-profile-cancel"
              onClick={() => void loadAdmins()}
              disabled={loading}
            >
              <RefreshCw
                size={15}
                className={loading ? 'branch-admin-refresh-spin' : ''}
              />
              Refresh
            </button>
          </div>

          <div className="branch-admin-search">
            <Search size={18} />
            <input
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search by name, email or phone..."
              aria-label="Search Branch Admins"
            />
            {search && (
              <button
                type="button"
                onClick={() => setSearch('')}
                aria-label="Clear search"
              >
                <X size={16} />
              </button>
            )}
          </div>

          {loading ? (
            <div className="branch-admin-list-message">
              Loading assigned Admins...
            </div>
          ) : error ? (
            <div className="page-notice error" role="alert">
              {error}
            </div>
          ) : filteredAdmins.length === 0 ? (
            <div className="branch-admin-list-empty">
              <Users size={30} />
              <strong>
                {admins.length === 0
                  ? 'No Admins assigned to this Branch'
                  : 'No matching Admins found'}
              </strong>
              <span>
                {admins.length === 0
                  ? 'Assign a Branch Admin to manage this Branch.'
                  : 'Try another name, email or phone number.'}
              </span>
            </div>
          ) : (
            <div className="branch-admin-cards">
              {filteredAdmins.map((admin) => (
                <article
                  key={admin.assignment_id}
                  className="branch-admin-card"
                >
                  <div className="branch-admin-card-main">
                    <div className="branch-admin-avatar">
                      {admin.full_name.charAt(0).toUpperCase()}
                    </div>

                    <div className="branch-admin-identity">
                      <strong>{admin.full_name}</strong>
                      <span>{admin.email || 'No email available'}</span>
                    </div>

                    <span
                      className={`branch-admin-status ${
                        admin.assignment_status === 'active'
                          ? 'active'
                          : 'inactive'
                      }`}
                    >
                      {admin.assignment_status}
                    </span>
                  </div>

                  <div className="branch-admin-card-meta">
                    <span>
                      <Mail size={15} />
                      {admin.email || 'No email available'}
                    </span>

                    <span>
                      <Phone size={15} />
                      {admin.phone || 'No phone available'}
                    </span>

                    <span>
                      <CalendarDays size={15} />
                      Assigned: {new Date(admin.assigned_at).toLocaleString()}
                    </span>
                  </div>

                  {admin.notes && (
                    <div className="branch-admin-notes">
                      Notes: {admin.notes}
                    </div>
                  )}
                  {admin.assignment_status === 'active' && (
                    <button
                      type="button"
                      className="branch-admin-revoke-action"
                      onClick={(event) => {
                        event.stopPropagation()
                        setSelectedRevoke({
                          assignmentId: admin.assignment_id,
                          adminName: admin.full_name,
                        })
                      }}
                    >
                      <ShieldOff size={14} />
                      Revoke Access
                    </button>
                  )}
                </article>
              ))}
            </div>
          )}

          {!loading && !error && admins.length > 0 && (
            <div className="branch-admin-list-footer">
              Showing {filteredAdmins.length} of {admins.length} Admins
            </div>
          )}
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
            {selectedRevoke && (
        <BranchAdminRevokeModal
          assignmentId={selectedRevoke.assignmentId}
          adminName={selectedRevoke.adminName}
          branchName={branchName}
          onClose={() => setSelectedRevoke(null)}
          onSuccess={() => {
            void loadAdmins()
          }}
        />
      )}
    </div>
  )
}
