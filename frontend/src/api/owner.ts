
import apiClient from './client'
import type {
  OwnerListResponse,
  OwnerCreateRequest,
  OwnerCreateResponse,
  OwnerStatusUpdateRequest,
  OwnerStatusUpdateResponse,
  OwnerProfileUpdateRequest,
  OwnerProfileUpdateResponse,
} from '../types/owner'

export const ownerApi = {
  async getOwners(): Promise<OwnerListResponse> {
    const response = await apiClient.get<OwnerListResponse>('/owners')
    return response.data
  },

  async createOwner(
    payload: OwnerCreateRequest
  ): Promise<OwnerCreateResponse> {
    const response = await apiClient.post<OwnerCreateResponse>(
      '/owners',
      payload
    )
    return response.data
  },

  async setOwnerStatus(
    membershipId: string,
    payload: OwnerStatusUpdateRequest
  ): Promise<OwnerStatusUpdateResponse> {
    const response = await apiClient.patch<OwnerStatusUpdateResponse>(
      `/owners/${membershipId}/status`,
      payload
    )
    return response.data
  },

  async updateMyProfile(
    payload: OwnerProfileUpdateRequest
  ): Promise<OwnerProfileUpdateResponse> {
    const response = await apiClient.patch<OwnerProfileUpdateResponse>(
      '/owners/me/profile',
      payload
    )
    return response.data
  },
}
