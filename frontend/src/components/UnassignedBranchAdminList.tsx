import { useCallback, useEffect, useMemo, useState } from 'react'
import { isAxiosError } from 'axios'
import {
  X,
  RefreshCw,
  Search,
  Users,
  Mail,
  Phone,
  GitBranchPlus,
  LoaderCircle,
} from 'lucide-react'
import {
  branchApi,
  type Branch,
  type UnassignedBranchAdmin,
} from '../api/branch'
import './BranchAdminList.css'
import MasterBranchAdminAuditModal from './MasterBranchAdminAuditModal'

interface UnassignedBranchAdminListProps {
  onClose: () => void
}

function getLoadErrorMessage(error: unknown): string {
  const message = isAxiosError(error)
    ? error.response?.data?.detail
    : null

  return typeof message === 'string'
    ? message
    : 'Unable to load unassigned Branch Admins.'
}

export default function UnassignedBranchAdminList({
  onClose,
}: UnassignedBranchAdminListProps) {
  const [admins, setAdmins] = useState<UnassignedBranchAdmin[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [selectedAuditAdmin, setSelectedAuditAdmin] = useState<string | null>(
    null,
  )
  const [assigningAdmin, setAssigningAdmin] =
    useState<UnassignedBranchAdmin | null>(null)
  const [branches, setBranches] = useState<Branch[]>([])
  const [branchesLoading, setBranchesLoading] = useState(false)
  const [selectedBranchId, setSelectedBranchId] = useState('')
  const [assignmentSaving, setAssignmentSaving] = useState(false)
  const [assignmentError, setAssignmentError] = useState('')
  const [assignmentMessage, setAssignmentMessage] = useState('')

  const loadAdmins = useCallback(async () => {
    try {
      const response = await branchApi.getUnassignedBranchAdmins()
      setAdmins(response.admins)
      setError('')
    } catch (err) {
      setError(getLoadErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [])

  const handleOpenAssignment = async (admin: UnassignedBranchAdmin) => {
    setAssigningAdmin(admin)
    setBranches([])
    setSelectedBranchId('')
    setAssignmentError('')
    setAssignmentMessage('')
    setBranchesLoading(true)

    try {
      const response = await branchApi.getBranches()
      setBranches(response.branches.filter((branch) => branch.is_active))
    } catch (err) {
      const message = isAxiosError(err)
        ? err.response?.data?.detail
        : null

      setAssignmentError(
        typeof message === 'string' ? message : 'Unable to load active branches.'
      )
    } finally {
      setBranchesLoading(false)
    }
  }

  const handleAssignAdmin = async () => {
    if (!assigningAdmin || !selectedBranchId) return

    const branch = branches.find((item) => item.id === selectedBranchId)
    if (!branch) return

    setAssignmentSaving(true)
    setAssignmentError('')

    try {
      await branchApi.assignBranchAdmin(selectedBranchId, {
        business_user_id: assigningAdmin.business_user_id,
      })

      setAdmins((current) =>
        current.filter(
          (admin) => admin.business_user_id !== assigningAdmin.business_user_id
        )
      )
      setAssignmentMessage(`${assigningAdmin.full_name} assigned to ${branch.branch_name}.`)
      setAssigningAdmin(null)
      setSelectedBranchId('')
    } catch (err) {
      const message = isAxiosError(err)
        ? err.response?.data?.detail
        : null

      setAssignmentError(
        typeof message === 'string' ? message : 'Unable to assign Branch Admin.'
      )
    } finally {
      setAssignmentSaving(false)
    }
  }

  useEffect(() => {
    let current = true

    void branchApi.getUnassignedBranchAdmins()
      .then((response) => {
        if (current) {
          setAdmins(response.admins)
        }
      })
      .catch((err: unknown) => {
        if (current) {
          setError(getLoadErrorMessage(err))
        }
      })
      .finally(() => {
        if (current) {
          setLoading(false)
        }
      })

    return () => {
      current = false
    }
  }, [])

  const sortedAdmins = useMemo(
    () => [...admins].sort((a, b) => a.full_name.localeCompare(b.full_name)),
    [admins],
  )

  const filteredAdmins = useMemo(() => {
    const query = search.trim().toLowerCase()

    if (!query) return sortedAdmins

    return sortedAdmins.filter((admin) =>
      [
        admin.full_name,
        admin.email,
        admin.phone,
      ].some((value) => value?.toLowerCase().includes(query))
    )
  }, [sortedAdmins, search])

  return (
    <div className="owner-modal-overlay">
      <div
        className="owner-profile-modal branch-admin-list-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="unassigned-branch-admin-list-title"
      >
        <div className="owner-modal-header">
          <div>
            <h2 id="unassigned-branch-admin-list-title">
              Unassigned Branch Admins
            </h2>
            <p>Active Branch Admins with no active branch assignment</p>
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
              <h3>Admins Not Assigned to Any Branch</h3>
              <span>
                {admins.length} {admins.length === 1 ? 'Admin' : 'Admins'}
              </span>
            </div>

            <button
              type="button"
              className="owner-profile-cancel"
              onClick={() => {
                setLoading(true)
                setError('')
                void loadAdmins()
              }}
              disabled={loading}
            >
              <RefreshCw
                size={15}
                className={loading ? 'branch-admin-refresh-spin' : ''}
              />
              Refresh
            </button>
          </div>

          {assignmentMessage && (
            <div className="page-notice" role="status">
              {assignmentMessage}
            </div>
          )}

          <div className="branch-admin-search">
            <Search size={18} />
            <input
              type="search"
              value={search}
              onChange={(event) => setSearch(event.target.value)}
              placeholder="Search by name, email or phone..."
              aria-label="Search Unassigned Branch Admins"
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
              Loading unassigned Branch Admins...
            </div>
          ) : error ? (
            <div className="page-notice error" role="alert">
              {error}
              <button
                type="button"
                className="owner-profile-cancel"
                onClick={() => {
                  setLoading(true)
                  setError('')
                  void loadAdmins()
                }}
              >
                Try Again
              </button>
            </div>
          ) : filteredAdmins.length === 0 ? (
            <div className="branch-admin-list-empty">
              <Users size={30} />
              <strong>
                {admins.length === 0
                  ? 'All Branch Admins Are Assigned'
                  : 'No Matching Admins Found'}
              </strong>
              <span>
                {admins.length === 0
                  ? 'There are no active Branch Admins without a branch assignment.'
                  : 'Try another name, email or phone number.'}
              </span>
            </div>
          ) : (
            <div className="branch-admin-cards">
              {filteredAdmins.map((admin) => (
                <article
                  key={admin.business_user_id}
                  className="branch-admin-card"
                >
                  <button
                    type="button"
                    className="branch-admin-card-main branch-admin-card-audit"
                    aria-label={`View audit details for ${admin.full_name}`}
                    onClick={() => setSelectedAuditAdmin(admin.business_user_id)}
                  >
                    <div className="branch-admin-avatar">
                      {admin.full_name.charAt(0).toUpperCase()}
                    </div>
                    <div className="branch-admin-identity">
                      <strong>{admin.full_name}</strong>
                      <span>{admin.email || 'No email available'}</span>
                    </div>
                    <span className="branch-admin-status inactive">
                      Unassigned
                    </span>
                  </button>

                  <div className="branch-admin-card-meta">
                    <span>
                      <Mail size={15} />
                      {admin.email || 'No email available'}
                    </span>
                    <span>
                      <Phone size={15} />
                      {admin.phone || 'No phone available'}
                    </span>
                  </div>

                  <div className="branch-admin-card-actions">
                    <button
                      type="button"
                      className="branch-admin-assign-button"
                      onClick={() => void handleOpenAssignment(admin)}
                    >
                      <GitBranchPlus size={16} />
                      Assign to Branch
                    </button>
                  </div>
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
      {assigningAdmin && (
        <div className="owner-modal-overlay">
          <div
            className="owner-profile-modal branch-admin-list-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="assign-unassigned-branch-admin-title"
          >
            <div className="owner-modal-header">
              <div>
                <h2 id="assign-unassigned-branch-admin-title">
                  Assign Branch Admin
                </h2>
                <p>{assigningAdmin.full_name}</p>
              </div>
              <button
                type="button"
                className="owner-close-button"
                onClick={() => setAssigningAdmin(null)}
                disabled={assignmentSaving}
                aria-label="Close"
              >
                <X size={20} />
              </button>
            </div>

            <div className="owner-profile-edit">
              <div>
                <label htmlFor="unassigned-admin-branch">Branch</label>
                {branchesLoading ? (
                  <p>Loading active branches...</p>
                ) : branches.length > 0 ? (
                  <select
                    id="unassigned-admin-branch"
                    value={selectedBranchId}
                    onChange={(event) => setSelectedBranchId(event.target.value)}
                    disabled={assignmentSaving}
                  >
                    <option value="">Choose a branch</option>
                    {branches.map((branch) => (
                      <option key={branch.id} value={branch.id}>
                        {branch.branch_name}
                        {branch.branch_code ? ` (${branch.branch_code})` : ''}
                      </option>
                    ))}
                  </select>
                ) : !assignmentError ? (
                  <p className="page-notice">
                    No active branches are available for assignment.
                  </p>
                ) : null}
              </div>

              {assignmentError && (
                <div className="page-notice error" role="alert">
                  {assignmentError}
                </div>
              )}
            </div>

            <div className="owner-profile-actions">
              <button
                type="button"
                className="owner-profile-cancel"
                onClick={() => setAssigningAdmin(null)}
                disabled={assignmentSaving}
              >
                Cancel
              </button>
              <button
                type="button"
                className="owner-profile-save"
                onClick={() => void handleAssignAdmin()}
                disabled={
                  assignmentSaving || branchesLoading || !selectedBranchId
                }
              >
                {assignmentSaving ? (
                  <LoaderCircle size={15} className="branch-admin-refresh-spin" />
                ) : (
                  <GitBranchPlus size={15} />
                )}
                {assignmentSaving ? 'Assigning...' : 'Assign Admin'}
              </button>
            </div>
          </div>
        </div>
      )}
      {selectedAuditAdmin && (
        <MasterBranchAdminAuditModal
          businessUserId={selectedAuditAdmin}
          onClose={() => setSelectedAuditAdmin(null)}
        />
      )}
    </div>
  )
}
