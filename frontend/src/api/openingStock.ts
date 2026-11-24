
import apiClient from './client'
import type {
  OpeningStockCreateRequest,
  OpeningStockResponse,
  OpeningStockDraftListResponse,
} from '../types/openingStock'

export const openingStockApi = {
  async getDrafts(branchId?: string | null): Promise<OpeningStockDraftListResponse> {
    const response = await apiClient.get<OpeningStockDraftListResponse>(
      '/opening-stock/drafts',
      { params: branchId ? { branch_id: branchId } : undefined }
    )
    return response.data
  },

  async createDraft(
    payload: OpeningStockCreateRequest
  ): Promise<OpeningStockResponse> {
    const response = await apiClient.post<OpeningStockResponse>(
      '/opening-stock/drafts',
      payload
    )
    return response.data
  },

  async postOpeningStock(
    documentId: string,
    branchId?: string | null,
  ): Promise<OpeningStockResponse> {
    const response = await apiClient.post<OpeningStockResponse>(
      `/opening-stock/${documentId}/post`,
      undefined,
      { params: branchId ? { branch_id: branchId } : undefined }
    )
    return response.data
  },

  async updateDraft(
    documentId: string,
    payload: OpeningStockCreateRequest,
  ): Promise<OpeningStockResponse> {
    const response = await apiClient.put<OpeningStockResponse>(
      `/opening-stock/${documentId}/draft`,
      payload,
    )
    return response.data
  },
}
