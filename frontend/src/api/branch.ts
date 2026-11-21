
import apiClient from './client'

export interface Branch {
  id: string
  branch_name: string
  branch_code: string | null
  address: string | null
  phone: string | null
  email: string | null
  is_default: boolean
  is_active: boolean
  created_at: string
  updated_at: string | null
}

interface BranchListResponse {
  branches: Branch[]
}


export const branchApi = {
  async getBranches(): Promise<BranchListResponse> {
    const response = await apiClient.get<BranchListResponse>('/branches')
    return response.data
  },

  async createBranch(payload: {
    branch_name: string
    branch_code?: string | null
    address?: string | null
    phone?: string | null
    email?: string | null
  }): Promise<{ branch: Branch }> {
    const response = await apiClient.post<{ branch: Branch }>(
      '/branches',
      payload
    )
    return response.data
  },

  async updateBranch(
    branchId: string,
    payload: {
      branch_name: string
      branch_code?: string | null
      address?: string | null
      phone?: string | null
      email?: string | null
    }
  ): Promise<{ branch: Branch }> {
    const response = await apiClient.put<{ branch: Branch }>(
      `/branches/${branchId}`,
      payload
    )
    return response.data
  },
}
