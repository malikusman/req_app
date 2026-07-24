/** Shared firmographic options for signup, onboarding, and settings. */

export const INDUSTRY_OPTIONS = [
  { value: 'logistics', label: 'Logistics & freight' },
  { value: 'manufacturing', label: 'Manufacturing' },
  { value: 'professional_services', label: 'Professional services' },
  { value: 'finance', label: 'Finance' },
  { value: 'healthcare', label: 'Healthcare' },
  { value: 'retail', label: 'Retail' },
  { value: 'technology', label: 'Technology' },
  { value: 'other', label: 'Other' },
] as const;

export const SIZE_BAND_OPTIONS = [
  { value: '1-10', label: '1–10' },
  { value: '11-50', label: '11–50' },
  { value: '51-200', label: '51–200' },
  { value: '201-1000', label: '201–1,000' },
  { value: '1000+', label: '1,000+' },
] as const;

export const REGION_OPTIONS = [
  { value: 'Middle East', label: 'Middle East' },
  { value: 'Gulf Cooperation Council (GCC)', label: 'Gulf Cooperation Council (GCC)' },
  { value: 'Europe', label: 'Europe' },
  { value: 'North America', label: 'North America' },
  { value: 'Asia Pacific', label: 'Asia Pacific' },
  { value: 'Latin America', label: 'Latin America' },
  { value: 'Africa', label: 'Africa' },
  { value: 'Other', label: 'Other' },
] as const;

export const REVENUE_BAND_OPTIONS = [
  { value: '', label: 'Prefer not to say' },
  { value: 'under_1m', label: 'Under $1M' },
  { value: '1m_10m', label: '$1M–$10M' },
  { value: '10m_50m', label: '$10M–$50M' },
  { value: '50m_250m', label: '$50M–$250M' },
  { value: '250m_plus', label: '$250M+' },
] as const;

export const DEPARTMENT_OPTIONS = [
  'Finance',
  'Operations',
  'HR',
  'IT',
  'Sales',
  'Procurement',
  'Warehouse',
  'Customer success',
] as const;

export const BUSINESS_GOAL_OPTIONS = [
  { value: 'cut_cycle_time', label: 'Cut cycle time' },
  { value: 'reduce_manual_work', label: 'Reduce manual work' },
  { value: 'audit_readiness', label: 'Audit readiness' },
  { value: 'scale_ops', label: 'Scale operations' },
  { value: 'cost_visibility', label: 'Cost visibility' },
  { value: 'other', label: 'Other' },
] as const;

export const ENGAGEMENT_MODE_OPTIONS = [
  { value: 'hybrid', label: 'Documents + employees (recommended)' },
  { value: 'documents', label: 'Documents only for now' },
  { value: 'interview', label: 'Employee interviews focus' },
] as const;

export function toggleMulti(values: string[], value: string): string[] {
  return values.includes(value) ? values.filter((v) => v !== value) : [...values, value];
}
