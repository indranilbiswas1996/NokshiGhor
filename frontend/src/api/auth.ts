
import apiClient from './client'
import type {
  LoginRequest,
  LoginResponse,
  User,
  Business,
  BusinessListResponse,
  BusinessSelectResponse,
} from '../types/auth'

export const authApi = {
  async login(data: LoginRequest): Promise<LoginResponse> {
    const response = await apiClient.post<LoginResponse>(
      '/auth/login',
      data
    )

    localStorage.setItem(
      'nokshighor-access-token',
      response.data.access_token
    )

    return response.data
  },

  async getProfile(): Promise<User> {
    const response = await apiClient.get<User>('/auth/me')
    return response.data
  },

  async changePassword(data: {
    current_password: string
    new_password: string
  }): Promise<{ message: string }> {
    const response = await apiClient.post<{ message: string }>(
      '/auth/password/change',
      data,
    )
    return response.data
  },

  async requestPasswordReset(email: string): Promise<{ message: string }> {
    const response = await apiClient.post<{ message: string }>(
      '/auth/password/forgot',
      { email },
    )
    return response.data
  },

  async resetPassword(data: {
    token: string
    new_password: string
  }): Promise<{ message: string }> {
    const response = await apiClient.post<{ message: string }>(
      '/auth/password/reset',
      data,
    )
    return response.data
  },

  async getBusinesses(): Promise<BusinessListResponse> {
    const response = await apiClient.get<BusinessListResponse>(
      '/auth/businesses'
    )

    return response.data
  },

  async selectBusiness(businessId: string): Promise<BusinessSelectResponse> {
    const response = await apiClient.post<BusinessSelectResponse>(
      '/auth/businesses/select',
      { business_id: businessId }
    )

    localStorage.setItem(
      'nokshighor-access-token',
      response.data.access_token
    )

    localStorage.setItem(
      'nokshighor-current-business',
      JSON.stringify(response.data.business)
    )

    return response.data
  },

  async getCurrentBusiness(): Promise<Business> {
    const response = await apiClient.get<Business>(
      '/auth/current-business'
    )

    return response.data
  },

  async logout(): Promise<void> {
    try {
      await apiClient.post('/auth/logout')
    } finally {
      localStorage.removeItem('nokshighor-access-token')
      localStorage.removeItem('nokshighor-current-business')
    }
  },
}
