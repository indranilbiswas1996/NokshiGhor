
export interface User {
  id: string
  full_name: string
  email: string
  profile_picture: string | null
  is_super_admin: boolean
}

export interface LoginRequest {
  email: string
  password: string
}

export interface LoginResponse {
  access_token: string
  token_type: string
  expires_in: number
  user: User
}

export interface Business {
  id: string
  business_name: string
  business_type: string
  status: string
  role_name: string
}

export interface BusinessListResponse {
  businesses: Business[]
  total: number
  is_super_admin: boolean
}

export interface BusinessSelectRequest {
  business_id: string
}

export interface BusinessSelectResponse {
  access_token: string
  token_type: string
  expires_in: number
  business: Business
}
