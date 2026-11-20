import apiClient from './client'
import type {
  SaleCreateRequest,
  Sale,
  SaleListResponse,
  SaleDraftResponse,
  SalesProduct,
  SalesCustomer,
  SalesWarehouse,
} from '../types/sales'

export const salesApi = {
  async getSales(params?: {
    limit?: number
    offset?: number
    sale_status?: string
  }): Promise<SaleListResponse> {
    const response = await apiClient.get<SaleListResponse>('/sales', {
      params,
    })
    return response.data
  },

  async getSaleDetails(saleId: string): Promise<Sale> {
    const response = await apiClient.get<Sale>(`/sales/${saleId}`)
    return response.data
  },

  async getSalesProducts(): Promise<SalesProduct[]> {
    const response = await apiClient.get<SalesProduct[]>(
      '/sales/reference/products'
    )
    return response.data
  },

  async getSalesCustomers(): Promise<SalesCustomer[]> {
    const response = await apiClient.get<SalesCustomer[]>(
      '/sales/reference/customers'
    )
    return response.data
  },

  async getSalesWarehouses(): Promise<SalesWarehouse[]> {
    const response = await apiClient.get<SalesWarehouse[]>(
      '/sales/reference/warehouses'
    )
    return response.data
  },

  async createSaleDraft(
    payload: SaleCreateRequest
  ): Promise<SaleDraftResponse> {
    const response = await apiClient.post<SaleDraftResponse>(
      '/sales/drafts',
      payload
    )
    return response.data
  },

  async postSale(saleId: string): Promise<{
    success: boolean
    message: string
    sale_id: string
  }> {
    const response = await apiClient.post<{
      success: boolean
      message: string
      sale_id: string
    }>(`/sales/${saleId}/post`)

    return response.data
  },

}