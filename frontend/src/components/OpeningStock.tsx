import { useEffect, useMemo, useState } from 'react'
import { isAxiosError } from 'axios'
import { ArrowLeft, Plus, Trash2, PackagePlus, LoaderCircle, CheckCircle2 } from 'lucide-react'
import { salesApi } from '../api/sales'
import { openingStockApi } from '../api/openingStock'
import type { SalesProduct, SalesWarehouse } from '../types/sales'
import type {
  OpeningStockResponse,
  OpeningStockDraft,
} from '../types/openingStock'
import './OpeningStock.css'

interface OpeningStockProps {
  branchId: string | null
  onCancel: () => void
  onCompleted: () => void
}

interface StockRow {
  rowId: number
  product_id: string
  quantity: string
  unit_cost: string
}

function getErrorMessage(error: unknown): string {
  if (isAxiosError(error)) {
    return error.response?.data?.detail || error.message || 'Something went wrong.'
  }
  return error instanceof Error ? error.message : 'Something went wrong.'
}

export default function OpeningStock({ branchId, onCancel, onCompleted }: OpeningStockProps) {
  const [products, setProducts] = useState<SalesProduct[]>([])
  const [warehouses, setWarehouses] = useState<SalesWarehouse[]>([])
  const [warehouseId, setWarehouseId] = useState('')
  const [openingDate, setOpeningDate] = useState(new Date().toISOString().slice(0, 10))
  const [notes, setNotes] = useState('')
  const [rows, setRows] = useState<StockRow[]>([
    { rowId: 1, product_id: '', quantity: '', unit_cost: '0' },
  ])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [posting, setPosting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [draft, setDraft] = useState<OpeningStockResponse | null>(null)
  const [savedDrafts, setSavedDrafts] = useState<OpeningStockDraft[]>([])
  const [loadingDrafts, setLoadingDrafts] = useState(false)
  const [editing, setEditing] = useState(false)
  const [updating, setUpdating] = useState(false)
  const [nextRowId, setNextRowId] = useState(2)

  useEffect(() => {
    let ignore = false

    async function loadReferences() {
      setLoading(true)
      setError('')
      try {
        setLoadingDrafts(true)
        const [productList, warehouseList, draftResponse] = await Promise.all([
            salesApi.getSalesProducts(),
            salesApi.getSalesWarehouses(),
            openingStockApi.getDrafts(branchId),
        ])

        if (ignore) return

        setProducts(productList.filter((product) => product.track_inventory))
        const availableWarehouses = warehouseList.filter(
          (warehouse) => !branchId || warehouse.branch_id === branchId
        )
        setWarehouses(availableWarehouses)
        setSavedDrafts(draftResponse.drafts.filter(
          (draftItem) => !branchId || availableWarehouses.some(
            (warehouse) => warehouse.id === draftItem.warehouse_id
          )
        ))
        const defaultWarehouse = availableWarehouses.find((warehouse) => warehouse.is_default)
        if (defaultWarehouse) setWarehouseId(defaultWarehouse.id)
        else if (availableWarehouses.length > 0) setWarehouseId(availableWarehouses[0].id)
        else setWarehouseId('')
      } catch (err) {
        if (!ignore) setError(getErrorMessage(err))
      } finally {
        setLoadingDrafts(false)
        if (!ignore) setLoading(false)
      }
    }

    loadReferences()
    return () => { ignore = true }
  }, [branchId])

  const totalValue = useMemo(() => rows.reduce((total, row) => {
    return total + (Number(row.quantity) || 0) * (Number(row.unit_cost) || 0)
  }, 0), [rows])

  const selectedProductIds = rows.map((row) => row.product_id).filter(Boolean)
  async function refreshSavedDrafts() {
    try {
        const response = await openingStockApi.getDrafts(branchId)
        setSavedDrafts(response.drafts.filter(
          (draftItem) => !branchId || warehouses.some(
            (warehouse) => warehouse.id === draftItem.warehouse_id
          )
        ))
    } catch (err) {
        setError(getErrorMessage(err))
    }
    }

  function updateRow(rowId: number, field: keyof StockRow, value: string) {
    setRows((current) => current.map((row) =>
      row.rowId === rowId ? { ...row, [field]: value } : row
    ))
  }

  function addRow() {
    setRows((current) => [
      ...current,
      { rowId: nextRowId, product_id: '', quantity: '', unit_cost: '0' },
    ])
    setNextRowId((current) => current + 1)
  }

  function removeRow(rowId: number) {
    setRows((current) => current.length > 1
      ? current.filter((row) => row.rowId !== rowId)
      : current
    )
  }

    function handleOpenSavedDraft(savedDraft: OpeningStockDraft) {
    setError('')
    setSuccess('')

    setDraft({
        message: 'Opening stock draft loaded',
        document_id: savedDraft.document_id,
        opening_status: 'draft',
    })

    setWarehouseId(savedDraft.warehouse_id)
    setOpeningDate(savedDraft.opening_date)
    setNotes(savedDraft.notes || '')

    setRows(
        savedDraft.items.map((item, index) => ({
        rowId: index + 1,
        product_id: item.product_id,
        quantity: String(item.quantity),
        unit_cost: String(item.unit_cost),
        }))
    )

    setNextRowId(savedDraft.items.length + 1)
    setEditing(false)
    }

  async function handleCreateDraft() {
    setError('')
    setSuccess('')

    if (!warehouseId) {
      setError('Please select a warehouse.')
      return
    }

    if (rows.some((row) => !row.product_id || !row.quantity || Number(row.quantity) <= 0)) {
      setError('Select a product and enter a valid quantity for every row.')
      return
    }

    if (rows.some((row) => Number(row.unit_cost) < 0 || !Number.isFinite(Number(row.unit_cost)))) {
      setError('Enter a valid unit cost for every product.')
      return
    }

    setSaving(true)
    try {
      const response = await openingStockApi.createDraft({
        branch_id: branchId,
        warehouse_id: warehouseId,
        opening_date: openingDate,
        notes: notes.trim() || null,
        items: rows.map((row) => ({
          product_id: row.product_id,
          quantity: Number(row.quantity),
          unit_cost: Number(row.unit_cost),
        })),
      })
      setDraft(response)
      await refreshSavedDrafts()
      setSuccess('Opening stock draft created successfully.')
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setSaving(false)
    }
  }
  async function handleUpdateDraft() {
    if (!draft || draft.opening_status !== 'draft') return

    setError('')
    setSuccess('')

    if (!warehouseId) {
        setError('Please select a warehouse.')
        return
    }

    if (rows.some((row) => !row.product_id || !row.quantity || Number(row.quantity) <= 0)) {
        setError('Select a product and enter a valid quantity for every row.')
        return
    }

    if (rows.some((row) => Number(row.unit_cost) < 0 || !Number.isFinite(Number(row.unit_cost)))) {
        setError('Enter a valid unit cost for every product.')
        return
    }

    setUpdating(true)

    try {
        const response = await openingStockApi.updateDraft(draft.document_id, {
        branch_id: branchId,
        warehouse_id: warehouseId,
        opening_date: openingDate,
        notes: notes.trim() || null,
        items: rows.map((row) => ({
            product_id: row.product_id,
            quantity: Number(row.quantity),
            unit_cost: Number(row.unit_cost),
        })),
        })

        setDraft(response)
        setEditing(false)
        await refreshSavedDrafts()
        setSuccess('Opening stock draft updated successfully.')
    } catch (err) {
        setError(getErrorMessage(err))
    } finally {
        setUpdating(false)
    }
    }
  async function handlePostStock() {
    if (!draft || draft.opening_status !== 'draft') return

    const confirmed = window.confirm(
      'Post this opening stock? This action will update inventory and cannot be reversed by editing the document.'
    )
    if (!confirmed) return

    setError('')
    setSuccess('')
    setPosting(true)
    try {
      const response = await openingStockApi.postOpeningStock(
        draft.document_id,
        branchId,
      )
      setDraft(response)
      await refreshSavedDrafts()
      setSuccess('Opening stock posted successfully. Inventory has been updated.')
    } catch (err) {
      setError(getErrorMessage(err))
    } finally {
      setPosting(false)
    }
  }

  const selectedWarehouse = warehouses.find((warehouse) => warehouse.id === warehouseId)

  if (loading) {
    return <div className="opening-stock-loading"><LoaderCircle className="opening-stock-spin" /> Loading stock references...</div>
  }

  return (
    <section className="opening-stock-page">
      <div className="opening-stock-heading">
        <button className="opening-stock-back" onClick={onCancel}>
          <ArrowLeft size={17} /> Back
        </button>
        <div>
          <div className="opening-stock-eyebrow">INVENTORY MANAGEMENT</div>
          <h2><PackagePlus size={23} /> Opening Stock</h2>
          <p>Enter the initial stock quantities for your warehouse.</p>
        </div>
      </div>

      {error && <div className="opening-stock-alert error" role="alert">{error}</div>}
      {success && <div className="opening-stock-alert success"><CheckCircle2 size={17} /> {success}</div>}
        <div className="opening-stock-card opening-stock-saved-drafts">
        <div className="opening-stock-card-title">
            <div>
            <h3>Saved Opening Stock Drafts</h3>
            <span>Continue working on previously saved drafts.</span>
            </div>
            <span>{savedDrafts.length} Draft(s)</span>
        </div>

        {loadingDrafts ? (
            <p>Loading saved drafts...</p>
        ) : savedDrafts.length === 0 ? (
            <p>No saved opening stock drafts found.</p>
        ) : (
            <div className="opening-stock-draft-list">
            {savedDrafts.map((item) => (
                <div className="opening-stock-draft-list-item" key={item.document_id}>
                <div>
                    <strong>{item.opening_number}</strong>
                    <span>{item.opening_date}</span>
                    <small>
                    {item.items.length} product(s) · {item.notes || 'No notes'}
                    </small>
                </div>

                <button
                    className="opening-stock-cancel"
                    onClick={() => handleOpenSavedDraft(item)}
                >
                    Open Draft
                </button>
                </div>
            ))}
            </div>
        )}
        </div>

      {products.length === 0 || warehouses.length === 0 ? (
        <div className="opening-stock-empty">
          {products.length === 0
            ? 'No inventory-tracked products found. Create an inventory product first.'
            : 'No warehouse found. Create a warehouse first.'}
        </div>
      ) : (
        <>
          <div className="opening-stock-card">
            <div className="opening-stock-card-title">
              <h3>Document Information</h3>
              <span>Required details</span>
            </div>

            <div className="opening-stock-fields">
              <label>
                Warehouse <span>*</span>
                <select value={warehouseId} onChange={(event) => setWarehouseId(event.target.value)} disabled={!!draft && !editing}>
                  {warehouses.map((warehouse) => (
                    <option key={warehouse.id} value={warehouse.id}>
                      {warehouse.warehouse_name}{warehouse.is_default ? ' (Default)' : ''}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                Opening Date <span>*</span>
                <input type="date" value={openingDate} onChange={(event) => setOpeningDate(event.target.value)} disabled={!!draft && !editing} />
              </label>

              <label className="opening-stock-notes">
                Notes
                <textarea value={notes} onChange={(event) => setNotes(event.target.value)} placeholder="Optional notes..." disabled={!!draft && !editing} />
              </label>
            </div>
          </div>

          <div className="opening-stock-card">
            <div className="opening-stock-card-title">
              <div>
                <h3>Product Items</h3>
                <span>Add the opening quantity and purchase cost for each product.</span>
              </div>
              {(!draft || editing) && (
                <button className="opening-stock-add" onClick={addRow}>
                  <Plus size={16} /> Add Product
                </button>
              )}
            </div>

            <div className="opening-stock-table-wrap">
              <table className="opening-stock-table">
                <thead>
                  <tr>
                    <th>Product</th>
                    <th>Quantity</th>
                    <th>Unit Cost ()</th>
                    <th>Amount ()</th>
                    {!draft && <th></th>}
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => {
                    const product = products.find((item) => item.id === row.product_id)
                    const amount = (Number(row.quantity) || 0) * (Number(row.unit_cost) || 0)

                    return (
                      <tr key={row.rowId}>
                        <td>
                          <select
                            value={row.product_id}
                            disabled={!!draft && !editing}
                            onChange={(event) => updateRow(row.rowId, 'product_id', event.target.value)}
                          >
                            <option value="">Select product</option>
                            {products.map((item) => (
                              <option
                                key={item.id}
                                value={item.id}
                                disabled={item.id !== row.product_id && selectedProductIds.includes(item.id)}
                              >
                                {item.product_name}{item.sku ? ` (${item.sku})` : ''}
                              </option>
                            ))}
                          </select>
                          {product && <small>{product.unit_name} ({product.unit_symbol})</small>}
                        </td>
                        <td>
                          <input
                            type="number"
                            min="0.001"
                            step={product ? Math.pow(10, -product.decimal_places) : '0.001'}
                            value={row.quantity}
                            placeholder="0"
                            disabled={!!draft && !editing}
                            onChange={(event) => updateRow(row.rowId, 'quantity', event.target.value)}
                          />
                        </td>
                        <td>
                          <input
                            type="number"
                            min="0"
                            step="0.01"
                            value={row.unit_cost}
                            disabled={!!draft && !editing}
                            onChange={(event) => updateRow(row.rowId, 'unit_cost', event.target.value)}
                          />
                        </td>
                        <td className="opening-stock-amount">{amount.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</td>
                        {(!draft || editing) && (
                          <td>
                            <button className="opening-stock-remove" onClick={() => removeRow(row.rowId)} disabled={rows.length === 1} aria-label="Remove product">
                              <Trash2 size={16} />
                            </button>
                          </td>
                        )}
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>

            <div className="opening-stock-total">
              <span>Total Opening Stock Value</span>
              <strong> {totalValue.toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</strong>
            </div>
          </div>

          {draft && (
            <div className="opening-stock-draft">
              <div>
                <span>Document ID</span>
                <strong>{draft.document_id}</strong>
                <span>Status: <b>{draft.opening_status.toUpperCase()}</b></span>
              </div>
              {draft.opening_status === 'draft' ? (
                <div className="opening-stock-draft-actions">
                    {editing ? (
                    <>
                        <button
                        className="opening-stock-cancel"
                        onClick={() => setEditing(false)}
                        disabled={updating}
                        >
                        Cancel Edit
                        </button>

                        <button
                        className="opening-stock-save"
                        onClick={handleUpdateDraft}
                        disabled={updating}
                        >
                        {updating
                            ? <LoaderCircle className="opening-stock-spin" size={17} />
                            : <CheckCircle2 size={17} />}
                        {updating ? 'Updating...' : 'Save Changes'}
                        </button>
                    </>
                    ) : (
                    <>
                        <button
                        className="opening-stock-cancel"
                        onClick={() => setEditing(true)}
                        >
                        Edit Draft
                        </button>

                        <button
                        className="opening-stock-post"
                        onClick={handlePostStock}
                        disabled={posting}
                        >
                        {posting
                            ? <LoaderCircle className="opening-stock-spin" size={17} />
                            : <CheckCircle2 size={17} />}
                        {posting ? 'Posting...' : 'Post Opening Stock'}
                        </button>
                    </>
                    )}
                </div>
                ) : (
                <button className="opening-stock-post" onClick={onCompleted}>
                    <CheckCircle2 size={17} /> Done
                </button>
                )}
            </div>
          )}

          {!draft && (
            <div className="opening-stock-actions">
              <button className="opening-stock-cancel" onClick={onCancel}>Cancel</button>
              <button className="opening-stock-save" onClick={handleCreateDraft} disabled={saving}>
                {saving ? <LoaderCircle className="opening-stock-spin" size={17} /> : <PackagePlus size={17} />}
                {saving ? 'Saving Draft...' : 'Save Opening Stock Draft'}
              </button>
            </div>
          )}
        </>
      )}

      {selectedWarehouse && <span className="opening-stock-hidden">{selectedWarehouse.warehouse_code}</span>}
    </section>
  )
}
