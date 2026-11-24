
import { useEffect, useState } from 'react'
import { ArrowLeft, Printer, CheckCircle } from 'lucide-react'
import { salesApi } from '../api/sales'
import type { Sale } from '../types/sales'

interface SaleDetailsProps {
  saleId: string
  branchId: string | null
  onBack: () => void
}

const formatMoney = (value: number) =>
  `\u20B9 ${Number(value).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })}`

export default function SaleDetails({
  saleId,
  branchId,
  onBack,
}: SaleDetailsProps) {
  const [sale, setSale] = useState<Sale | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [posting, setPosting] = useState(false)
  const [postError, setPostError] = useState('')
  const [postSuccess, setPostSuccess] = useState('')

  useEffect(() => {
    let ignore = false

    const loadDetails = async () => {
      setLoading(true)
      setError('')

      try {
        const response = await salesApi.getSaleDetails(saleId, branchId)
        if (!ignore) setSale(response)
      } catch (err) {
        console.error('Sale details loading failed:', err)
        if (!ignore) {
          setError('Unable to load invoice details. Please try again.')
        }
      } finally {
        if (!ignore) setLoading(false)
      }
    }

    loadDetails()

    return () => {
      ignore = true
    }
  }, [saleId, branchId])

  const handlePostSale = async () => {
    if (!sale || sale.sale_status !== 'draft' || posting) return

    const confirmed = window.confirm(
      `Are you sure you want to post invoice ${sale.sale_number}?\n\nOnce posted, the sale will update stock records and cannot be edited as a draft.`
    )

    if (!confirmed) return

    setPosting(true)
    setPostError('')
    setPostSuccess('')

    try {
      await salesApi.postSale(sale.id, branchId)

      // Update the status immediately after successful posting.
      setSale((current) =>
        current ? { ...current, sale_status: 'posted' } : current
      )

      setPostSuccess('Sale posted successfully.')

      // Refresh invoice details from the backend.
      try {
        const refreshedSale = await salesApi.getSaleDetails(sale.id, branchId)
        setSale(refreshedSale)
      } catch (refreshError) {
        console.error('Invoice refresh failed:', refreshError)
      }
    } catch (err) {
      console.error('Sale posting failed:', err)

      const apiError = err as {
        response?: {
          data?: {
            detail?: string
          }
        }
      }

      setPostError(
        apiError.response?.data?.detail ||
          'Sale cannot be posted. Please check stock availability and sale status.'
      )
    } finally {
      setPosting(false)
    }
  }

  if (loading) {
    return (
      <section className="content-section">
        <p>Loading invoice details...</p>
      </section>
    )
  }

  if (error || !sale) {
    return (
      <section className="content-section">
        <p role="alert">{error || 'Sale not found.'}</p>
        <button className="secondary-button" onClick={onBack}>
          <ArrowLeft size={16} /> Back to Sales
        </button>
      </section>
    )
  }

  return (
    <section className="content-section sale-details-panel">
      <div className="section-header">
        <div>
          <h2>Invoice Details</h2>
          <p>{sale.sale_number}</p>
        </div>

        <div className="sale-details-actions">
          <button className="secondary-button" onClick={onBack}>
            <ArrowLeft size={16} /> Back
          </button>

          {sale.sale_status === 'draft' && (
            <button
              className="primary-button"
              onClick={handlePostSale}
              disabled={posting}
            >
              <CheckCircle size={16} />
              {posting ? 'Posting...' : 'Post Sale'}
            </button>
          )}

          <button
            className="secondary-button"
            onClick={() => window.print()}
          >
            <Printer size={16} /> Print
          </button>
        </div>
      </div>

      {postError && (
        <p className="form-error" role="alert">
          {postError}
        </p>
      )}

      {postSuccess && (
        <p className="form-success" role="status">
          {postSuccess}
        </p>
      )}

      <div className="invoice-paper">
        <div className="invoice-heading">
          <div>
            <h2>{sale.shop_name_snapshot}</h2>
            <p>Sales Invoice</p>
          </div>

          <div className="invoice-number">
            <strong>{sale.sale_number}</strong>
            <span>{sale.sale_date}</span>
            <span className={`status-badge ${sale.sale_status}`}>
              {sale.sale_status}
            </span>
          </div>
        </div>

        <div className="invoice-customer">
          <div>
            <span className="invoice-label">CUSTOMER</span>
            <strong>{sale.customer_name_snapshot}</strong>
          </div>

          <div>
            <span className="invoice-label">PAYMENT STATUS</span>
            <strong>{sale.payment_status}</strong>
          </div>

          {sale.due_date && (
            <div>
              <span className="invoice-label">DUE DATE</span>
              <strong>{sale.due_date}</strong>
            </div>
          )}
        </div>

        <div className="table-wrapper">
          <table className="transaction-table invoice-items-table">
            <thead>
              <tr>
                <th>PRODUCT</th>
                <th>SKU</th>
                <th>QTY</th>
                <th>PRICE</th>
                <th>TAX</th>
                <th>AMOUNT</th>
              </tr>
            </thead>

            <tbody>
              {sale.items.map((item) => (
                <tr key={item.id}>
                  <td>{item.product_name_snapshot}</td>
                  <td>{item.sku_snapshot || '\u2014'}</td>
                  <td>{Number(item.quantity)}</td>
                  <td>{formatMoney(item.unit_price)}</td>
                  <td>{formatMoney(item.tax_amount)}</td>
                  <td className="amount-cell">
                    {formatMoney(item.line_total)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="invoice-summary">
          <div>
            <span>Subtotal</span>
            <strong>{formatMoney(sale.subtotal)}</strong>
          </div>

          <div>
            <span>Discount</span>
            <strong>{formatMoney(sale.discount_amount)}</strong>
          </div>

          <div>
            <span>Tax</span>
            <strong>{formatMoney(sale.tax_amount)}</strong>
          </div>

          <div>
            <span>Shipping</span>
            <strong>{formatMoney(sale.shipping_charge)}</strong>
          </div>

          <div>
            <span>Other Charges</span>
            <strong>{formatMoney(sale.other_charges)}</strong>
          </div>

          <div>
            <span>Round Off</span>
            <strong>{formatMoney(sale.round_off)}</strong>
          </div>

          <div className="invoice-grand-total">
            <span>Grand Total</span>
            <strong>{formatMoney(sale.total_amount)}</strong>
          </div>

          <div>
            <span>Paid Amount</span>
            <strong>{formatMoney(sale.paid_amount)}</strong>
          </div>

          <div>
            <span>Balance Due</span>
            <strong>
              {formatMoney(
                Math.max(0, sale.total_amount - sale.paid_amount)
              )}
            </strong>
          </div>
        </div>
      </div>
    </section>
  )
}
