import apiClient from './client'

export interface ManagedBusiness {
  id: string
  business_name: string
  business_type: 'electrical' | 'interior' | 'both' | 'other'
  status: 'active' | 'inactive'
}

interface ManagedBusinessListResponse {
  businesses: ManagedBusiness[]
}

export const superAdminApi = {
  async getBusinesses(): Promise<ManagedBusinessListResponse> {
    const response = await apiClient.get<ManagedBusinessListResponse>(
      '/super-admin/businesses'
    )
    return response.data
  },

  async createBusiness(payload: {
    business_name: string
    business_type: ManagedBusiness['business_type']
  }): Promise<ManagedBusiness> {
    const response = await apiClient.post<ManagedBusiness>(
      '/super-admin/businesses',
      payload
    )
    return response.data
  },

  async setBusinessStatus(
    businessId: string,
    status: ManagedBusiness['status'],
  ): Promise<ManagedBusiness> {
    const response = await apiClient.patch<ManagedBusiness>(
      `/super-admin/businesses/${businessId}/status`,
      { status },
    )
    return response.data
  },
}
