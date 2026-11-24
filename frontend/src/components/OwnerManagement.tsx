import { useCallback, useEffect, useState } from 'react'
import { isAxiosError } from 'axios'
import {
  Users,
  UserRound,
  UserCheck,
  UserX,
  RefreshCw,
  LoaderCircle,
  Mail,
  Phone,
  ShieldCheck,
  UserPlus,
  X,
  Pencil,
  Save,
} from 'lucide-react'
import { ownerApi } from '../api/owner'
import type { Owner } from '../types/owner'
import './OwnerManagement.css'
import type { OwnerCreateRequest } from '../types/owner'
import { authApi } from '../api/auth'
interface OwnerManagementProps {
  bengali?: boolean
}
function getErrorMessage(error: unknown): string {
  if (isAxiosError(error)) {
    return error.response?.data?.detail || error.message || 'Something went wrong.'
  }

  return error instanceof Error ? error.message : 'Something went wrong.'
}

export default function OwnerManagement({
  bengali = false,
}: OwnerManagementProps) {
  const [owners, setOwners] = useState<Owner[]>([])
  const [currentUserId, setCurrentUserId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState('')
  const [showCreateForm, setShowCreateForm] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [updatingMembershipId, setUpdatingMembershipId] = useState<string | null>(null)
  const [showEditProfile, setShowEditProfile] = useState(false)
  const [profileSubmitting, setProfileSubmitting] = useState(false)
  const [profileError, setProfileError] = useState('')
  const [profileData, setProfileData] = useState({
    full_name: '',
    phone: '',
  })
  const [formData, setFormData] = useState<OwnerCreateRequest>({
    full_name: '',
    email: '',
    phone: '',
    password: '',
  })
  const loadOwners = useCallback(async (refresh = false) => {
    if (refresh) setRefreshing(true)
    else setLoading(true)

    setError('')

    try {
      const response = await ownerApi.getOwners()
      setOwners(response.owners)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [])
  const handleCreateOwner = async () => {
    if (!formData.full_name.trim() || !formData.email.trim()) {
      setError(
        bengali
          ? 'নাম এবং Email অবশ্যই দিতে হবে।'
          : 'Name and Email are required.'
      )
      return
    }
    const phone = formData.phone?.trim() || ''

    if (phone && !/^[6-9]\d{9}$/.test(phone)) {
      setError(
        bengali
          ? 'সঠিক ১০ সংখ্যার ভারতীয় মোবাইল নম্বর দিন।'
          : 'Enter a valid 10-digit Indian mobile number.'
      )
      return
    }
    if (formData.password && formData.password.length < 8) {
      setError(
        bengali
          ? 'Password কমপক্ষে ৮ অক্ষরের হতে হবে।'
          : 'Password must be at least 8 characters.'
      )
      return
    }

    setSubmitting(true)
    setError('')

    try {
      await ownerApi.createOwner({
        ...formData,
        full_name: formData.full_name.trim(),
        email: formData.email.trim().toLowerCase(),
        phone: formData.phone?.trim() || null,
        password: formData.password || null,
      })

      setFormData({
        full_name: '',
        email: '',
        phone: '',
        password: '',
      })

      setShowCreateForm(false)
      await loadOwners()
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setSubmitting(false)
    }
  }
  const handleOwnerStatusChange = async (owner: Owner) => {
  const nextStatus = owner.status === 'active' ? 'inactive' : 'active'

  const confirmed = window.confirm(
    bengali
      ? nextStatus === 'inactive'
        ? 'এই মালিককে নিষ্ক্রিয় করতে চান?'
        : 'এই মালিককে আবার সক্রিয় করতে চান?'
      : nextStatus === 'inactive'
        ? `Deactivate ${owner.full_name}?`
        : `Reactivate ${owner.full_name}?`
  )

  if (!confirmed) return

  setUpdatingMembershipId(owner.membership_id)
  setError('')

  try {
    await ownerApi.setOwnerStatus(owner.membership_id, {
      status: nextStatus,
    })
    await loadOwners(true)
  } catch (err) {
    setError(getErrorMessage(err))
  } finally {
    setUpdatingMembershipId(null)
  }
}

  const handleEditProfile = (owner: Owner) => {
    setProfileData({
      full_name: owner.full_name,
      phone: owner.phone || '',
    })
    setShowEditProfile(true)
    setProfileError('')
  }

  
  const handleSaveProfile = async () => {
    if (!profileData.full_name.trim()) {
      setProfileError(
        bengali ? 'সম্পূর্ণ নাম দিতে হবে।' : 'Full name is required.'
      )
      return
    }

    const phone = profileData.phone.trim()

    if (phone && !/^[6-9]\d{9}$/.test(phone)) {
      setProfileError(
        bengali
          ? 'সঠিক ১০ সংখ্যার ভারতীয় মোবাইল নম্বর দিন।'
          : 'Enter a valid 10-digit Indian mobile number.'
      )
      return
    }

    setProfileSubmitting(true)
    setProfileError('')

    try {
      await ownerApi.updateMyProfile({
        full_name: profileData.full_name.trim(),
        phone: phone || null,
      })

      setShowEditProfile(false)
      await loadOwners(true)
    } catch (err) {
      setProfileError(getErrorMessage(err))
    } finally {
      setProfileSubmitting(false)
    }
  }


  useEffect(() => {
    let mounted = true

    authApi.getProfile()
      .then((user) => {
        if (mounted) {
          setCurrentUserId(user.id)
        }
      })
      .catch((err) => {
        if (mounted) {
          setError(getErrorMessage(err))
        }
      })

    return () => {
      mounted = false
    }
  }, [])
  useEffect(() => {
    void loadOwners()
  }, [loadOwners])

  const activeOwners = owners.filter((owner) => owner.status === 'active').length
  const inactiveOwners = owners.length - activeOwners

  const formatDate = (value: string) => {
    return new Date(value).toLocaleDateString(
      bengali ? 'bn-IN' : 'en-IN',
      { day: '2-digit', month: 'short', year: 'numeric' }
    )
  }

  if (loading) {
    return (
      <div className="owner-loading">
        <LoaderCircle className="owner-spin" size={24} />
        <span>{bengali ? 'মালিকদের তথ্য লোড হচ্ছে...' : 'Loading owners...'}</span>
      </div>
    )
  }

  return (
    <section className="owner-page">
      <div className="owner-heading">
        <div>
          <div className="owner-eyebrow">
            {bengali ? 'ব্যবসা পরিচালনা' : 'BUSINESS MANAGEMENT'}
          </div>
          <h2>
            <Users size={24} />
            {bengali ? 'মালিক ব্যবস্থাপনা' : 'Owner Management'}
          </h2>
          <p>
            {bengali
              ? 'এই ব্যবসার মালিক এবং তাদের সদস্যপদের অবস্থা দেখুন।'
              : 'View the owners and their membership status for this business.'}
          </p>
        </div>
        <div className="owner-heading-actions">
          <button
            type="button"
            className="primary-button"
            onClick={() => setShowCreateForm(!showCreateForm)}
          >
            <UserPlus size={16} />
            {bengali ? 'নতুন মালিক যোগ করুন' : 'Add Owner'}
          </button>
          <button
            type="button"
            className="outline-button owner-refresh"
            onClick={() => void loadOwners(true)}
            disabled={refreshing}
          >
            <RefreshCw size={16} className={refreshing ? 'owner-spin' : ''} />
            {bengali ? 'রিফ্রেশ' : 'Refresh'}
          </button>
        </div>
      </div>

      {error && (
        <div className="owner-alert" role="alert">
          {error}
          <button onClick={() => void loadOwners()}>Retry</button>
        </div>
      )}

      {showCreateForm && (
        <div className="owner-create-card">
          <div className="owner-create-heading">
            <div>
              <h3>{bengali ? 'নতুন মালিক যোগ করুন' : 'Add New Owner'}</h3>
              <p>
                {bengali
                  ? 'নতুন মালিকের তথ্য পূরণ করুন।'
                  : 'Enter the new owner\'s details.'}
              </p>
            </div>
            <button
              type="button"
              className="owner-close-button"
              onClick={() => setShowCreateForm(false)}
            >
              <X size={18} />
            </button>
          </div>

          <form
            onSubmit={(event) => {
              event.preventDefault()
              void handleCreateOwner()
            }}
            className="owner-create-form"
          >
            <label>
              {bengali ? 'সম্পূর্ণ নাম *' : 'Full Name *'}
              <input
                type="text"
                value={formData.full_name}
                onChange={(event) =>
                  setFormData({ ...formData, full_name: event.target.value })
                }
                placeholder="Enter full name"
                required
              />
            </label>

            <label>
              Email *
              <input
                type="email"
                value={formData.email}
                onChange={(event) =>
                  setFormData({ ...formData, email: event.target.value })
                }
                placeholder="owner@example.com"
                required
              />
            </label>

            <label>
              {bengali ? 'ফোন নম্বর' : 'Phone Number'}
              <input
                type="tel"
                value={formData.phone || ''}
                onChange={(event) =>
                  setFormData({ ...formData, phone: event.target.value })
                }
                placeholder="Phone number"
              />
            </label>

            <label>
              {bengali ? 'Password (নতুন User-এর জন্য)' : 'Password (for new User)'}
              <input
                type="password"
                value={formData.password || ''}
                onChange={(event) =>
                  setFormData({ ...formData, password: event.target.value })
                }
                placeholder="Minimum 8 characters"
                minLength={8}
              />
            </label>

            <p className="owner-form-hint">
              {bengali
                ? 'আগে থেকে থাকা Active User-কে যোগ করলে Password ফাঁকা রাখুন।'
                : 'Leave password blank when adding an existing active User.'}
            </p>

            <button
              type="submit"
              className="owner-submit-button"
              disabled={submitting}
            >
              {submitting
                ? (bengali ? 'যোগ হচ্ছে...' : 'Adding...')
                : (bengali ? 'মালিক যোগ করুন' : 'Create Owner')}
            </button>
          </form>
        </div>
      )}

      <div className="owner-summary">
        <div className="owner-summary-card">
          <div className="owner-summary-icon total">
            <Users size={21} />
          </div>
          <div>
            <span>{bengali ? 'মোট মালিক' : 'Total Owners'}</span>
            <strong>{owners.length}</strong>
          </div>
        </div>

        <div className="owner-summary-card">
          <div className="owner-summary-icon active">
            <UserCheck size={21} />
          </div>
          <div>
            <span>{bengali ? 'সক্রিয় মালিক' : 'Active Owners'}</span>
            <strong>{activeOwners}</strong>
          </div>
        </div>

        <div className="owner-summary-card">
          <div className="owner-summary-icon inactive">
            <UserX size={21} />
          </div>
          <div>
            <span>{bengali ? 'নিষ্ক্রিয় মালিক' : 'Inactive Owners'}</span>
            <strong>{inactiveOwners}</strong>
          </div>
        </div>
      </div>

      <div className="owner-card">
        <div className="owner-card-heading">
          <div>
            <h3>{bengali ? 'মালিকদের তালিকা' : 'Owners List'}</h3>
            <span>
              {bengali
                ? 'এই ব্যবসার সঙ্গে যুক্ত মালিকরা'
                : 'Owners associated with this business'}
            </span>
          </div>
          <span className="owner-count">
            {owners.length} {bengali ? 'জন' : 'Owner(s)'}
          </span>
        </div>

        {owners.length === 0 ? (
          <div className="owner-empty">
            <UserRound size={34} />
            <strong>
              {bengali ? 'কোনো মালিক পাওয়া যায়নি' : 'No owners found'}
            </strong>
          </div>
        ) : (
          <div className="owner-list">
            {owners.map((owner) => (
              <div className="owner-list-item" key={owner.membership_id}>
                <div className="owner-avatar">
                  {owner.full_name.trim().charAt(0).toUpperCase()}
                </div>

                <div className="owner-details">
                  <div className="owner-name-row">
                    <strong>{owner.full_name}</strong>
                    <span className={`owner-status ${owner.status}`}>
                      {owner.status === 'active'
                        ? (bengali ? 'সক্রিয়' : 'Active')
                        : (bengali ? 'নিষ্ক্রিয়' : 'Inactive')}
                    </span>
                  </div>

                  <div className="owner-contact">
                    <span><Mail size={14} /> {owner.email}</span>
                    {owner.phone && (
                      <span><Phone size={14} /> {owner.phone}</span>
                    )}
                  </div>
                  
                {currentUserId && owner.user_id === currentUserId && (
                  <button
                    type="button"
                    className="owner-edit-action"
                    onClick={() => handleEditProfile(owner)}
                  >
                    <Pencil size={14} />
                    {bengali ? 'প্রোফাইল সম্পাদনা' : 'Edit Profile'}
                  </button>
                )}

                  <small>
                    <ShieldCheck size={13} />
                    {bengali ? 'সদস্য হয়েছেন: ' : 'Member since: '}
                    {formatDate(owner.created_at)}
                  </small>
                                    {currentUserId && owner.user_id !== currentUserId && (
                    <button
                      type="button"
                      className="owner-status-action"
                      onClick={() => void handleOwnerStatusChange(owner)}
                      disabled={updatingMembershipId === owner.membership_id}
                    >
                      {updatingMembershipId === owner.membership_id
                        ? (bengali ? 'অপেক্ষা করুন...' : 'Please wait...')
                        : owner.status === 'active'
                          ? (bengali ? 'নিষ্ক্রিয় করুন' : 'Deactivate')
                          : (bengali ? 'আবার সক্রিয় করুন' : 'Reactivate')}
                    </button>
                  )}
                </div>

                {currentUserId && owner.user_id === currentUserId && showEditProfile && (
                  <div
                    className="owner-modal-overlay"
                    onClick={() => {
                      if (!profileSubmitting) {
                        setShowEditProfile(false)
                        setProfileError('')
                      }
                    }}
                  >
                    <div
                      className="owner-profile-modal"
                      role="dialog"
                      aria-modal="true"
                      aria-labelledby="owner-profile-modal-title"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <div className="owner-modal-header">
                        <div>
                          <h3 id="owner-profile-modal-title">
                            {bengali ? 'প্রোফাইল সম্পাদনা' : 'Edit Your Profile'}
                          </h3>
                          <p>
                            {bengali
                              ? 'আপনার ব্যক্তিগত তথ্য আপডেট করুন।'
                              : 'Update your personal information.'}
                          </p>
                        </div>

                        <button
                          type="button"
                          className="owner-close-button"
                          onClick={() => {
                            setShowEditProfile(false)
                            setProfileError('')
                          }}
                          disabled={profileSubmitting}
                        >
                          <X size={18} />
                        </button>
                      </div>

                      {profileError && (
                        <div className="page-notice" role="alert">
                          {profileError}
                        </div>
                      )}

                      <div className="owner-profile-edit">
                        <label>
                          {bengali ? 'সম্পূর্ণ নাম' : 'Full Name'}
                          <input
                            type="text"
                            value={profileData.full_name}
                            onChange={(e) =>
                              setProfileData((prev) => ({
                                ...prev,
                                full_name: e.target.value,
                              }))
                            }
                            maxLength={150}
                          />
                        </label>

                        <label>
                          {bengali ? 'ফোন নম্বর' : 'Phone Number'}
                          <input
                            type="tel"
                            value={profileData.phone}
                            onChange={(e) =>
                              setProfileData((prev) => ({
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
                            value={owner.email}
                            readOnly
                            disabled
                          />
                        </label>
                      </div>

                      <div className="owner-profile-actions">
                        <button
                          type="button"
                          className="owner-profile-cancel"
                          onClick={() => {
                            setShowEditProfile(false)
                            setProfileError('')
                          }}
                          disabled={profileSubmitting}
                        >
                          <X size={15} />
                          {bengali ? 'বাতিল' : 'Cancel'}
                        </button>

                        <button
                          type="button"
                          className="owner-profile-save"
                          onClick={handleSaveProfile}
                          disabled={profileSubmitting}
                        >
                          {profileSubmitting ? (
                            <LoaderCircle size={15} className="spin" />
                          ) : (
                            <Save size={15} />
                          )}
                          {bengali ? 'সংরক্ষণ করুন' : 'Save Changes'}
                        </button>
                      </div>
                    </div>
                  </div>
                )}

              </div>
            ))}
          </div>
        )}
      </div>
    </section>
  )
}
