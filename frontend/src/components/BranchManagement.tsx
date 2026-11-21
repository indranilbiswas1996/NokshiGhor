
import { useCallback, useEffect, useState } from 'react'
import { isAxiosError } from 'axios'
import {
  GitBranch,
  RefreshCw,
  LoaderCircle,
  MapPin,
  Phone,
  Mail,
  CheckCircle2,
  XCircle,
  Star,
  Plus,
  Pencil,
  X,
  Save,
} from 'lucide-react'
import { branchApi } from '../api/branch'
import type { Branch } from '../api/branch'
import './BranchManagement.css'

interface BranchManagementProps {
  bengali?: boolean
}

function getErrorMessage(error: unknown): string {
  if (isAxiosError(error)) {
    return error.response?.data?.detail || error.message || 'Something went wrong.'
  }

  return error instanceof Error ? error.message : 'Something went wrong.'
}

export default function BranchManagement({
  bengali = false,
}: BranchManagementProps) {
  const [branches, setBranches] = useState<Branch[]>([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState('')
  const [showCreateForm, setShowCreateForm] = useState(false)

const [createBranchSubmitting, setCreateBranchSubmitting] = useState(false)
const [createBranchError, setCreateBranchError] = useState('')

const [createBranchData, setCreateBranchData] = useState({
  branch_name: '',
  branch_code: '',
  address: '',
  phone: '',
  email: '',
})

  const [editingBranch, setEditingBranch] = useState<Branch | null>(null)

    const [showEditBranch, setShowEditBranch] = useState(false)
    
    const [branchEditSubmitting, setBranchEditSubmitting] = useState(false)
    const [branchEditError, setBranchEditError] = useState('')

    const [branchEditData, setBranchEditData] = useState({
    branch_name: '',
    branch_code: '',
    address: '',
    phone: '',
    email: '',
    })

  const loadBranches = useCallback(async (refresh = false) => {
    if (refresh) setRefreshing(true)
    else setLoading(true)

    setError('')

    try {
      const response = await branchApi.getBranches()
      setBranches(response.branches)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [])

const handleEditBranch = (branch: Branch) => {
  setEditingBranch(branch)

  setBranchEditData({
    branch_name: branch.branch_name,
    branch_code: branch.branch_code || '',
    address: branch.address || '',
    phone: branch.phone || '',
    email: branch.email || '',
  })

  setBranchEditError('')
  setShowEditBranch(true)
}

const handleSaveBranch = async () => {
  if (!editingBranch) return

  if (!branchEditData.branch_name.trim()) {
    setBranchEditError(
      bengali ? 'শাখার নাম দিতে হবে।' : 'Branch name is required.'
    )
    return
  }

  const phone = branchEditData.phone.trim()

  if (phone && !/^[6-9]\d{9}$/.test(phone)) {
    setBranchEditError(
      bengali
        ? 'সঠিক ১০ সংখ্যার ভারতীয় মোবাইল নম্বর দিন।'
        : 'Enter a valid 10-digit Indian mobile number.'
    )
    return
  }

  setBranchEditSubmitting(true)
  setBranchEditError('')

  try {
    await branchApi.updateBranch(editingBranch.id, {
      branch_name: branchEditData.branch_name.trim(),
      branch_code: branchEditData.branch_code.trim() || null,
      address: branchEditData.address.trim() || null,
      phone: phone || null,
      email: branchEditData.email.trim() || null,
    })

    setShowEditBranch(false)
    setEditingBranch(null)
    await loadBranches(true)
  } catch (err) {
    setBranchEditError(getErrorMessage(err))
  } finally {
    setBranchEditSubmitting(false)
  }
}


const handleCreateBranch = async () => {
  if (!createBranchData.branch_name.trim()) {
    setCreateBranchError(
      bengali ? 'শাখার নাম দিতে হবে।' : 'Branch name is required.'
    )
    return
  }

  const phone = createBranchData.phone.trim()

  if (phone && !/^[6-9]\d{9}$/.test(phone)) {
    setCreateBranchError(
      bengali
        ? 'সঠিক ১০ সংখ্যার ভারতীয় মোবাইল নম্বর দিন।'
        : 'Enter a valid 10-digit Indian mobile number.'
    )
    return
  }

  setCreateBranchSubmitting(true)
  setCreateBranchError('')

  try {
    await branchApi.createBranch({
      branch_name: createBranchData.branch_name.trim(),
      branch_code: createBranchData.branch_code.trim() || null,
      address: createBranchData.address.trim() || null,
      phone: phone || null,
      email: createBranchData.email.trim() || null,
    })

    setShowCreateForm(false)
    setCreateBranchData({
      branch_name: '',
      branch_code: '',
      address: '',
      phone: '',
      email: '',
    })

    await loadBranches(true)
  } catch (err) {
    setCreateBranchError(getErrorMessage(err))
  } finally {
    setCreateBranchSubmitting(false)
  }
}

  useEffect(() => {
    void loadBranches()
  }, [loadBranches])

  const activeBranches = branches.filter(
    (branch) => branch.is_active
  ).length

  const inactiveBranches = branches.length - activeBranches

  const formatDate = (value: string) =>
    new Date(value).toLocaleDateString(
      bengali ? 'bn-IN' : 'en-IN',
      { day: '2-digit', month: 'short', year: 'numeric' }
    )

  if (loading) {
    return (
      <div className="branch-loading">
        <LoaderCircle className="branch-spin" size={24} />
        <span>
          {bengali ? 'শাখার তথ্য লোড হচ্ছে...' : 'Loading branches...'}
        </span>
      </div>
    )
  }

  return (
    <section className="branch-page">
      <div className="branch-heading">
        <div>
          <div className="branch-eyebrow">BUSINESS MANAGEMENT</div>
          <h2>
            <GitBranch size={24} />
            {bengali ? 'শাখা পরিচালনা' : 'Branch Management'}
          </h2>
          <p>
            {bengali
              ? 'আপনার ব্যবসার সমস্ত শাখার তথ্য ও অবস্থা দেখুন।'
              : 'View all branches and their current status for this business.'}
          </p>
        </div>

        <div className="branch-heading-actions">
          <button
            type="button"
            className="branch-create-button"
            onClick={() => setShowCreateForm((previous) => !previous)}
          >
            <Plus size={17} />
            {bengali ? 'নতুন শাখা' : 'Create Branch'}
          </button>

          <button
            type="button"
            className="branch-refresh"
            onClick={() => void loadBranches(true)}
            disabled={refreshing}
          >
            <RefreshCw
              size={16}
              className={refreshing ? 'branch-spin' : ''}
            />
            {bengali ? 'রিফ্রেশ' : 'Refresh'}
          </button>
        </div>
      </div>
      
{showEditBranch && editingBranch && (
  <div
    className="owner-modal-overlay"
    onClick={() => {
      if (!branchEditSubmitting) {
        setShowEditBranch(false)
        setEditingBranch(null)
        setBranchEditError('')
      }
    }}
  >
    <div
      className="owner-profile-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="branch-edit-modal-title"
      onClick={(e) => e.stopPropagation()}
    >
      <div className="owner-modal-header">
        <div>
          <h3 id="branch-edit-modal-title">
            {bengali ? 'শাখার তথ্য সম্পাদনা' : 'Edit Branch'}
          </h3>
          <p>
            {bengali
              ? 'শাখার তথ্য আপডেট করুন।'
              : 'Update branch information.'}
          </p>
        </div>

        <button
          type="button"
          className="owner-close-button"
          onClick={() => {
            setShowEditBranch(false)
            setEditingBranch(null)
            setBranchEditError('')
          }}
          disabled={branchEditSubmitting}
        >
          <X size={18} />
        </button>
      </div>

      {branchEditError && (
        <div className="page-notice" role="alert">
          {branchEditError}
        </div>
      )}

      <div className="owner-profile-edit">
        <label>
          {bengali ? 'শাখার নাম *' : 'Branch Name *'}
          <input
            type="text"
            value={branchEditData.branch_name}
            onChange={(e) =>
              setBranchEditData((prev) => ({
                ...prev,
                branch_name: e.target.value,
              }))
            }
            maxLength={150}
            required
          />
        </label>

        <label>
          {bengali ? 'শাখা কোড' : 'Branch Code'}
          <input
            type="text"
            value={branchEditData.branch_code}
            onChange={(e) =>
              setBranchEditData((prev) => ({
                ...prev,
                branch_code: e.target.value,
              }))
            }
            maxLength={30}
          />
        </label>

        <label>
          {bengali ? 'ঠিকানা' : 'Address'}
          <textarea
            value={branchEditData.address}
            onChange={(e) =>
              setBranchEditData((prev) => ({
                ...prev,
                address: e.target.value,
              }))
            }
          />
        </label>

        <label>
          {bengali ? 'ফোন নম্বর' : 'Phone Number'}
          <input
            type="tel"
            value={branchEditData.phone}
            onChange={(e) =>
              setBranchEditData((prev) => ({
                ...prev,
                phone: e.target.value,
              }))
            }
            maxLength={30}
          />
        </label>

        <label>
          Email
          <input
            type="email"
            value={branchEditData.email}
            onChange={(e) =>
              setBranchEditData((prev) => ({
                ...prev,
                email: e.target.value,
              }))
            }
            maxLength={254}
          />
        </label>
      </div>

      <div className="owner-profile-actions">
        <button
          type="button"
          className="owner-profile-cancel"
          onClick={() => {
            setShowEditBranch(false)
            setEditingBranch(null)
            setBranchEditError('')
          }}
          disabled={branchEditSubmitting}
        >
          <X size={15} />
          {bengali ? 'বাতিল' : 'Cancel'}
        </button>

        <button
          type="button"
          className="owner-profile-save"
          onClick={() => void handleSaveBranch()}
          disabled={branchEditSubmitting}
        >
          {branchEditSubmitting ? (
            <LoaderCircle size={15} className="branch-spin" />
          ) : (
            <Save size={15} />
          )}
          {branchEditSubmitting
            ? (bengali ? 'সংরক্ষণ হচ্ছে...' : 'Saving...')
            : (bengali ? 'সংরক্ষণ করুন' : 'Save Changes')}
        </button>
      </div>
    </div>
  </div>
)}

      
{showCreateForm && (
  <div
    className="owner-modal-overlay"
    onClick={() => {
      if (!createBranchSubmitting) {
        setShowCreateForm(false)
        setCreateBranchError('')
      }
    }}
  >
    <div
      className="owner-profile-modal"
      role="dialog"
      aria-modal="true"
      aria-labelledby="branch-create-modal-title"
      onClick={(e) => e.stopPropagation()}
    >
      <div className="owner-modal-header">
        <div>
          <h3 id="branch-create-modal-title">
            {bengali ? 'নতুন শাখা যোগ করুন' : 'Create New Branch'}
          </h3>
          <p>
            {bengali
              ? 'নতুন শাখার তথ্য পূরণ করুন।'
              : 'Enter the new branch information.'}
          </p>
        </div>

        <button
          type="button"
          className="owner-close-button"
          onClick={() => {
            setShowCreateForm(false)
            setCreateBranchError('')
          }}
          disabled={createBranchSubmitting}
        >
          <X size={18} />
        </button>
      </div>

      {createBranchError && (
        <div className="page-notice" role="alert">
          {createBranchError}
        </div>
      )}

      <div className="owner-profile-edit">
        <label>
          {bengali ? 'শাখার নাম *' : 'Branch Name *'}
          <input
            type="text"
            value={createBranchData.branch_name}
            onChange={(e) =>
              setCreateBranchData((prev) => ({
                ...prev,
                branch_name: e.target.value,
              }))
            }
            maxLength={150}
            required
          />
        </label>

        <label>
          {bengali ? 'শাখা কোড' : 'Branch Code'}
          <input
            type="text"
            value={createBranchData.branch_code}
            onChange={(e) =>
              setCreateBranchData((prev) => ({
                ...prev,
                branch_code: e.target.value,
              }))
            }
            maxLength={30}
          />
        </label>

        <label>
          {bengali ? 'ঠিকানা' : 'Address'}
          <textarea
            value={createBranchData.address}
            onChange={(e) =>
              setCreateBranchData((prev) => ({
                ...prev,
                address: e.target.value,
              }))
            }
          />
        </label>

        <label>
          {bengali ? 'ফোন নম্বর' : 'Phone Number'}
          <input
            type="tel"
            value={createBranchData.phone}
            onChange={(e) =>
              setCreateBranchData((prev) => ({
                ...prev,
                phone: e.target.value,
              }))
            }
            maxLength={30}
          />
        </label>

        <label>
          Email
          <input
            type="email"
            value={createBranchData.email}
            onChange={(e) =>
              setCreateBranchData((prev) => ({
                ...prev,
                email: e.target.value,
              }))
            }
            maxLength={254}
          />
        </label>
      </div>

      <div className="owner-profile-actions">
        <button
          type="button"
          className="owner-profile-cancel"
          onClick={() => {
            setShowCreateForm(false)
            setCreateBranchError('')
          }}
          disabled={createBranchSubmitting}
        >
          <X size={15} />
          {bengali ? 'বাতিল' : 'Cancel'}
        </button>

        <button
          type="button"
          className="owner-profile-save"
          onClick={() => void handleCreateBranch()}
          disabled={createBranchSubmitting}
        >
          {createBranchSubmitting ? (
            <LoaderCircle size={15} className="branch-spin" />
          ) : (
            <Plus size={15} />
          )}
          {createBranchSubmitting
            ? (bengali ? 'তৈরি হচ্ছে...' : 'Creating...')
            : (bengali ? 'শাখা তৈরি করুন' : 'Create Branch')}
        </button>
      </div>
    </div>
  </div>
)}

      
      {error && (
        <div className="branch-alert" role="alert">
          {error}
          <button onClick={() => void loadBranches()}>
            {bengali ? 'আবার চেষ্টা করুন' : 'Retry'}
          </button>
        </div>
      )}

      <div className="branch-summary">
        <div className="branch-summary-card">
          <div className="branch-summary-icon total">
            <GitBranch size={21} />
          </div>
          <div>
            <span>{bengali ? 'মোট শাখা' : 'Total Branches'}</span>
            <strong>{branches.length}</strong>
          </div>
        </div>

        <div className="branch-summary-card">
          <div className="branch-summary-icon active">
            <CheckCircle2 size={21} />
          </div>
          <div>
            <span>{bengali ? 'সক্রিয় শাখা' : 'Active Branches'}</span>
            <strong>{activeBranches}</strong>
          </div>
        </div>

        <div className="branch-summary-card">
          <div className="branch-summary-icon inactive">
            <XCircle size={21} />
          </div>
          <div>
            <span>{bengali ? 'নিষ্ক্রিয় শাখা' : 'Inactive Branches'}</span>
            <strong>{inactiveBranches}</strong>
          </div>
        </div>
      </div>

      <div className="branch-card">
        <div className="branch-card-heading">
          <div>
            <h3>{bengali ? 'শাখার তালিকা' : 'Branches List'}</h3>
            <span>
              {bengali
                ? 'এই ব্যবসার অধীনে থাকা সমস্ত শাখা'
                : 'All branches associated with this business'}
            </span>
          </div>

          <span className="branch-count">
            {branches.length} {bengali ? 'টি' : 'Branch(es)'}
          </span>
        </div>

        {branches.length === 0 ? (
          <div className="branch-empty">
            <GitBranch size={36} />
            <strong>
              {bengali ? 'কোনো শাখা পাওয়া যায়নি' : 'No branches found'}
            </strong>
          </div>
        ) : (
          <div className="branch-list">
            {branches.map((branch) => (
              <article className="branch-list-item" key={branch.id}>
                <div className="branch-avatar">
                  <GitBranch size={22} />
                </div>

                <div className="branch-details">
                  <div className="branch-name-row">
                    <strong>{branch.branch_name}</strong>

                    {branch.is_default && (
                      <span className="branch-default">
                        <Star size={12} />
                        {bengali ? 'প্রধান শাখা' : 'Main Branch'}
                      </span>
                    )}

                    <span
                      className={`branch-status ${
                        branch.is_active ? 'active' : 'inactive'
                      }`}
                    >
                      {branch.is_active
                        ? (bengali ? 'সক্রিয়' : 'Active')
                        : (bengali ? 'নিষ্ক্রিয়' : 'Inactive')}
                    </span>
                  </div>

                  <div className="branch-contact">
                    {branch.branch_code && (
                      <span>
                        <GitBranch size={14} />
                        {branch.branch_code}
                      </span>
                    )}

                    {branch.address && (
                      <span>
                        <MapPin size={14} />
                        {branch.address}
                      </span>
                    )}

                    {branch.phone && (
                      <span>
                        <Phone size={14} />
                        {branch.phone}
                      </span>
                    )}

                    {branch.email && (
                      <span>
                        <Mail size={14} />
                        {branch.email}
                      </span>
                    )}
                  </div>

                  <small>
                    {bengali ? 'তৈরি হয়েছে: ' : 'Created: '}
                    {formatDate(branch.created_at)}
                  </small>
                                    <div className="branch-card-actions">
                    <button
                      type="button"
                      className="branch-icon-button"
                      onClick={() => handleEditBranch(branch)}
                      title={bengali ? 'শাখা সম্পাদনা' : 'Edit Branch'}
                    >
                      <Pencil size={16} />
                      {bengali ? 'সম্পাদনা' : 'Edit'}
                    </button>
                  </div>
                </div>
              </article>
            ))}
          </div>
        )}
      </div>
    </section>
  )
}
