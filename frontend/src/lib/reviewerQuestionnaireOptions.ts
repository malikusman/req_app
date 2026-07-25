/** Reviewer profile questionnaire — 9 soft sections, mirrors company onboarding UX. */

export type ReviewerFieldType =
  | 'single_select'
  | 'multi_select'
  | 'searchable_select'
  | 'text'
  | 'textarea'
  | 'photo'
  | 'experiences'
  | 'cv';

export type ReviewerQuestionnaireField = {
  id: string;
  type: ReviewerFieldType;
  label: string;
  options?: string[];
  maxSelections?: number;
  placeholder?: string;
  readOnly?: boolean;
};

export type ReviewerQuestionnaireSection = {
  id: number;
  title: string;
  shortTitle: string;
  fields: ReviewerQuestionnaireField[];
};

export const REVIEWER_INDUSTRY_OPTIONS = [
  'Retail & E-commerce',
  'Manufacturing',
  'Construction & Engineering',
  'Healthcare & Medical',
  'Real Estate',
  'Logistics & Transportation',
  'Hospitality & Food Service',
  'Professional Services',
  'Financial Services & Insurance',
  'Education',
  'IT & Software',
  'Energy & Utilities',
  'Automotive',
  'Agriculture',
  'Media & Entertainment',
  'Government & Public Sector',
  'Other',
];

export const REVIEWER_LOCATION_OPTIONS = [
  'United Arab Emirates',
  'Saudi Arabia',
  'Qatar',
  'Kuwait',
  'Bahrain',
  'Oman',
  'United States',
  'United Kingdom',
  'India',
  'Pakistan',
  'Egypt',
  'Germany',
  'Singapore',
  'Canada',
  'Other',
];

export const REVIEWER_STRENGTH_OPTIONS = [
  'Operations transformation',
  'Finance & controls',
  'Supply chain',
  'ERP rollout',
  'Change management',
  'Process mining',
  'Healthcare operations',
  'GCC markets',
  'Digital transformation',
  'Shared services',
  'Procurement',
  'Customer operations',
  'Data & analytics',
  'HR operations',
  'Legal & compliance',
  'Sales & revenue operations',
  'Marketing operations',
  'IT infrastructure',
  'Cybersecurity',
  'M&A/integration',
  'Strategic planning',
];

export const REVIEWER_QUESTIONNAIRE_SECTIONS: ReviewerQuestionnaireSection[] = [
  {
    id: 1,
    title: 'Professional Identity',
    shortTitle: 'Identity',
    fields: [
      { id: 'photo', type: 'photo', label: 'Profile photo' },
      { id: 'name', type: 'text', label: 'Name', readOnly: true },
      { id: 'email', type: 'text', label: 'Email', readOnly: true },
      {
        id: 'headline',
        type: 'text',
        label: 'Headline',
        placeholder: 'Ex-McKinsey | Operations & Supply Chain, GCC',
      },
      {
        id: 'bio',
        type: 'textarea',
        label: 'Bio',
        placeholder: 'A short professional bio (aim for ~80+ characters when you publish).',
      },
      { id: 'linkedin_url', type: 'text', label: 'LinkedIn URL', placeholder: 'https://linkedin.com/in/…' },
      { id: 'website', type: 'text', label: 'Website (optional)', placeholder: 'https://…' },
      {
        id: 'location',
        type: 'searchable_select',
        label: 'Location',
        options: REVIEWER_LOCATION_OPTIONS,
      },
    ],
  },
  {
    id: 2,
    title: 'Background Type',
    shortTitle: 'Background',
    fields: [
      {
        id: 'career_background',
        type: 'multi_select',
        label: 'Which of these best describes your professional background?',
        options: [
          'Big 4 (Deloitte, EY, KPMG, PwC)',
          'Tier-1 Strategy Consulting (McKinsey, BCG, Bain)',
          'Big Tech / FAANG',
          'Boutique Consulting Firm',
          'Corporate Operator (in-house exec/leader)',
          'Investment Banking / Private Equity',
          'Academia / Research',
          'Startup Founder / Operator',
          'Independent Consultant',
          'Government / Public Sector',
        ],
      },
      {
        id: 'seniority_level',
        type: 'single_select',
        label: "What's your current or most recent seniority level?",
        options: [
          'C-Suite/Partner',
          'VP/Director',
          'Senior Manager',
          'Manager',
          'Individual Contributor/Specialist',
          'Academic (Professor/Researcher)',
          'Founder/Owner',
        ],
      },
      {
        id: 'years_experience',
        type: 'single_select',
        label: 'Years of experience',
        options: ['<3 years', '3–7 years', '8–15 years', '16–25 years', '25+ years'],
      },
      {
        id: 'team_size_managed',
        type: 'single_select',
        label: "Largest team you've managed or advised at scale (optional)",
        options: [
          'Individual contributor / no direct reports',
          '1–10 people',
          '11–50 people',
          '51–200 people',
          '200+ people',
          'Not applicable (advisory-only role)',
        ],
      },
    ],
  },
  {
    id: 3,
    title: 'Education & Certifications',
    shortTitle: 'Education',
    fields: [
      {
        id: 'education_level',
        type: 'single_select',
        label: 'Highest level of education completed?',
        options: [
          "Bachelor's degree",
          "Master's degree (MBA/MSc/etc.)",
          'PhD/Doctorate',
          'Professional qualification (no degree track)',
          'Other',
        ],
      },
      {
        id: 'field_of_study',
        type: 'multi_select',
        label: 'Field(s) of study (optional)',
        options: [
          'Business/MBA',
          'Finance/Accounting',
          'Engineering',
          'Computer Science/AI/Data Science',
          'Operations/Supply Chain',
          'Economics',
          'Law',
          'Sciences',
          'Other',
        ],
      },
      {
        id: 'certifications',
        type: 'multi_select',
        label: 'Certifications (optional)',
        options: [
          'CPA',
          'CFA',
          'CMA',
          'PMP',
          'Six Sigma (Green/Black Belt)',
          'CISA/CISSP',
          'SHRM/HR certifications',
          'AI/ML certifications (e.g. AWS/Google/Coursera-DeepLearning.AI)',
          'None',
          'Other',
        ],
      },
    ],
  },
  {
    id: 4,
    title: 'Industry Expertise',
    shortTitle: 'Industries',
    fields: [
      {
        id: 'industries_covered',
        type: 'multi_select',
        label: 'Industries you have direct experience in',
        options: REVIEWER_INDUSTRY_OPTIONS,
      },
      {
        id: 'company_size_familiarity',
        type: 'multi_select',
        label: 'Company sizes you have primarily worked with',
        options: [
          'Startups (1–50 employees)',
          'SMEs (51–500 employees)',
          'Mid-market (500–2,000)',
          'Enterprise (2,000+)',
          'Public sector/government',
        ],
      },
      {
        id: 'regional_expertise',
        type: 'multi_select',
        label: 'Regions/markets (optional)',
        options: [
          'GCC/Middle East',
          'North America',
          'Europe',
          'South Asia',
          'Southeast Asia',
          'Africa',
          'Latin America',
          'Global/multi-region',
        ],
      },
    ],
  },
  {
    id: 5,
    title: 'Functional Expertise',
    shortTitle: 'Strengths',
    fields: [
      {
        id: 'strengths',
        type: 'multi_select',
        label: 'Core areas of expertise (up to 6)',
        maxSelections: 6,
        options: REVIEWER_STRENGTH_OPTIONS,
      },
      {
        id: 'review_focus',
        type: 'multi_select',
        label: 'Which parts of a company assessment are you best positioned to review?',
        options: [
          'Financial/accounting processes',
          'Operational efficiency',
          'Technology & systems architecture',
          'Data & document management',
          'Customer engagement & CX',
          'Organizational structure & HR',
          'AI/automation opportunity sizing',
          'Security & compliance',
          'Overall strategic recommendations',
        ],
      },
    ],
  },
  {
    id: 6,
    title: 'AI & Technology Fluency',
    shortTitle: 'AI & Tech',
    fields: [
      {
        id: 'ai_fluency_level',
        type: 'single_select',
        label: 'Familiarity with AI/automation technologies',
        options: [
          'Deep technical expertise (I build/research AI systems)',
          "Strong practitioner (I've led AI/automation initiatives)",
          'Working knowledge (I evaluate and advise on AI use cases)',
          'Business-level understanding (non-technical, strategic view)',
          'Limited — finance/ops focus primarily',
        ],
      },
      {
        id: 'ai_tools_familiarity',
        type: 'multi_select',
        label: 'Enterprise tools you are comfortable evaluating (optional)',
        options: [
          'ERP systems (SAP, Oracle, Dynamics)',
          'CRM platforms',
          'RPA/workflow automation tools',
          'Data & BI platforms',
          'AI/LLM-based tools (chatbots, copilots, RAG)',
          'Cloud infrastructure (AWS/Azure/GCP)',
          'Cybersecurity tooling',
          'None of the above',
        ],
      },
    ],
  },
  {
    id: 7,
    title: 'Engagement Preferences',
    shortTitle: 'Engagement',
    fields: [
      {
        id: 'review_capacity',
        type: 'single_select',
        label: 'How many company reviews can you take on per month?',
        options: ['1–2', '3–5', '6–10', '10+'],
      },
      {
        id: 'engagement_type',
        type: 'multi_select',
        label: 'What type of review engagement are you open to?',
        options: [
          'Async report review only',
          'Live call with company stakeholders',
          'Ongoing advisory relationship',
          'One-off assessment only',
        ],
      },
      {
        id: 'preferred_company_types',
        type: 'multi_select',
        label: 'Preferred company size/stage (optional)',
        options: ['No preference', 'Early-stage/startups', 'Established SMEs', 'Larger mid-market/enterprise'],
      },
    ],
  },
  {
    id: 8,
    title: 'Experience History',
    shortTitle: 'Experience',
    fields: [{ id: 'experiences', type: 'experiences', label: 'Roles' }],
  },
  {
    id: 9,
    title: 'CV / Resume',
    shortTitle: 'CV',
    fields: [
      {
        id: 'cv_upload',
        type: 'cv',
        label: 'Upload your CV/resume (PDF, optional)',
      },
    ],
  },
];

export type ReviewerAnswers = Record<string, string | string[] | unknown[] | boolean | undefined>;

export function computeReviewerCompletionPercent(
  answers: ReviewerAnswers,
  extras?: { hasAvatar?: boolean; hasCv?: boolean; hasExperiences?: boolean }
): number {
  const ids = REVIEWER_QUESTIONNAIRE_SECTIONS.flatMap((s) => s.fields.map((f) => f.id));
  const answered = ids.filter((id) => {
    if (id === 'photo') return Boolean(extras?.hasAvatar);
    if (id === 'cv_upload') return Boolean(extras?.hasCv) || Boolean(answers.cv_upload);
    if (id === 'experiences') {
      const rows = Array.isArray(answers.experiences) ? answers.experiences : [];
      if (rows.some((r) => {
        const h = r as { organization?: string; title?: string };
        return Boolean(h.organization?.trim() && h.title?.trim());
      }))
        return true;
      return Boolean(extras?.hasExperiences);
    }
    const v = answers[id];
    if (Array.isArray(v)) return v.length > 0;
    return Boolean(v && String(v).trim());
  }).length;
  return Math.round((answered / ids.length) * 100);
}

export function reviewerSectionTouched(sectionId: number, answers: ReviewerAnswers, extras?: {
  hasAvatar?: boolean;
  hasCv?: boolean;
  hasExperiences?: boolean;
}): boolean {
  const section = REVIEWER_QUESTIONNAIRE_SECTIONS.find((s) => s.id === sectionId);
  if (!section) return false;
  return section.fields.some((f) => {
    if (f.id === 'photo') return Boolean(extras?.hasAvatar);
    if (f.id === 'cv_upload') return Boolean(extras?.hasCv) || Boolean(answers.cv_upload);
    if (f.id === 'experiences') {
      const rows = Array.isArray(answers.experiences) ? answers.experiences : [];
      return (
        rows.some((r) => {
          const h = r as { organization?: string; title?: string };
          return Boolean(h.organization?.trim() && h.title?.trim());
        }) || Boolean(extras?.hasExperiences)
      );
    }
    const v = answers[f.id];
    if (Array.isArray(v)) return v.length > 0;
    return Boolean(v && String(v).trim());
  });
}
