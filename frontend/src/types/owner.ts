export interface Owner {
  membership_id: string
  user_id: string
  full_name: string
  email: string
  phone: string | null
  status: 'active' | 'inactive'
  created_at: string
  updated_at: string | null
}

export interface OwnerListResponse {
  owners: Owner[]
}
export interface OwnerCreateRequest {
  full_name: string
  email: string
  phone?: string | null
  password?: string | null
}

export interface OwnerCreateResponse {
  membership_id: string
  user_id: string
  full_name: string
  email: string
  status: 'active'
  new_user_created: boolean
}
export interface OwnerStatusUpdateRequest {
  status: 'active' | 'inactive'
}

export interface OwnerStatusUpdateResponse {
  membership_id: string
  status: 'active' | 'inactive'
}

export interface OwnerProfileUpdateRequest {
  full_name: string
  phone?: string | null
}

export interface OwnerProfileUpdateResponse {
  user_id: string
  profile: {
    full_name: string
    phone: string | null
  }
}
