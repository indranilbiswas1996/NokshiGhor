import { useState, type FormEvent } from 'react'
import { isAxiosError } from 'axios'
import { KeyRound, LoaderCircle, Mail, X } from 'lucide-react'
import { authApi } from '../api/auth'
import './PasswordSecurity.css'

export type PasswordDialogMode = 'change' | 'forgot'

interface PasswordSecurityModalProps {
  mode: PasswordDialogMode
  email: string
  onClose: () => void
}

function getErrorMessage(error: unknown): string {
  if (isAxiosError(error)) {
    const detail = error.response?.data?.detail
    if (typeof detail === 'string') return detail
  }
  return error instanceof Error ? error.message : 'Something went wrong.'
}

export function PasswordSecurityModal({
  mode,
  email: initialEmail,
  onClose,
}: PasswordSecurityModalProps) {
  const [email, setEmail] = useState(initialEmail)
  const [currentPassword, setCurrentPassword] = useState('')
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setSaving(true)
    setError('')
    setNotice('')

    try {
      if (mode === 'change') {
        if (newPassword !== confirmPassword) {
          throw new Error('New passwords do not match.')
        }
        if (newPassword.length < 12) {
          throw new Error('New password must contain at least 12 characters.')
        }

        const response = await authApi.changePassword({
          current_password: currentPassword,
          new_password: newPassword,
        })
        setNotice(response.message)
        setCurrentPassword('')
        setNewPassword('')
        setConfirmPassword('')
      } else {
        const response = await authApi.requestPasswordReset(email.trim())
        setNotice(response.message)
      }
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="owner-modal-overlay" onMouseDown={(event) => {
      if (event.target === event.currentTarget && !saving) onClose()
    }}>
      <section
        className="owner-profile-modal password-security-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="password-security-title"
      >
        <header className="owner-modal-header">
          <div>
            <h2 id="password-security-title">
              {mode === 'change' ? 'Change Password' : 'Forgot Password'}
            </h2>
            <p>
              {mode === 'change'
                ? 'Verify your current password before choosing a new one.'
                : 'We will email a single-use reset link if the account is active.'}
            </p>
          </div>
          <button type="button" className="owner-close-button" onClick={onClose} disabled={saving} aria-label="Close">
            <X size={20} />
          </button>
        </header>

        {notice ? (
          <p className="password-security-notice" role="status">{notice}</p>
        ) : (
          <form className="owner-profile-edit" onSubmit={(event) => void handleSubmit(event)}>
            {mode === 'change' ? (
              <>
                <label>
                  Current password
                  <input
                    type="password"
                    autoComplete="current-password"
                    value={currentPassword}
                    onChange={(event) => setCurrentPassword(event.target.value)}
                    required
                    disabled={saving}
                  />
                </label>
                <label>
                  New password
                  <input
                    type="password"
                    autoComplete="new-password"
                    minLength={12}
                    value={newPassword}
                    onChange={(event) => setNewPassword(event.target.value)}
                    required
                    disabled={saving}
                  />
                </label>
                <label>
                  Confirm new password
                  <input
                    type="password"
                    autoComplete="new-password"
                    minLength={12}
                    value={confirmPassword}
                    onChange={(event) => setConfirmPassword(event.target.value)}
                    required
                    disabled={saving}
                  />
                </label>
              </>
            ) : (
              <label>
                Email address
                <span className="password-security-email">
                  <Mail size={16} />
                  <input
                    type="email"
                    autoComplete="email"
                    value={email}
                    onChange={(event) => setEmail(event.target.value)}
                    required
                    disabled={saving}
                  />
                </span>
              </label>
            )}

            {error && <p className="page-notice error" role="alert">{error}</p>}

            <div className="owner-profile-actions">
              <button type="button" className="owner-profile-cancel" onClick={onClose} disabled={saving}>Cancel</button>
              <button type="submit" className="owner-profile-save" disabled={saving}>
                {saving ? <LoaderCircle size={15} className="password-security-spin" /> : <KeyRound size={15} />}
                {saving ? 'Please wait...' : mode === 'change' ? 'Save Password' : 'Send Reset Link'}
              </button>
            </div>
          </form>
        )}
      </section>
    </div>
  )
}

interface PasswordResetPageProps {
  token: string
  onComplete: () => void
}

export function PasswordResetPage({ token, onComplete }: PasswordResetPageProps) {
  const [password, setPassword] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [complete, setComplete] = useState(false)

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setError('')
    if (password !== confirmation) {
      setError('Passwords do not match.')
      return
    }

    setSaving(true)
    try {
      await authApi.resetPassword({ token, new_password: password })
      setComplete(true)
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setSaving(false)
    }
  }

  return (
    <main className="auth-page">
      <section className="auth-card">
        <div className="auth-brand">
          <div className="auth-brand-icon"><KeyRound size={24} /></div>
          <div><h1>NokshiGhor</h1><p>SMART BUSINESS MANAGEMENT</p></div>
        </div>
        <div className="auth-heading">
          <h2>{complete ? 'Password reset' : 'Reset your password'}</h2>
          <p>{complete ? 'Your password has been updated.' : 'Choose a new password with at least 12 characters.'}</p>
        </div>
        {complete ? (
          <button type="button" className="auth-submit" onClick={onComplete}>Return to Sign In</button>
        ) : (
          <form className="auth-form" onSubmit={(event) => void handleSubmit(event)}>
            <label>New password</label>
            <div className="auth-input-wrap">
              <KeyRound size={18} />
              <input type="password" autoComplete="new-password" minLength={12} value={password} onChange={(event) => setPassword(event.target.value)} required disabled={saving} />
            </div>
            <label>Confirm new password</label>
            <div className="auth-input-wrap">
              <KeyRound size={18} />
              <input type="password" autoComplete="new-password" minLength={12} value={confirmation} onChange={(event) => setConfirmation(event.target.value)} required disabled={saving} />
            </div>
            {error && <p className="auth-error" role="alert">{error}</p>}
            <button type="submit" className="auth-submit" disabled={saving}>
              {saving ? 'Saving...' : 'Reset Password'}
            </button>
          </form>
        )}
      </section>
    </main>
  )
}
