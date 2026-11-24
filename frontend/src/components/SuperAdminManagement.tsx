import { useCallback, useEffect, useState } from 'react'
import { isAxiosError } from 'axios'
import {
  Building2,
  CheckCircle2,
  LoaderCircle,
  Plus,
  RefreshCw,
  XCircle,
} from 'lucide-react'
import {
  superAdminApi,
  type ManagedBusiness,
} from '../api/superAdmin'
import './SuperAdminManagement.css'

interface SuperAdminManagementProps {
  onClose: () => void
}

const businessTypes: ManagedBusiness['business_type'][] = [
  'electrical',
  'interior',
  'both',
  'other',
]

function getErrorMessage(error: unknown): string {
  if (isAxiosError(error)) {
    const detail = error.response?.data?.detail
    if (typeof detail === 'string') return detail
  }
  return error instanceof Error ? error.message : 'Something went wrong.'
}

export default function SuperAdminManagement({ onClose }: SuperAdminManagementProps) {
  const [businesses, setBusinesses] = useState<ManagedBusiness[]>([])
  const [businessName, setBusinessName] = useState('')
  const [businessType, setBusinessType] = useState<ManagedBusiness['business_type']>('both')
  const [loading, setLoading] = useState(true)
  const [creating, setCreating] = useState(false)
  const [updatingId, setUpdatingId] = useState<string | null>(null)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const loadBusinesses = useCallback(async () => {
    setError('')
    try {
      const response = await superAdminApi.getBusinesses()
      setBusinesses(response.businesses)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadBusinesses()
  }, [loadBusinesses])

  const handleCreate = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    if (!businessName.trim()) {
      setError('Business name is required.')
      return
    }

    setCreating(true)
    setError('')
    setNotice('')
    try {
      const created = await superAdminApi.createBusiness({
        business_name: businessName.trim(),
        business_type: businessType,
      })
      setBusinesses((current) =>
        [...current, created].sort((a, b) => a.business_name.localeCompare(b.business_name))
      )
      setBusinessName('')
      setNotice(`${created.business_name} created. It is now available in business selection.`)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setCreating(false)
    }
  }

  const handleStatusChange = async (business: ManagedBusiness) => {
    const nextStatus = business.status === 'active' ? 'inactive' : 'active'
    const confirmed = window.confirm(
      `${nextStatus === 'inactive' ? 'Deactivate' : 'Activate'} ${business.business_name}?`
    )
    if (!confirmed) return

    setUpdatingId(business.id)
    setError('')
    setNotice('')
    try {
      const updated = await superAdminApi.setBusinessStatus(business.id, nextStatus)
      setBusinesses((current) =>
        current.map((item) => item.id === updated.id ? updated : item)
      )
      setNotice(`${updated.business_name} is now ${updated.status}.`)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setUpdatingId(null)
    }
  }

  return (
    <main className="super-admin-page">
      <header className="super-admin-heading">
        <div>
          <span>PLATFORM ADMINISTRATION</span>
          <h1><Building2 size={23} /> Business Management</h1>
          <p>Create businesses and manage their availability.</p>
        </div>
        <button type="button" className="outline-button" onClick={onClose}>
          Back
        </button>
      </header>

      {error && <div className="super-admin-alert error" role="alert">{error}</div>}
      {notice && <div className="super-admin-alert" role="status">{notice}</div>}

      <form className="super-admin-create" onSubmit={(event) => void handleCreate(event)}>
        <label>
          Business name
          <input
            value={businessName}
            onChange={(event) => setBusinessName(event.target.value)}
            maxLength={200}
            required
          />
        </label>
        <label>
          Business type
          <select
            value={businessType}
            onChange={(event) => setBusinessType(event.target.value as ManagedBusiness['business_type'])}
          >
            {businessTypes.map((type) => (
              <option key={type} value={type}>{type[0].toUpperCase() + type.slice(1)}</option>
            ))}
          </select>
        </label>
        <button type="submit" className="primary-button" disabled={creating}>
          {creating ? <LoaderCircle size={16} className="super-admin-spin" /> : <Plus size={16} />}
          {creating ? 'Creating...' : 'Create Business'}
        </button>
      </form>

      <section className="super-admin-businesses">
        <div className="super-admin-list-heading">
          <div>
            <h2>Businesses</h2>
            <span>{businesses.length} total</span>
          </div>
          <button
            type="button"
            className="outline-button"
            onClick={() => {
              setLoading(true)
              void loadBusinesses()
            }}
            disabled={loading}
            aria-label="Refresh businesses"
            title="Refresh businesses"
          >
            <RefreshCw size={16} className={loading ? 'super-admin-spin' : ''} />
          </button>
        </div>

        {loading ? (
          <p className="super-admin-empty">Loading businesses...</p>
        ) : businesses.length === 0 ? (
          <p className="super-admin-empty">No businesses have been created yet.</p>
        ) : (
          <div className="super-admin-table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Business</th>
                  <th>Type</th>
                  <th>Status</th>
                  <th aria-label="Actions" />
                </tr>
              </thead>
              <tbody>
                {businesses.map((business) => (
                  <tr key={business.id}>
                    <td>{business.business_name}</td>
                    <td>{business.business_type}</td>
                    <td>
                      <span className={`super-admin-status ${business.status}`}>
                        {business.status}
                      </span>
                    </td>
                    <td>
                      <button
                        type="button"
                        className="super-admin-status-action"
                        onClick={() => void handleStatusChange(business)}
                        disabled={updatingId === business.id}
                      >
                        {updatingId === business.id ? (
                          <LoaderCircle size={15} className="super-admin-spin" />
                        ) : business.status === 'active' ? (
                          <XCircle size={15} />
                        ) : (
                          <CheckCircle2 size={15} />
                        )}
                        {updatingId === business.id
                          ? 'Saving...'
                          : business.status === 'active' ? 'Deactivate' : 'Activate'}
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </main>
  )
}
