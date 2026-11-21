
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

  async setBranchStatus(
    branchId: string,
    isActive: boolean
  ): Promise<{ branch: Branch }> {
    const response = await apiClient.patch<{ branch: Branch }>(
      `/branches/${branchId}/status`,
      { is_active: isActive }
    )
    return response.data
  },
  async setDefaultBranch(branchId: string): Promise<{ branch: Branch }> {
    const response = await apiClient.patch<{ branch: Branch }>(
      `/branches/${branchId}/default`
    )
    return response.data
  },
  async assignBranchAdmin(
    branchId: string,
    data: {
      business_user_id: string
      notes?: string | null
    }
  ): Promise<BranchAdminAssignmentResponse> {
    const response = await apiClient.post<BranchAdminAssignmentResponse>(
      `/branches/${branchId}/admins`,
      data
    )

    return response.data
  },

  async getBranchAdminCandidates(
    branchId: string
  ): Promise<BranchAdminCandidatesResponse> {
    const response = await apiClient.get<BranchAdminCandidatesResponse>(
      `/branches/${branchId}/admin-candidates`
    )

    return response.data
  },
  async createBranchAdmin(
    payload: BranchAdminCreateRequest
  ): Promise<BranchAdminCreateResponse> {
    const response = await apiClient.post<BranchAdminCreateResponse>(
      '/branches/admins',
      payload
    )
    return response.data
  },

  async getBranchAdmins(
    branchId: string
  ): Promise<BranchAdminListResponse> {
    const response = await apiClient.get<BranchAdminListResponse>(
      `/branches/${branchId}/admins`
    )
    return response.data
  },
  async getMasterBranchAdmins(): Promise<MasterBranchAdminListResponse> {
    const response = await apiClient.get<MasterBranchAdminListResponse>(
      '/branches/master-admins'
    )
    return response.data
  },
}

export interface BranchAdminAssignment {
  id: string
  business_id: string
  branch_id: string
  business_user_id: string
  assignment_type: 'branch_admin' | 'employee'
  assignment_status: 'active' | 'revoked'
  effective_from: string
  assigned_at: string
  assigned_by: string
  notes: string | null
}

export interface BranchAdminCandidate {
  business_user_id: string
  user_id: string
  full_name: string
  email: string | null
  phone: string | null
}
export interface BranchAdminCandidatesResponse {
  candidates: BranchAdminCandidate[]
}
export interface BranchAdminAssignmentResponse {
  assignment: BranchAdminAssignment
}

export interface BranchAdminCreateRequest {
  full_name: string
  email: string
  phone: string | null
  password: string
}

export interface BranchAdminCreateResponse {
  admin: {
    business_user_id: string
    user_id: string
    full_name: string
    email: string
    phone: string | null
    role_name: string
    new_user_created: boolean
  }
}


export interface BranchAdmin {
  assignment_id: string
  business_user_id: string
  user_id: string
  full_name: string
  email: string | null
  phone: string | null
  assignment_status: string
  assigned_at: string
  assigned_by: string
  notes: string | null
}

export interface BranchAdminListResponse {
  admins: BranchAdmin[]
}

export interface MasterBranchAdmin {
  assignment_id: string
  branch_id: string
  branch_name: string
  business_user_id: string
  user_id: string
  full_name: string
  email: string
  phone: string | null
  assignment_status: string
  assigned_at: string
  notes: string | null
}

export interface MasterBranchAdminListResponse {
  admins: MasterBranchAdmin[]
}