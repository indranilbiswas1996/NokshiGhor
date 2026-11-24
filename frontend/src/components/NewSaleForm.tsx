
import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { ArrowLeft, Plus, Trash2 } from 'lucide-react'
import { salesApi } from '../api/sales'
import type {
  SalesProduct,
  SalesCustomer,
  SalesWarehouse,
  SaleCreateRequest,
} from '../types/sales'

interface SaleLine {
  id: number
  product_id: string
  quantity: string
  unit_price: number
  discount_amount: string
}

interface Props {
  branchId: string | null
  onCancel: () => void
  onCreated: () => void
}

export default function NewSaleForm({ branchId, onCancel, onCreated }: Props) {
  const [products, setProducts] = useState<SalesProduct[]>([])
  const [customers, setCustomers] = useState<SalesCustomer[]>([])
  const [warehouses, setWarehouses] = useState<SalesWarehouse[]>([])
  const [customerId, setCustomerId] = useState('')
  const [warehouseId, setWarehouseId] = useState('')
  const [lines, setLines] = useState<SaleLine[]>([
    { id: 1, product_id: '', quantity: '1', unit_price: 0, discount_amount: '0' },
  ])
  const [notes, setNotes] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [nextId, setNextId] = useState(2)

  useEffect(() => {
    let ignore = false

    const loadReferences = async () => {
      setLoading(true)
      setError('')

      try {
        const [productData, customerData, warehouseData] = await Promise.all([
          salesApi.getSalesProducts(),
          salesApi.getSalesCustomers(),
          salesApi.getSalesWarehouses(),
        ])

        if (ignore) return

        setProducts(productData)
        setCustomers(customerData)
        const availableWarehouses = warehouseData.filter(
          (warehouse) => !branchId || warehouse.branch_id === branchId
        )
        setWarehouses(availableWarehouses)

        const defaultWarehouse = availableWarehouses.find((item) => item.is_default)
        if (defaultWarehouse) {
          setWarehouseId(defaultWarehouse.id)
        } else if (availableWarehouses.length > 0) {
          setWarehouseId(availableWarehouses[0].id)
        } else {
          setWarehouseId('')
        }
      } catch (err) {
        console.error('Sales reference loading failed:', err)
        if (!ignore) {
          setError('Unable to load products or business references. Please try again.')
        }
      } finally {
        if (!ignore) setLoading(false)
      }
    }

    loadReferences()

    return () => {
      ignore = true
    }
  }, [branchId])

  const selectedProducts = lines
    .map((line) => products.find((product) => product.id === line.product_id))
    .filter((product): product is SalesProduct => Boolean(product))

  const warehouseRequired = selectedProducts.some(
    (product) => product.track_inventory
  ) || Boolean(branchId)

  const totals = useMemo(() => {
    let subtotal = 0
    let tax = 0

    lines.forEach((line) => {
      const product = products.find((item) => item.id === line.product_id)
      const quantity = Number(line.quantity) || 0
      const discount = Number(line.discount_amount) || 0

      if (!product || quantity <= 0) return

      const gross = quantity * line.unit_price
      const taxableAmount = Math.max(0, gross - discount)

      subtotal += taxableAmount
      tax += taxableAmount * (product.tax_rate / 100)
    })

    return {
      subtotal,
      tax,
      total: subtotal + tax,
    }
  }, [lines, products])

  const updateLine = (id: number, changes: Partial<SaleLine>) => {
    setLines((current) =>
      current.map((line) =>
        line.id === id ? { ...line, ...changes } : line
      )
    )
  }

  const addLine = () => {
    setLines((current) => [
      ...current,
      {
        id: nextId,
        product_id: '',
        quantity: '1',
        unit_price: 0,
        discount_amount: '0',
      },
    ])
    setNextId((current) => current + 1)
  }

  const removeLine = (id: number) => {
    setLines((current) => current.filter((line) => line.id !== id))
  }

  const handleProductChange = (lineId: number, productId: string) => {
    const product = products.find((item) => item.id === productId)

    updateLine(lineId, {
      product_id: productId,
      unit_price: product?.selling_price ?? 0,
    })
  }

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setError('')

    if (lines.length === 0 || lines.some((line) => !line.product_id)) {
      setError('Please select a product for every sale item.')
      return
    }

    if (lines.some((line) => !Number.isFinite(Number(line.quantity)) || Number(line.quantity) <= 0)) {
      setError('Every item must have a quantity greater than zero.')
      return
    }

    if (warehouseRequired && !warehouseId) {
      setError('Please select a warehouse for inventory-tracked products.')
      return
    }

    const payload: SaleCreateRequest = {
      branch_id: branchId,
      customer_id: customerId || null,
      warehouse_id: warehouseId || null,
      discount_amount: 0,
      shipping_charge: 0,
      other_charges: 0,
      notes: notes.trim() || null,
      items: lines.map((line) => ({
        product_id: line.product_id,
        quantity: Number(line.quantity),
        unit_price: line.unit_price,
        discount_amount: Number(line.discount_amount) || 0,
      })),
    }

    setSaving(true)

    try {
      await salesApi.createSaleDraft(payload)
      onCreated()
    } catch (err) {
      console.error('Sale draft creation failed:', err)
      setError('Unable to save sale draft. Please check the details and try again.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return <section className="panel"><p>Loading sale form...</p></section>
  }

  return (
    <section className="panel new-sale-panel">
      <div className="panel-header">
        <div>
          <h2>New Sale</h2>
          <p>Create a sales invoice draft</p>
        </div>
        <button type="button" className="outline-button" onClick={onCancel}>
          <ArrowLeft size={16} /> Back to Sales
        </button>
      </div>

      {error && <p className="sale-form-error" role="alert">{error}</p>}

      <form onSubmit={handleSubmit}>
        <div className="sale-form-grid">
          <label>
            Customer
            <select
              value={customerId}
              onChange={(event) => setCustomerId(event.target.value)}
            >
              <option value="">Walk-in Customer</option>
              {customers.map((customer) => (
                <option key={customer.id} value={customer.id}>
                  {customer.customer_name}
                  {customer.phone ? ` (${customer.phone})` : ''}
                </option>
              ))}
            </select>
          </label>

          <label>
            Warehouse {warehouseRequired ? '*' : ''}
            <select
              value={warehouseId}
              onChange={(event) => setWarehouseId(event.target.value)}
            >
              <option value="">Select warehouse</option>
              {warehouses.map((warehouse) => (
                <option key={warehouse.id} value={warehouse.id}>
                  {warehouse.warehouse_name} ({warehouse.warehouse_code})
                </option>
              ))}
            </select>
          </label>
        </div>

        <div className="sale-items-heading">
          <h3>Sale Items</h3>
          <button type="button" className="outline-button" onClick={addLine}>
            <Plus size={16} /> Add Item
          </button>
        </div>

        {lines.map((line) => {
          const product = products.find((item) => item.id === line.product_id)

          return (
            <div className="sale-item-row" key={line.id}>
              <label className="sale-product-field">
                Product
                <select
                  value={line.product_id}
                  onChange={(event) =>
                    handleProductChange(line.id, event.target.value)
                  }
                  required
                >
                  <option value="">Select product</option>
                  {products.map((item) => (
                    <option key={item.id} value={item.id}>
                      {item.product_name} {item.sku ? `— ${item.sku}` : ''}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                SKU
                <input value={product?.sku ?? '—'} readOnly />
              </label>

              <label>
                Unit
                <input value={product?.unit_symbol ?? '—'} readOnly />
              </label>

              <label>
                Price (₹)
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={line.unit_price}
                  onChange={(event) =>
                    updateLine(line.id, { unit_price: Number(event.target.value) })
                  }
                />
              </label>

              <label>
                Qty
                <input
                  type="number"
                  min={product ? 1 / (10 ** product.decimal_places) : 0.001}
                  step={product ? 1 / (10 ** product.decimal_places) : 'any'}
                  value={line.quantity}
                  onChange={(event) =>
                    updateLine(line.id, { quantity: event.target.value })
                  }
                  required
                />
              </label>

              <label>
                Discount (₹)
                <input
                  type="number"
                  min="0"
                  step="0.01"
                  value={line.discount_amount}
                  onChange={(event) =>
                    updateLine(line.id, { discount_amount: event.target.value })
                  }
                />
              </label>

              <label>
                Tax
                <input value={product ? `${product.tax_rate}%` : '—'} readOnly />
              </label>

              <button
                type="button"
                className="sale-remove-button"
                onClick={() => removeLine(line.id)}
                disabled={lines.length === 1}
                aria-label="Remove item"
              >
                <Trash2 size={17} />
              </button>
            </div>
          )
        })}

        <label className="sale-notes-field">
          Notes
          <textarea
            rows={3}
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
            placeholder="Optional sale notes"
          />
        </label>

        <div className="sale-total-box">
          <div><span>Subtotal</span><strong>₹ {totals.subtotal.toFixed(2)}</strong></div>
          <div><span>Tax</span><strong>₹ {totals.tax.toFixed(2)}</strong></div>
          <div className="sale-grand-total">
            <span>Total</span><strong>₹ {totals.total.toFixed(2)}</strong>
          </div>
        </div>

        <div className="sale-form-actions">
          <button type="button" className="outline-button" onClick={onCancel}>
            Cancel
          </button>
          <button type="submit" className="primary-button" disabled={saving || products.length === 0}>
            {saving ? 'Saving...' : 'Save as Draft'}
          </button>
        </div>
      </form>
    </section>
  )
}
