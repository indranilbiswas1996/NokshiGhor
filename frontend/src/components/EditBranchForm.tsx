
import { useState } from 'react'
import { isAxiosError } from 'axios'
import { LoaderCircle, Save, X } from 'lucide-react'
import { branchApi, type Branch } from '../api/branch'

interface EditBranchFormProps {
  branch: Branch
  bengali: boolean
  onUpdated: () => void
  onCancel: () => void
}

export default function EditBranchForm({
  branch,
  bengali,
  onUpdated,
  onCancel,
}: EditBranchFormProps) {
  const [form, setForm] = useState({
    branch_name: branch.branch_name,
    branch_code: branch.branch_code ?? '',
    address: branch.address ?? '',
    phone: branch.phone ?? '',
    email: branch.email ?? '',
  })

  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const handleChange = (
    field: keyof typeof form,
    value: string
  ) => {
    setForm((previous) => ({
      ...previous,
      [field]: value,
    }))
  }

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setSaving(true)
    setError('')

    try {
      await branchApi.updateBranch(branch.id, {
        branch_name: form.branch_name.trim(),
        branch_code: form.branch_code.trim() || null,
        address: form.address.trim() || null,
        phone: form.phone.trim() || null,
        email: form.email.trim() || null,
      })

      onUpdated()
    } catch (err) {
      if (isAxiosError(err)) {
        setError(
          err.response?.data?.detail ||
            (bengali ? 'শাখা আপডেট করা যায়নি।' : 'Unable to update branch.')
        )
      } else {
        setError(bengali ? 'একটি সমস্যা হয়েছে।' : 'Something went wrong.')
      }
    } finally {
      setSaving(false)
    }
  }

  return (
    <form className="branch-form" onSubmit={handleSubmit}>
      <div className="branch-form-header">
        <h3>{bengali ? 'শাখার তথ্য সম্পাদনা' : 'Edit Branch'}</h3>
        <button type="button" className="branch-icon-button" onClick={onCancel}>
          <X size={18} />
        </button>
      </div>

      {error && <div className="branch-error">{error}</div>}

      <div className="branch-form-grid">
        <label>
          {bengali ? 'শাখার নাম' : 'Branch Name'} *
          <input
            required
            maxLength={150}
            value={form.branch_name}
            onChange={(e) => handleChange('branch_name', e.target.value)}
          />
        </label>

        <label>
          {bengali ? 'শাখা কোড' : 'Branch Code'}
          <input
            maxLength={30}
            value={form.branch_code}
            onChange={(e) => handleChange('branch_code', e.target.value)}
          />
        </label>

        <label>
          {bengali ? 'ঠিকানা' : 'Address'}
          <textarea
            value={form.address}
            onChange={(e) => handleChange('address', e.target.value)}
          />
        </label>

        <label>
          {bengali ? 'ফোন নম্বর' : 'Phone'}
          <input
            maxLength={30}
            value={form.phone}
            onChange={(e) => handleChange('phone', e.target.value)}
          />
        </label>

        <label>
          {bengali ? 'ইমেইল' : 'Email'}
          <input
            type="email"
            maxLength={254}
            value={form.email}
            onChange={(e) => handleChange('email', e.target.value)}
          />
        </label>
      </div>

      <div className="branch-form-actions">
        <button type="button" onClick={onCancel} disabled={saving}>
          {bengali ? 'বাতিল' : 'Cancel'}
        </button>

        <button type="submit" disabled={saving}>
          {saving ? (
            <LoaderCircle size={16} className="spin" />
          ) : (
            <Save size={16} />
          )}
          {saving
            ? (bengali ? 'সংরক্ষণ হচ্ছে...' : 'Saving...')
            : (bengali ? 'পরিবর্তন সংরক্ষণ' : 'Save Changes')}
        </button>
      </div>
    </form>
  )
}
