import { authApi } from './api/auth'
import { useState, useEffect, useRef, useCallback, type CSSProperties } from 'react'
import {
  LayoutDashboard, Package, Boxes, ShoppingCart, ShoppingBag,
  Wallet, BriefcaseBusiness, ReceiptText, Users, Settings,
  Bell, Search, Menu, X, TrendingUp,
  ArrowUpRight, CalendarDays, Plus,
  ChevronDown, Zap, Languages, CircleHelp, Palette, LogOut
} from 'lucide-react'
import './App.css'
import AuthScreen from './components/AuthScreen'
import type { Business } from './types/auth'
import { salesApi } from './api/sales'
import type { SaleListItem } from './types/sales'
import NewSaleForm from './components/NewSaleForm'
import SaleDetails from './components/SaleDetails'
import OpeningStock from './components/OpeningStock'

const navigation = [
  { title: 'Overview', bn: 'সারসংক্ষেপ', items: [
    { label: 'Dashboard', bn: 'ড্যাশবোর্ড', icon: LayoutDashboard },
  ]},
  { title: 'Business', bn: 'ব্যবসা', items: [
    { label: 'Products', bn: 'পণ্য', icon: Package },
    { label: 'Inventory', bn: 'ইনভেন্টরি', icon: Boxes },
    { label: 'Purchase', bn: 'ক্রয়', icon: ShoppingCart },
    { label: 'Sales & POS', bn: 'বিক্রয় ও POS', icon: ShoppingBag },
    { label: 'Customers', bn: 'গ্রাহক', icon: Users },
  ]},
  { title: 'Management', bn: 'পরিচালনা', items: [
    { label: 'Accounts', bn: 'হিসাব', icon: Wallet },
    { label: 'Projects', bn: 'প্রজেক্ট', icon: BriefcaseBusiness },
    { label: 'Tax Management', bn: 'ট্যাক্স', icon: ReceiptText },
  ]},
]

const transactions = [
  { id: 'INV-2026-1042', name: 'Rahul Electrical Works', date: '19 Nov 2026', amount: '₹ 12,450', status: 'Paid', type: 'sale' },
  { id: 'PUR-2026-0281', name: 'Havells India Ltd.', date: '19 Nov 2026', amount: '₹ 28,600', status: 'Pending', type: 'purchase' },
  { id: 'INV-2026-1041', name: 'Saha Interior Solutions', date: '18 Nov 2026', amount: '₹ 8,750', status: 'Paid', type: 'sale' },
  { id: 'INV-2026-1040', name: 'Amit Kumar', date: '18 Nov 2026', amount: '₹ 3,200', status: 'Partial', type: 'sale' },
]

const chartBars = [38, 55, 43, 68, 49, 76, 57, 88, 65, 72, 52, 94]
const themes = [
  { name: 'Dusty Rose', color: '#A8797D', sidebar: '#49343B' },
  { name: 'Sage Green', color: '#8DA995', sidebar: '#30483F' },
  { name: 'Soft Blue', color: '#829DB8', sidebar: '#304357' },
  { name: 'Lavender', color: '#9A8BB5', sidebar: '#413750' },
  { name: 'Warm Amber', color: '#C49B68', sidebar: '#493B2C' },
  { name: 'Classic Maroon', color: '#824B52', sidebar: '#38252D' },
]
interface BrandSettings {
  softwareName: string
  tagline: string
  logo: string | null
}

const defaultBranding: BrandSettings = {
  softwareName: 'Business Manager',
  tagline: 'SMART BUSINESS MANAGEMENT',
  logo: null,
}

interface BusinessSettings {
  shopName: string
  businessType: string
  phone: string
  email: string
  address: string
  gstin: string
  invoiceFooter: string
}

const defaultBusinessSettings: BusinessSettings = {
  shopName: 'NokshiGhor',
  businessType: 'Electrical & Interior',
  phone: '',
  email: '',
  address: '',
  gstin: '',
  invoiceFooter: 'Thank you for your business!',
}
function App() {
  const [collapsed, setCollapsed] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)
  const [language, setLanguage] = useState<'en' | 'bn'>('en')
  const [activePage, setActivePage] = useState('Dashboard')
  const [isCreatingSale, setIsCreatingSale] = useState(false)
  const [selectedSaleId, setSelectedSaleId] = useState<string | null>(null)
  const [salesRefreshKey, setSalesRefreshKey] = useState(0)
  const [isCreatingOpeningStock, setIsCreatingOpeningStock] = useState(false)

  const bengali = language === 'bn'
  const [theme, setTheme] = useState(() => {
    return localStorage.getItem('nokshighor-theme') || '#A8797D'
  })

  const [customColor, setCustomColor] = useState('#A8797D')
  const [themePanelOpen, setThemePanelOpen] = useState(false)
  const themeControlRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const handleOutsideClick = (event: PointerEvent) => {
      if (
        themeControlRef.current &&
        !themeControlRef.current.contains(event.target as Node)
      ) {
        setThemePanelOpen(false)
      }
    }

    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setThemePanelOpen(false)
      }
    }

    document.addEventListener('pointerdown', handleOutsideClick)
    document.addEventListener('keydown', handleEscape)

    return () => {
      document.removeEventListener('pointerdown', handleOutsideClick)
      document.removeEventListener('keydown', handleEscape)
    }
  }, [])
  useEffect(() => {
    localStorage.setItem('nokshighor-theme', theme)
  }, [theme])
  const [branding, setBranding] = useState<BrandSettings>(() => {
  try {
    const saved = localStorage.getItem('nokshighor-branding')
    return saved
      ? { ...defaultBranding, ...JSON.parse(saved) }
      : defaultBranding
  } catch {
    return defaultBranding
  }
})
const [authenticatedBusiness, setAuthenticatedBusiness] =
useState<Business | null>(null)

const handleAuthenticated = useCallback((business: Business) => {
  setAuthenticatedBusiness(business)
}, [])
const handleLogout = async () => {
  try {
    await authApi.logout()
  } catch (error) {
    console.error('Logout failed:', error)
  } finally {
    setAuthenticatedBusiness(null)
  }
}
useEffect(() => {
  localStorage.setItem('nokshighor-branding', JSON.stringify(branding))
}, [branding])
const [businessSettings, setBusinessSettings] =
  useState<BusinessSettings>(() => {
    try {
      const saved = localStorage.getItem('nokshighor-business-settings')
      return saved
        ? { ...defaultBusinessSettings, ...JSON.parse(saved) }
        : defaultBusinessSettings
    } catch {
      return defaultBusinessSettings
    }
  })

useEffect(() => {
  localStorage.setItem(
    'nokshighor-business-settings',
    JSON.stringify(businessSettings)
  )
}, [businessSettings])

useEffect(() => {
  if (activePage !== 'Sales & POS' || !authenticatedBusiness) {
    return
  }

  let ignore = false

  const loadSales = async () => {
    setSalesLoading(true)
    setSalesError('')

    try {
      const response = await salesApi.getSales({
        limit: 20,
        offset: 0,
      })

      if (!ignore) {
        setSales(response.items)
        setSalesTotal(response.total_count)
      }
    } catch (error) {
      if (!ignore) {
        setSalesError(
          'Unable to load sales. Please try again.'
        )
        console.error('Sales loading failed:', error)
      }
    } finally {
      if (!ignore) {
        setSalesLoading(false)
      }
    }
  }

  loadSales()

  return () => {
    ignore = true
  }
}, [activePage, authenticatedBusiness, salesRefreshKey])

  const [sales, setSales] = useState<SaleListItem[]>([])
  const [salesLoading, setSalesLoading] = useState(false)
  const [salesError, setSalesError] = useState('')
  const [salesTotal, setSalesTotal] = useState(0)
  const pageNames: Record<string, string> = {
    Dashboard: 'ড্যাশবোর্ড',
    Products: 'পণ্য',
    Inventory: 'ইনভেন্টরি',
    Purchase: 'ক্রয়',
    'Sales & POS': 'বিক্রয় ও POS',
    Customers: 'গ্রাহক',
    Accounts: 'হিসাব',
    Projects: 'প্রজেক্ট',
    'Tax Management': 'ট্যাক্স ব্যবস্থাপনা',
    Settings: 'সেটিংস',
  }

  const stats = [
    { label: bengali ? 'আজকের বিক্রয়' : "Today's Sales", value: '₹ 24,580', change: '+12.8%', up: true, icon: ShoppingBag, color: 'green', note: bengali ? 'গতকালের তুলনায়' : 'vs yesterday' },
    { label: bengali ? 'মোট ক্রয়' : 'Total Purchase', value: '₹ 18,250', change: '+8.2%', up: true, icon: ShoppingCart, color: 'blue', note: bengali ? 'গতকালের তুলনায়' : 'vs yesterday' },
    { label: bengali ? 'স্টক মূল্য' : 'Stock Value', value: '₹ 8.42L', change: '4.5%', up: true, icon: Boxes, color: 'purple', note: bengali ? 'মোট পণ্যের মূল্য' : 'total inventory value' },
    { label: bengali ? 'আজকের লাভ' : "Today's Profit", value: '₹ 6,330', change: '+15.3%', up: true, icon: TrendingUp, color: 'orange', note: bengali ? 'গতকালের তুলনায়' : 'vs yesterday' },
  ]
if (!authenticatedBusiness) {
  return <AuthScreen onAuthenticated={handleAuthenticated} />
}
  return (
    <div
      className={`app-shell ${collapsed ? 'sidebar-collapsed' : ''}`}
      style={{
        '--accent': theme,
        '--sidebar-bg':
          themes.find((item) => item.color === theme)?.sidebar || '#49343B',
      } as CSSProperties}
    >
      {mobileOpen && <button className="mobile-overlay" onClick={() => setMobileOpen(false)} aria-label="Close menu" />}

      <aside className={`sidebar ${mobileOpen ? 'mobile-open' : ''}`}>
        <div className="brand">
          <div className="brand-mark">
            {branding.logo ? (
              <img
                src={branding.logo}
                alt={branding.softwareName}
                className="brand-logo-image"
              />
            ) : (
              <Zap size={23} fill="currentColor" />
            )}
          </div>

          <div className="brand-text">
            <strong>{branding.softwareName}</strong>
            <span>{branding.tagline}</span>
          </div>
          <button className="mobile-close" onClick={() => setMobileOpen(false)} aria-label="Close sidebar"><X size={19} /></button>
        </div>

        <div className="business-switch">
          <div className="business-avatar">N</div>
          <div className="business-info">
            <strong>{businessSettings.shopName}</strong>
            <span>{businessSettings.businessType}</span>
          </div>
          <ChevronDown size={16} />
        </div>

        <nav className="side-navigation">
          {navigation.map((group) => (
            <div className="nav-group" key={group.title}>
              <p className="nav-heading">{bengali ? group.bn : group.title}</p>
              {group.items.map((item) => {
                const Icon = item.icon
                return (
                  <button
                    key={item.label}
                    className={`nav-item ${activePage === item.label ? 'active' : ''}`}
                    onClick={() => { setActivePage(item.label); setMobileOpen(false) }}
                    title={item.label}
                  >
                    <Icon size={19} strokeWidth={1.8} />
                    <span>{bengali ? item.bn : item.label}</span>
                  </button>
                )
              })}
            </div>
          ))}
        </nav>

        <div className="sidebar-bottom">
          <button
            className={`nav-item ${activePage === 'Settings' ? 'active' : ''}`}
            onClick={() => {
              setActivePage('Settings')
              setMobileOpen(false)
            }}
          >
            <Settings size={19} />
            <span>{bengali ? 'সেটিংস' : 'Settings'}</span>
          </button>
          <button className="nav-item"><CircleHelp size={19} /><span>{bengali ? 'সাহায্য' : 'Help & Support'}</span></button>
          <div className="sidebar-profile">
            <div className="profile-avatar">OW</div>
            <div className="profile-info"><strong>Business Owner</strong><span>Administrator</span></div>
            <ChevronDown size={16} />
          </div>
        </div>
      </aside>

      <main className="main-area">
        <header className="topbar">
          <div className="topbar-left">
            <button className="icon-button mobile-menu" onClick={() => setMobileOpen(true)} aria-label="Open menu"><Menu /></button>
            <button className="icon-button desktop-menu" onClick={() => setCollapsed(!collapsed)} aria-label="Toggle sidebar"><Menu /></button>
            <div className="breadcrumb"><span>{bengali ? 'ব্যবসা' : 'Business'}</span><span className="crumb-separator">/</span><strong>{bengali ? pageNames[activePage] : activePage}</strong></div>
          </div>
          <div className="theme-control" ref={themeControlRef}>
            <button
              className="icon-button theme-toggle"
              onClick={() => setThemePanelOpen(!themePanelOpen)}
              title="Change website theme"
            >
              <Palette size={19} />
              <span>Theme</span>
            </button>

            {themePanelOpen && (
              <div className="theme-panel">
                <strong>Choose Theme</strong>

                <div className="theme-options">
                  {themes.map((item) => (
                    <button
                      key={item.name}
                      className={`theme-option ${theme === item.color ? 'selected' : ''}`}
                      onClick={() => {
                        setTheme(item.color)
                        setCustomColor(item.color)
                      }}
                      title={item.name}
                    >
                      <span style={{ backgroundColor: item.color }} />
                      <small>{item.name}</small>
                    </button>
                  ))}
                </div>

                <div className="custom-theme">
                  <label htmlFor="custom-theme-color">Custom Color</label>
                  <input
                    id="custom-theme-color"
                    type="color"
                    value={customColor}
                    onChange={(event) => {
                      setCustomColor(event.target.value)
                      setTheme(event.target.value)
                    }}
                  />
                </div>
              </div>
            )}
          </div>
          <div className="topbar-actions">
            <div className="search-box"><Search size={17} /><input placeholder={bengali ? 'খুঁজুন...' : 'Search anything...'} /></div>
            <button className="icon-button language-button" onClick={() => setLanguage(bengali ? 'en' : 'bn')} title="Change language"><Languages size={19} /><span>{bengali ? 'EN' : 'বাংলা'}</span></button>
            <button className="icon-button notification-button" aria-label="Notifications"><Bell size={19} /><i /></button>
            <div className="topbar-avatar">OW</div>
            <button
              className="icon-button"
              onClick={handleLogout}
              title="Logout"
              aria-label="Logout"
            >
              <LogOut size={19} />
            </button>
          </div>
        </header>

        <div className={`page-content ${activePage === 'Settings' ? 'settings-page-active' : ''}`}>
          <section className="welcome-row">
            <div>
              <div className="eyebrow">{bengali ? 'আপনার ব্যবসার এক নজরে চিত্র' : 'YOUR BUSINESS AT A GLANCE'}</div>
              <h1>{bengali ? `স্বাগতম, Business Owner!` : 'Welcome back, Business Owner!'} <span>👋</span></h1>
              <p>{bengali ? 'আজ আপনার ব্যবসার কার্যক্রমের সারসংক্ষেপ এখানে দেখুন।' : "Here's what's happening with your business today."}</p>
            </div>
            <div className="welcome-actions">
              <button className="outline-button"><CalendarDays size={17} /> 19 Nov 2026 <ChevronDown size={15} /></button>
              <button className="primary-button" onClick={() => {
                setActivePage('Sales & POS')
                setIsCreatingSale(true)
              }}><Plus size={18} /> {bengali ? 'নতুন বিক্রয়' : 'New Sale'}</button>
            </div>
          </section>
          {activePage !== 'Dashboard' &&
            activePage !== 'Sales & POS' &&
            activePage !== 'Inventory' && (
              <div className="page-notice">
                <strong>{bengali ? pageNames[activePage] : activePage}</strong>
                <span>
                  {bengali
                    ? 'এই মডিউলের UI এবং API পরবর্তী ধাপে তৈরি হবে।'
                    : 'This module UI and API will be developed in the upcoming steps.'}
                </span>
              </div>
            )}

          {activePage === 'Inventory' && !isCreatingOpeningStock && (
            <section className="panel transactions-panel">
              <div className="panel-header">
                <div>
                  <h2>{bengali ? 'ইনভেন্টরি ব্যবস্থাপনা' : 'Inventory Management'}</h2>
                  <p>
                    {bengali
                      ? 'প্রাথমিক স্টক তৈরি ও পরিচালনা করুন'
                      : 'Create and manage your opening stock'}
                  </p>
                </div>
                <button
                  className="primary-button"
                  onClick={() => setIsCreatingOpeningStock(true)}
                >
                  <Plus size={18} />
                  {bengali ? 'প্রাথমিক স্টক যোগ করুন' : 'Add Opening Stock'}
                </button>
              </div>
            </section>
          )}

          {activePage === 'Inventory' && isCreatingOpeningStock && (
            <OpeningStock
              onCancel={() => setIsCreatingOpeningStock(false)}
              onCompleted={() => setIsCreatingOpeningStock(false)}
            />
          )}

          {activePage === 'Sales & POS' && !isCreatingSale && !selectedSaleId && (
            <section className="panel transactions-panel">
              <div className="panel-header">
                <div>
                  <h2>{bengali ? 'বিক্রয়ের তালিকা' : 'Sales List'}</h2>
                  <p>
                    {bengali
                      ? `মোট বিক্রয়: ${salesTotal}`
                      : `Total sales: ${salesTotal}`}
                  </p>
                </div>

              </div>

              {salesLoading ? (
                <p>{bengali ? 'লোড হচ্ছে...' : 'Loading sales...'}</p>
              ) : salesError ? (
                <p role="alert">{salesError}</p>
              ) : sales.length === 0 ? (
                <p>{bengali ? 'কোনো বিক্রয় পাওয়া যায়নি।' : 'No sales found.'}</p>
              ) : (
                <div className="table-wrapper">
                  <table className="transaction-table">
                    <thead>
                      <tr>
                        <th>INVOICE</th>
                        <th>CUSTOMER</th>
                        <th>DATE</th>
                        <th>AMOUNT</th>
                        <th>STATUS</th>
                        <th>PAYMENT</th>
                      </tr>
                    </thead>
                    <tbody>
                      {sales.map((sale) => (
                        <tr key={sale.id}>
                          <td className="transaction-id">
                            <button
                              type="button"
                              className="invoice-link"
                              onClick={() => setSelectedSaleId(sale.id)}
                            >
                              {sale.sale_number}
                            </button>
                          </td>
                          <td>{sale.customer_name_snapshot}</td>
                          <td className="muted-cell">{sale.sale_date}</td>
                          <td className="amount-cell">
                            ₹ {Number(sale.total_amount).toLocaleString('en-IN', {
                              minimumFractionDigits: 2,
                            })}
                          </td>
                          <td>
                            <span className={`status-badge ${sale.sale_status}`}>
                              {sale.sale_status}
                            </span>
                          </td>
                          <td>{sale.payment_status}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </section>
          )}
          {activePage === 'Sales & POS' && selectedSaleId && (
            <SaleDetails
              saleId={selectedSaleId}
              onBack={() => setSelectedSaleId(null)}
            />
          )}
          {activePage === 'Sales & POS' && isCreatingSale && (
            <NewSaleForm
              onCancel={() => setIsCreatingSale(false)}
              onCreated={() => {
                setIsCreatingSale(false)
                setSalesRefreshKey((current) => current + 1)
              }}
            />
          )}
          {activePage === 'Dashboard' && (
            <section className="stats-grid">
            {stats.map((stat) => {
              const Icon = stat.icon
              return (
                <article className="stat-card" key={stat.label}>
                  <div className="stat-top"><span>{stat.label}</span><div className={`stat-icon ${stat.color}`}><Icon size={19} /></div></div>
                  <div className="stat-value">{stat.value}</div>
                  <div className="stat-bottom"><span className="trend-positive"><TrendingUp size={14} /> {stat.change}</span><span>{stat.note}</span></div>
                </article>
              )
            })}
          </section>
        )}
        {activePage === 'Dashboard' && (
          <section className="dashboard-grid">
            <article className="panel sales-panel">
              <div className="panel-header">
                <div><h2>{bengali ? 'বিক্রয়ের পরিসংখ্যান' : 'Sales Overview'}</h2><p>{bengali ? 'বিক্রয়ের সাম্প্রতিক প্রবণতা' : 'Your sales performance over time'}</p></div>
                <button className="select-button">{bengali ? 'এই বছর' : 'This year'} <ChevronDown size={15} /></button>
              </div>
              <div className="chart-summary"><strong>₹ 4,82,650</strong><span className="trend-positive"><ArrowUpRight size={16} /> 18.6%</span><small>{bengali ? 'গত বছরের তুলনায়' : 'vs last year'}</small></div>
              <div className="chart">
                <div className="chart-y-labels"><span>₹1.0L</span><span>₹75K</span><span>₹50K</span><span>₹25K</span><span>₹0</span></div>
                <div className="chart-plot">
                  <div className="chart-gridlines"><i /><i /><i /><i /><i /></div>
                  <div className="chart-bars">{chartBars.map((height, index) => <div className="bar-column" key={index}><div className={`chart-bar ${index === 11 ? 'highlight' : ''}`} style={{ height: `${height}%` }} /></div>)}</div>
                  <div className="chart-x-labels">{['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].map(month => <span key={month}>{month}</span>)}</div>
                </div>
              </div>
            </article>

            <article className="panel stock-panel">
              <div className="panel-header"><div><h2>{bengali ? 'স্টকের অবস্থা' : 'Stock Summary'}</h2><p>{bengali ? 'বর্তমান ইনভেন্টরি' : 'Current inventory status'}</p></div><button className="more-button">•••</button></div>
              <div className="stock-total"><strong>1,248</strong><span>{bengali ? 'মোট পণ্য' : 'Total products'}</span></div>
              <div className="stock-progress"><div className="stock-good" /><div className="stock-low" /><div className="stock-out" /></div>
              <div className="stock-legend">
                <div><i className="dot green-dot" /><span>{bengali ? 'পর্যাপ্ত স্টক' : 'In stock'}</span><strong>1,082</strong></div>
                <div><i className="dot orange-dot" /><span>{bengali ? 'কম স্টক' : 'Low stock'}</span><strong>126</strong></div>
                <div><i className="dot red-dot" /><span>{bengali ? 'স্টক শেষ' : 'Out of stock'}</span><strong>40</strong></div>
              </div>
              <button className="text-link" onClick={() => setActivePage('Inventory')}>{bengali ? 'ইনভেন্টরি দেখুন' : 'View inventory'} <ArrowUpRight size={15} /></button>
            </article>
          </section>
        )}
        {activePage === 'Dashboard' && (
          <section className="panel transactions-panel">
            <div className="panel-header">
              <div><h2>{bengali ? 'সাম্প্রতিক লেনদেন' : 'Recent Transactions'}</h2><p>{bengali ? 'আপনার সর্বশেষ ব্যবসায়িক লেনদেন' : 'Your latest business transactions'}</p></div>
              <button className="text-link">{bengali ? 'সব দেখুন' : 'View all'} <ArrowUpRight size={15} /></button>
            </div>
            
          <div className="table-wrapper">
            <table className="transaction-table">
              <thead>
                <tr>
                  <th>{bengali ? 'লেনদেন আইডি' : 'TRANSACTION ID'}</th>
                  <th>{bengali ? 'নাম' : 'CUSTOMER / SUPPLIER'}</th>
                  <th>{bengali ? 'তারিখ' : 'DATE'}</th>
                  <th>{bengali ? 'পরিমাণ' : 'AMOUNT'}</th>
                  <th>{bengali ? 'অবস্থা' : 'STATUS'}</th>
                  <th>{bengali ? 'ধরন' : 'TYPE'}</th>
                </tr>
              </thead>

              <tbody>
                {transactions.map(tx => (
                  <tr key={tx.id}>
                    <td data-label={bengali ? 'লেনদেন আইডি' : 'Transaction ID'} className="transaction-id">
                      {tx.id}
                    </td>
                    <td data-label={bengali ? 'নাম' : 'Customer / Supplier'}>
                      {tx.name}
                    </td>
                    <td data-label={bengali ? 'তারিখ' : 'Date'} className="muted-cell">
                      {tx.date}
                    </td>
                    <td data-label={bengali ? 'পরিমাণ' : 'Amount'} className="amount-cell">
                      {tx.amount}
                    </td>
                    <td data-label={bengali ? 'অবস্থা' : 'Status'}>
                      <span className={`status-badge ${tx.status.toLowerCase()}`}>
                        {tx.status}
                      </span>
                    </td>
                    <td data-label={bengali ? 'ধরন' : 'Type'}>
                      <span className={`type-label ${tx.type}`}>
                        {tx.type === 'sale'
                          ? (bengali ? 'বিক্রয়' : 'Sale')
                          : (bengali ? 'ক্রয়' : 'Purchase')}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          </section>
          )}
          {activePage === 'Settings' && (
            <section className="settings-container">
              <div className="settings-heading">
                <div>
                  <div className="eyebrow">APPLICATION CONFIGURATION</div>
                  <h1>{bengali ? 'সফটওয়্যার ব্র্যান্ডিং' : 'Software Branding'}</h1>
                  <p>
                    {bengali
                      ? 'সফটওয়্যারের নাম, পরিচিতি এবং লোগো পরিবর্তন করুন।'
                      : 'Customize your software name, tagline and logo.'}
                  </p>
                </div>
              </div>

              <div className="panel branding-card">
                <div className="panel-header">
                  <div>
                    <h2>{bengali ? 'ব্র্যান্ড পরিচিতি' : 'Brand Identity'}</h2>
                    <p>{bengali ? 'এই তথ্য Sidebar-এ দেখা যাবে' : 'This information appears in the sidebar'}</p>
                  </div>
                </div>

                <div className="branding-preview">
                  <div className="brand-mark">
                    {branding.logo ? (
                      <img src={branding.logo} alt="Logo preview" className="brand-logo-image" />
                    ) : (
                      <Zap size={25} fill="currentColor" />
                    )}
                  </div>
                  <div className="brand-text">
                    <strong>{branding.softwareName || 'Business Manager'}</strong>
                    <span>{branding.tagline || 'SMART BUSINESS MANAGEMENT'}</span>
                  </div>
                </div>

                <div className="branding-fields">
                  <div className="branding-field">
                    <label htmlFor="software-name">
                      {bengali ? 'সফটওয়্যারের নাম' : 'Software Name'}
                    </label>
                    <input
                      id="software-name"
                      type="text"
                      value={branding.softwareName}
                      maxLength={40}
                      placeholder="Business Manager"
                      onChange={(event) =>
                        setBranding({ ...branding, softwareName: event.target.value })
                      }
                    />
                  </div>

                  <div className="branding-field">
                    <label htmlFor="software-tagline">
                      {bengali ? 'ট্যাগলাইন' : 'Tagline'}
                    </label>
                    <input
                      id="software-tagline"
                      type="text"
                      value={branding.tagline}
                      maxLength={70}
                      placeholder="SMART BUSINESS MANAGEMENT"
                      onChange={(event) =>
                        setBranding({ ...branding, tagline: event.target.value })
                      }
                    />
                  </div>

                  <div className="branding-field">
                    <label htmlFor="software-logo">
                      {bengali ? 'লোগো আপলোড' : 'Upload Logo'}
                    </label>
                    <input
                      id="software-logo"
                      type="file"
                      accept="image/*"
                      onChange={(event) => {
                        const file = event.target.files?.[0]
                        if (!file) return

                        if (!file.type.startsWith('image/')) {
                          alert('Please select an image file.')
                          return
                        }

                        if (file.size > 1024 * 1024) {
                          alert('Please select an image smaller than 1 MB.')
                          event.target.value = ''
                          return
                        }

                        const reader = new FileReader()
                        reader.onload = () => {
                          if (typeof reader.result === 'string') {
                            setBranding((previous) => ({
                              ...previous,
                              logo: reader.result as string,
                            }))
                          }
                        }
                        reader.readAsDataURL(file)
                      }}
                    />
                    <small>Image format: PNG, JPG, SVG. Maximum size: 1 MB.</small>
                  </div>

                  {branding.logo && (
                    <button
                      className="outline-button"
                      type="button"
                      onClick={() => setBranding({ ...branding, logo: null })}
                    >
                      {bengali ? 'লোগো সরান' : 'Remove Logo'}
                    </button>
                  )}
                </div>
                <div className="branding-actions">
                  <button
                    className="primary-button"
                    type="button"
                    onClick={() => {
                      if (!branding.softwareName.trim()) {
                        alert('Software Name is required.')
                        return
                      }

                      localStorage.setItem(
                        'nokshighor-branding',
                        JSON.stringify(branding)
                      )
                      alert('Branding settings saved successfully.')
                    }}
                  >
                    Save Changes
                  </button>

                  <button
                    className="outline-button"
                    type="button"
                    onClick={() => {
                      setBranding(defaultBranding)
                      localStorage.removeItem('nokshighor-branding')
                    }}
                  >
                    Reset to Default
                  </button>
                </div>
              </div>
            </section>
          )}
          {activePage === 'Settings' && (
            <section className="panel branding-card business-settings-card">
              <div className="panel-header">
                <div>
                  <h2>{bengali ? 'দোকান ও ব্যবসার তথ্য' : 'Business Information'}</h2>
                  <p>
                    {bengali
                      ? 'আপনার দোকানের প্রয়োজনীয় তথ্য পরিচালনা করুন'
                      : 'Manage your shop details and invoice information'}
                  </p>
                </div>
              </div>

              <div className="branding-fields">
                <div className="branding-field">
                  <label>Shop Name</label>
                  <input
                    value={businessSettings.shopName}
                    onChange={(e) =>
                      setBusinessSettings({ ...businessSettings, shopName: e.target.value })
                    }
                    placeholder="NokshiGhor"
                  />
                </div>

                <div className="branding-field">
                  <label>Business Type</label>
                  <input
                    value={businessSettings.businessType}
                    onChange={(e) =>
                      setBusinessSettings({ ...businessSettings, businessType: e.target.value })
                    }
                    placeholder="Electrical & Interior"
                  />
                </div>

                <div className="branding-field">
                  <label>Phone Number</label>
                  <input
                    type="tel"
                    value={businessSettings.phone}
                    onChange={(e) =>
                      setBusinessSettings({ ...businessSettings, phone: e.target.value })
                    }
                    placeholder="Shop contact number"
                  />
                </div>

                <div className="branding-field">
                  <label>Email Address</label>
                  <input
                    type="email"
                    value={businessSettings.email}
                    onChange={(e) =>
                      setBusinessSettings({ ...businessSettings, email: e.target.value })
                    }
                    placeholder="business@example.com"
                  />
                </div>

                <div className="branding-field">
                  <label>Shop Address</label>
                  <textarea
                    value={businessSettings.address}
                    onChange={(e) =>
                      setBusinessSettings({ ...businessSettings, address: e.target.value })
                    }
                    placeholder="Enter complete shop address"
                    rows={3}
                  />
                </div>

                <div className="branding-field">
                  <label>GSTIN</label>
                  <input
                    value={businessSettings.gstin}
                    onChange={(e) =>
                      setBusinessSettings({ ...businessSettings, gstin: e.target.value.toUpperCase() })
                    }
                    placeholder="Enter GSTIN"
                    maxLength={15}
                  />
                </div>

                <div className="branding-field">
                  <label>Invoice Footer Message</label>
                  <input
                    value={businessSettings.invoiceFooter}
                    onChange={(e) =>
                      setBusinessSettings({ ...businessSettings, invoiceFooter: e.target.value })
                    }
                    placeholder="Thank you for your business!"
                  />
                </div>
              </div>
                            <div className="branding-actions">
                <button
                  className="primary-button"
                  onClick={() => {
                    localStorage.setItem(
                      'nokshighor-business-settings',
                      JSON.stringify(businessSettings)
                    )
                    alert('Business settings saved successfully!')
                  }}
                >
                  Save Changes
                </button>

                <button
                  className="outline-button"
                  onClick={() => {
                    if (window.confirm('Reset business settings to default?')) {
                      setBusinessSettings(defaultBusinessSettings)
                    }
                  }}
                >
                  Reset to Default
                </button>
              </div>
            </section>
          )}
          <footer className="page-footer"><span>© {new Date().getFullYear()} {businessSettings.shopName}. All rights reserved.</span><span>Smart Electrical & Interior Business Management System</span></footer>
        </div>
      </main>
    </div>
  )
}

export default App
