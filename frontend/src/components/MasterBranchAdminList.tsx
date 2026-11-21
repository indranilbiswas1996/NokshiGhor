
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
  Building2,
} from 'lucide-react'
import {
  branchApi,
  type MasterBranchAdmin,
} from '../api/branch'
import './BranchAdminList.css'

interface MasterBranchAdminListProps {
  onClose: () => void
}

interface GroupedMasterBranchAdmin {
  business_user_id: string
  user_id: string
  full_name: string
  email: string
  phone: string | null
  assignments: MasterBranchAdmin[]
}

export default function MasterBranchAdminList({
  onClose,
}: MasterBranchAdminListProps) {
  const [admins, setAdmins] = useState<MasterBranchAdmin[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')

  const loadAdmins = useCallback(async () => {
    setLoading(true)
    setError('')

    try {
      const response = await branchApi.getMasterBranchAdmins()
      setAdmins(response.admins ?? [])
    } catch (err) {
      const message = isAxiosError(err)
        ? err.response?.data?.detail
        : null

      setError(
        typeof message === 'string'
          ? message
          : 'Unable to load Master Branch Admins.'
      )
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadAdmins()
  }, [loadAdmins])

  // Group multiple Branch assignments under one Admin
  const groupedAdmins = useMemo<GroupedMasterBranchAdmin[]>(() => {
    const grouped = new Map<string, GroupedMasterBranchAdmin>()

    admins.forEach((admin) => {
      const existing = grouped.get(admin.business_user_id)

      if (existing) {
        existing.assignments.push(admin)
      } else {
        grouped.set(admin.business_user_id, {
          business_user_id: admin.business_user_id,
          user_id: admin.user_id,
          full_name: admin.full_name,
          email: admin.email,
          phone: admin.phone,
          assignments: [admin],
        })
      }
    })

    return Array.from(grouped.values()).map((admin) => ({
      ...admin,
      assignments: [...admin.assignments].sort(
        (a, b) =>
          a.branch_name.localeCompare(b.branch_name)
      ),
    }))
  }, [admins])

  // Search across Admin details and all assigned Branches
  const filteredAdmins = useMemo(() => {
    const query = search.trim().toLowerCase()

    if (!query) return groupedAdmins

    return groupedAdmins.filter((admin) => {
      const adminDetails = [
        admin.full_name,
        admin.email,
        admin.phone,
      ].some((value) => value?.toLowerCase().includes(query))

      const branchDetails = admin.assignments.some((assignment) =>
        [
          assignment.branch_name,
          assignment.assignment_status,
          assignment.notes,
        ].some((value) => value?.toLowerCase().includes(query))
      )

      return adminDetails || branchDetails
    })
  }, [groupedAdmins, search])

  return (
    <div className="owner-modal-overlay">
      <div
        className="owner-profile-modal branch-admin-list-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="master-branch-admin-list-title"
      >
        {/* Header */}
        <div className="owner-modal-header">
          <div>
            <h2 id="master-branch-admin-list-title">
              Master Branch Admins
            </h2>
            <p>All Branches · Business-wide Admin Assignments</p>
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

        {/* Body */}
        <div className="branch-admin-list-body">

          {/* Toolbar */}
          <div className="branch-admin-list-toolbar">
            <div>
              <h3>All Branch Admins</h3>
              <span>
                {groupedAdmins.length}{' '}
                {groupedAdmins.length === 1 ? 'Admin' : 'Admins'}
              </span>
            </div>

            <button
              type="button"
              className="owner-profile-cancel"
              onClick={() => void loadAdmins()}
              disabled={loading}
            >
              <RefreshCw size={15} />
              Refresh
            </button>
          </div>

          {/* Search */}
          <div className="branch-admin-search">
            <Search size={18} />

            <input
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search by admin, email, phone or branch..."
              aria-label="Search Master Branch Admins"
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

          {/* Loading */}
          {loading ? (
            <div className="branch-admin-list-message">
              Loading Master Branch Admins...
            </div>
          ) : error ? (
            <div className="page-notice error" role="alert">
              {error}

              <button
                type="button"
                className="owner-profile-cancel"
                onClick={() => void loadAdmins()}
              >
                Try Again
              </button>
            </div>
          ) : filteredAdmins.length === 0 ? (
            <div className="branch-admin-list-empty">
              <Users size={30} />

              <strong>
                {groupedAdmins.length === 0
                  ? 'No Branch Admins Found'
                  : 'No Matching Admins Found'}
              </strong>

              <span>
                {groupedAdmins.length === 0
                  ? 'There are currently no active Branch Admin assignments.'
                  : 'Try another name, email, phone or branch name.'}
              </span>
            </div>
          ) : (

            /* Grouped Admin Cards */
            <div className="branch-admin-cards">
              {filteredAdmins.map((admin) => (
                <article
                  key={admin.business_user_id}
                  className="branch-admin-card"
                >
                  {/* Admin Information */}
                  <div className="branch-admin-card-main">
                    <div className="branch-admin-avatar">
                      {admin.full_name.charAt(0).toUpperCase()}
                    </div>

                    <div className="branch-admin-identity">
                      <strong>{admin.full_name}</strong>
                      <span>{admin.email || 'No email available'}</span>
                    </div>

                    <span className="branch-admin-status active">
                      Active
                    </span>
                  </div>

                  {/* Admin Contact Details */}
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
                      <Building2 size={15} />
                      Assigned Branches: {admin.assignments.length}
                    </span>
                  </div>

                  {/* All Branch Assignments */}
                  <div className="branch-admin-notes">
                    <strong>Branch Details</strong>

                    {admin.assignments.map((assignment) => (
                      <div
                        key={assignment.assignment_id}
                        className="master-admin-branch-detail"
                      >
                        <span>
                          <Building2 size={15} />
                          <strong>{assignment.branch_name}</strong>
                        </span>

                        <span>
                          <CalendarDays size={14} />
                          Assigned:{' '}
                          {new Date(
                            assignment.assigned_at
                          ).toLocaleString()}
                        </span>

                        {assignment.notes && (
                          <span>
                            Notes: {assignment.notes}
                          </span>
                        )}
                      </div>
                    ))}
                  </div>
                </article>
              ))}
            </div>
          )}

          {/* List Count */}
          {!loading && !error && groupedAdmins.length > 0 && (
            <div className="branch-admin-list-footer">
              Showing {filteredAdmins.length} of {groupedAdmins.length} Admins
            </div>
          )}
        </div>

        {/* Footer */}
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
