
export interface SaleItemCreate {
  product_id: string
  quantity: number
  unit_price?: number | null
  discount_amount?: number
}

export interface SaleCreateRequest {
  branch_id?: string | null
  customer_id?: string | null
  warehouse_id?: string | null
  sale_date?: string
  due_date?: string | null
  discount_amount?: number
  shipping_charge?: number
  other_charges?: number
  notes?: string | null
  items: SaleItemCreate[]
}

export interface SaleItem {
  id: string
  product_id: string
  product_name_snapshot: string
  sku_snapshot: string | null
  quantity: number
  unit_id: string
  unit_price: number
  discount_amount: number
  tax_rate: number
  tax_amount: number
  line_total: number
}

export interface Sale {
  id: string
  sale_number: string
  sale_date: string
  due_date: string | null
  sale_status: string
  payment_status: string
  subtotal: number
  discount_amount: number
  tax_amount: number
  shipping_charge: number
  other_charges: number
  round_off: number
  total_amount: number
  paid_amount: number
  customer_name_snapshot: string
  shop_name_snapshot: string
  items: SaleItem[]
}
export interface SaleListItem {
  id: string
  sale_number: string
  sale_date: string
  due_date: string | null
  sale_status: string
  payment_status: string
  subtotal: number
  discount_amount: number
  tax_amount: number
  shipping_charge: number
  other_charges: number
  round_off: number
  total_amount: number
  paid_amount: number
  customer_name_snapshot: string
  customer_phone_snapshot: string | null
  shop_name_snapshot: string
  created_at: string
}

export interface SaleListResponse {
  items: SaleListItem[]
  total_count: number
  limit: number
  offset: number
}

export interface SaleDraftResponse {
  message: string
  sale_id: string
  sale_status: string
}

export interface SalesProduct {
  id: string
  product_name: string
  sku: string | null
  unit_id: string
  unit_name: string
  unit_symbol: string
  decimal_places: number
  selling_price: number
  tax_rate: number
  track_inventory: boolean
}

export interface SalesCustomer {
  id: string
  customer_name: string
  phone: string | null
}

export interface SalesWarehouse {
  id: string
  warehouse_name: string
  warehouse_code: string
  is_default: boolean
  branch_id: string
}