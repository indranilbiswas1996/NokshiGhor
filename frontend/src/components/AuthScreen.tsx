
import { useEffect, useState, type FormEvent } from 'react'
import { Building2, LockKeyhole, Mail, ArrowRight, LoaderCircle } from 'lucide-react'
import { authApi } from '../api/auth'
import type { Business } from '../types/auth'
import './AuthScreen.css'

interface AuthScreenProps {
  onAuthenticated: (business: Business) => void
}

export default function AuthScreen({ onAuthenticated }: AuthScreenProps) {
  const [mode, setMode] = useState<'login' | 'business'>('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [businesses, setBusinesses] = useState<Business[]>([])
  const [loading, setLoading] = useState(false)
  const [checking, setChecking] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    const token = localStorage.getItem('nokshighor-access-token')

    if (!token) {
      setChecking(false)
      return
    }

    const restoreSession = async () => {
      try {
        const business = await authApi.getCurrentBusiness()
        onAuthenticated(business)
      } catch {
        try {
          const result = await authApi.getBusinesses()
          setBusinesses(result.businesses)
          setMode('business')
        } catch {
          authApi.logout()
        }
      } finally {
        setChecking(false)
      }
    }

    void restoreSession()
  }, [onAuthenticated])

  const handleLogin = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setLoading(true)
    setError('')

    try {
      await authApi.login({ email, password })
      const result = await authApi.getBusinesses()

      if (result.businesses.length === 0) {
        setError('No business is associated with this account.')
        authApi.logout()
        return
      }

      setBusinesses(result.businesses)
      setMode('business')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed.')
    } finally {
      setLoading(false)
    }
  }

  const handleBusinessSelect = async (businessId: string) => {
    setLoading(true)
    setError('')

    try {
      const result = await authApi.selectBusiness(businessId)
      onAuthenticated(result.business)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Business selection failed.')
    } finally {
      setLoading(false)
    }
  }

  if (checking) {
    return <div className="auth-loading"><LoaderCircle className="auth-spinner" size={30} /></div>
  }

  return (
    <div className="auth-page">
      <section className="auth-card">
        <div className="auth-brand">
          <div className="auth-brand-icon"><Building2 size={25} /></div>
          <div>
            <h1>NokshiGhor</h1>
            <p>SMART BUSINESS MANAGEMENT</p>
          </div>
        </div>

        {mode === 'login' ? (
          <>
            <div className="auth-heading">
              <h2>Welcome back</h2>
              <p>Sign in to continue to your workspace.</p>
            </div>

            <form className="auth-form" onSubmit={handleLogin}>
              <label>Email address</label>
              <div className="auth-input-wrap">
                <Mail size={18} />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="Enter your email"
                  autoComplete="username"
                  required
                />
              </div>

              <label>Password</label>
              <div className="auth-input-wrap">
                <LockKeyhole size={18} />
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter your password"
                  autoComplete="current-password"
                  required
                />
              </div>

              {error && <p className="auth-error">{error}</p>}

              <button className="auth-submit" type="submit" disabled={loading}>
                {loading ? 'Signing in...' : 'Sign In'}
                {!loading && <ArrowRight size={18} />}
              </button>
            </form>
          </>
        ) : (
          <>
            <div className="auth-heading">
              <h2>Select your business</h2>
              <p>Choose the workspace you want to continue with.</p>
            </div>

            <div className="business-options">
              {businesses.map((business) => (
                <button
                  className="business-option"
                  key={business.id}
                  disabled={loading}
                  onClick={() => void handleBusinessSelect(business.id)}
                >
                  <span className="business-option-icon"><Building2 size={21} /></span>
                  <span className="business-option-info">
                    <strong>{business.business_name}</strong>
                    <small>{business.business_type} · {business.role_name}</small>
                  </span>
                  <ArrowRight size={18} />
                </button>
              ))}
            </div>

            {error && <p className="auth-error">{error}</p>}
          </>
        )}

        <p className="auth-footer">
        © {new Date().getFullYear()} NokshiGhor. All rights reserved.
        </p>
      </section>
    </div>
  )
}
