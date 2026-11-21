
import { useState } from 'react'
import { isAxiosError } from 'axios'
import { X, Save } from 'lucide-react'
import { branchApi } from '../api/branch'

interface CreateBranchFormProps {
  bengali: boolean
  onCancel: () => void
  onCreated: () => void
}

export default function CreateBranchForm({
  bengali,
  onCancel,
  onCreated,
}: CreateBranchFormProps) {
  const [form, setForm] = useState({
    branch_name: '',
    branch_code: '',
    address: '',
    phone: '',
    email: '',
  })
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const updateField = (field: keyof typeof form, value: string) => {
    setForm((previous) => ({ ...previous, [field]: value }))
  }

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setError('')

    if (!form.branch_name.trim()) {
      setError(bengali ? 'শাখার নাম লিখুন।' : 'Branch name is required.')
      return
    }

    setLoading(true)

    try {
      await branchApi.createBranch({
        branch_name: form.branch_name.trim(),
        branch_code: form.branch_code.trim() || null,
        address: form.address.trim() || null,
        phone: form.phone.trim() || null,
        email: form.email.trim() || null,
      })

      onCreated()
    } catch (err) {
      if (isAxiosError(err)) {
        setError(
          err.response?.data?.detail ||
            (bengali ? 'শাখা তৈরি করা যায়নি।' : 'Unable to create branch.')
        )
      } else {
        setError(bengali ? 'একটি সমস্যা হয়েছে।' : 'Something went wrong.')
      }
    } finally {
      setLoading(false)
    }
  }

  return (
    <form className="branch-create-form" onSubmit={handleSubmit}>
      <div className="branch-create-header">
        <h3>{bengali ? 'নতুন শাখা তৈরি করুন' : 'Create New Branch'}</h3>
        <button type="button" onClick={onCancel} aria-label="Close">
          <X size={18} />
        </button>
      </div>

      <div className="branch-form-grid">
        <label>
          {bengali ? 'শাখার নাম *' : 'Branch Name *'}
          <input
            value={form.branch_name}
            onChange={(e) => updateField('branch_name', e.target.value)}
            placeholder={bengali ? 'শাখার নাম লিখুন' : 'Enter branch name'}
            maxLength={150}
            required
          />
        </label>

        <label>
          {bengali ? 'শাখার কোড' : 'Branch Code'}
          <input
            value={form.branch_code}
            onChange={(e) => updateField('branch_code', e.target.value)}
            placeholder="e.g. BR001"
            maxLength={30}
          />
        </label>

        <label className="branch-form-full">
          {bengali ? 'ঠিকানা' : 'Address'}
          <textarea
            value={form.address}
            onChange={(e) => updateField('address', e.target.value)}
            placeholder={bengali ? 'শাখার ঠিকানা' : 'Branch address'}
            rows={2}
          />
        </label>

        <label>
          {bengali ? 'ফোন নম্বর' : 'Phone'}
          <input
            value={form.phone}
            onChange={(e) => updateField('phone', e.target.value)}
            maxLength={30}
            placeholder="Phone number"
          />
        </label>

        <label>
          {bengali ? 'ইমেল' : 'Email'}
          <input
            type="email"
            value={form.email}
            onChange={(e) => updateField('email', e.target.value)}
            placeholder="branch@example.com"
          />
        </label>
      </div>

      {error && <div className="branch-form-error">{error}</div>}

      <div className="branch-form-actions">
        <button type="button" onClick={onCancel} disabled={loading}>
          {bengali ? 'বাতিল' : 'Cancel'}
        </button>
        <button type="submit" disabled={loading}>
          <Save size={16} />
          {loading
            ? bengali ? 'তৈরি হচ্ছে...' : 'Creating...'
            : bengali ? 'শাখা তৈরি করুন' : 'Create Branch'}
        </button>
      </div>
    </form>
  )
}
