
import type { SalesProduct, SalesWarehouse } from './sales'

export interface OpeningStockItemCreate {
  product_id: string
  quantity: number
  unit_cost: number
  notes?: string | null
}

export interface OpeningStockCreateRequest {
  warehouse_id: string
  opening_date: string
  notes?: string | null
  items: OpeningStockItemCreate[]
}

export interface OpeningStockResponse {
  message: string
  document_id: string
  opening_status: 'draft' | 'posted'
}

export interface OpeningStockDraftItem {
  product_id: string
  quantity: number
  unit_id: string
  unit_cost: number
  notes: string | null
}

export interface OpeningStockDraft {
  document_id: string
  warehouse_id: string
  opening_number: string
  opening_date: string
  opening_status: 'draft'
  notes: string | null
  created_at: string
  updated_at: string
  items: OpeningStockDraftItem[]
}

export interface OpeningStockDraftListResponse {
  drafts: OpeningStockDraft[]
}

export type OpeningStockProduct = SalesProduct
export type OpeningStockWarehouse = SalesWarehouse
