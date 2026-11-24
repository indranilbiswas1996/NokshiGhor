import { ArrowLeft, Building2, LoaderCircle } from 'lucide-react'
import type { Branch } from '../api/branch'
import './BranchSelectionScreen.css'

interface BranchSelectionScreenProps {
  businessName: string
  branches: Branch[]
  loading: boolean
  error: string
  onSelect: (branchId: string) => void
  onBack: () => void
}

export default function BranchSelectionScreen({
  businessName,
  branches,
  loading,
  error,
  onSelect,
  onBack,
}: BranchSelectionScreenProps) {
  return (
    <main className="branch-selection-page">
      <section className="branch-selection-panel">
        <div className="branch-selection-brand">
          <span><Building2 size={21} /></span>
          <div>
            <strong>NokshiGhor</strong>
            <small>{businessName}</small>
          </div>
        </div>

        <header className="branch-selection-heading">
          <div>
            <span>WORKSPACE</span>
            <h1>Select your branch</h1>
          </div>
          <button type="button" className="branch-selection-back" onClick={onBack}>
            <ArrowLeft size={15} />
            Change business
          </button>
        </header>

        {error && <p className="branch-selection-error" role="alert">{error}</p>}

        {loading ? (
          <div className="branch-selection-loading">
            <LoaderCircle size={20} className="branch-selection-spin" />
            Loading branches...
          </div>
        ) : (
          <div className="branch-selection-options">
            <button
              type="button"
              className="branch-selection-option all"
              onClick={() => onSelect('all')}
            >
              <span className="branch-selection-icon"><Building2 size={19} /></span>
              <span className="branch-selection-details">
                <strong>All Branches</strong>
                <small>View the whole business</small>
              </span>
              <span className="branch-selection-status">All</span>
            </button>

            {branches.map((branch) => (
              <button
                key={branch.id}
                type="button"
                className="branch-selection-option"
                onClick={() => onSelect(branch.id)}
              >
                <span className="branch-selection-icon"><Building2 size={19} /></span>
                <span className="branch-selection-details">
                  <strong>{branch.branch_name}</strong>
                  {branch.branch_code && <small>{branch.branch_code}</small>}
                </span>
                <span className={`branch-selection-status ${branch.is_active ? 'active' : 'inactive'}`}>
                  {branch.is_active ? 'Active' : 'Inactive'}
                </span>
              </button>
            ))}

            {branches.length === 0 && (
              <p className="branch-selection-empty">No accessible branches are available.</p>
            )}
          </div>
        )}
      </section>
    </main>
  )
}
