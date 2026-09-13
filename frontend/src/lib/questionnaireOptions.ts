/**
 * The company onboarding questionnaire — 41 questions across 8 steps, storing 45
 * values (four are lettered sub-questions with their own key).
 *
 * There is one questionnaire. An earlier rebuild kept the old set alongside a new
 * one behind a `questionnaire_version` flag; with no live data to migrate that was
 * cost without benefit, so the approved set simply replaced it. The backend
 * authority on keys, steps and tiers is Companies::QuestionnaireConfig — the two
 * are cross-checked by a spec, so a key added here must be added there too.
 */
import { COUNTRIES } from './countries';

export type FieldType =
  | 'single_select'
  | 'multi_select'
  | 'searchable_select'
  | 'text'
  | 'textarea'
  /** Explanatory copy between questions. Stores nothing. */
  | 'static'
  /** One numeric input per option the user picked in `sourceField`. */
  | 'per_item_numeric'
  /** A multi-select where each selection can carry a short free-text detail. */
  | 'multi_select_with_detail'
  /** Pick items, then pick sub-options for each item picked. */
  | 'two_stage_matrix'
  /** Several labelled inputs that together form one answer. */
  | 'parallel_text'
  /** One searchable row per category. */
  | 'category_matrix';

/**
 * Essential is the only tier that counts toward the completion percent.
 * Recommended and Optional are worth asking but must never hold someone at 99%.
 */
export type FieldTier = 'essential' | 'recommended' | 'optional' | 'conditional';

export type OptionGroup = { label: string; options: string[] };
export type MatrixCategory = { id: string; label: string; options: string[] };

export type QuestionnaireField = {
  id: string;
  type: FieldType;
  label: string;
  helper?: string;
  tier?: FieldTier;
  options?: string[];
  groups?: OptionGroup[];
  maxSelections?: number;
  placeholder?: string;
  /** Reveals a free-text "Please specify" box when an "Other" option is chosen. */
  withOther?: boolean;
  /** Gives each selection its own short detail input. */
  withDetail?: boolean;
  detailPlaceholder?: string;
  /** per_item_numeric: the multi-select whose selections become the rows. */
  sourceField?: string;
  /** per_item_numeric: the opt-out shown beside each row. */
  unknownLabel?: string;
  /** two_stage_matrix: the sub-options offered for each chosen item. */
  channelOptions?: string[];
  stageOneLabel?: string;
  stageTwoLabel?: string;
  /** parallel_text: one input per label, answered in order. */
  subLabels?: string[];
  /** category_matrix: one searchable row per category. */
  categories?: MatrixCategory[];
  /** Shown only once `field` is answered and the answer is not one of `notOneOf`. */
  showWhen?: { field: string; notOneOf: string[] };
};

/** A group of questions shown together under one step. */
export type QuestionnaireScreen = { id: string; fields: QuestionnaireField[] };

export type QuestionnaireStep = {
  id: number;
  title: string;
  shortTitle: string;
  screens: QuestionnaireScreen[];
};

/** An answer is a scalar, a list, or — for the matrix questions — a keyed map. */
export type AnswerValue = string | string[] | Record<string, string | string[]> | undefined;
export type QuestionnaireAnswers = Record<string, AnswerValue>;

export const QUESTIONNAIRE_STEPS: QuestionnaireStep[] = [
  {
    id: 1,
    title: 'About Your Business',
    shortTitle: 'Business',
    screens: [
      {
        id: '1',
        fields: [
          {
            id: 'q01_primary_industry',
            type: 'searchable_select',
            label: "What is your company's primary industry?",
            options: [
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
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q02_business_description',
            type: 'textarea',
            label: 'Briefly describe your business. What are your main products or services, and who are your main customers?',
            helper: 'A few sentences are enough. 100–1,500 chars.',
            tier: 'essential',
          },
          {
            id: 'q03_employee_count',
            type: 'single_select',
            label: 'How many employees does your company have?',
            options: ['1–10', '11–25', '26–50', '51–100', '101–250', '251–500', '501–1,000', '1,000+'],
            tier: 'essential',
          },
          {
            id: 'q04_headquarters_country',
            type: 'searchable_select',
            label: 'Where is your company headquartered?',
            options: COUNTRIES,
            tier: 'essential',
          },
          {
            id: 'q05_customer_types',
            type: 'multi_select',
            label: 'Who does your company primarily sell to or serve?',
            options: ['Businesses', 'Consumers', 'Government / public sector', 'Other'],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q06_operating_sites',
            type: 'single_select',
            label: 'How many physical offices, branches, stores, warehouses, factories or other operating sites does your company have?',
            options: ['1', '2–5', '6–20', '21–50', '51+', 'Fully remote / no permanent operating site'],
            tier: 'essential',
          },
        ],
      },
    ],
  },
  {
    id: 2,
    title: 'Organisation & Business Processes',
    shortTitle: 'Organisation',
    screens: [
      {
        id: '2a',
        fields: [
          {
            id: 'q07_departments',
            type: 'multi_select',
            label: 'Which departments or functions exist in your organisation?',
            options: [
              'Sales',
              'Marketing',
              'Customer Service / Support',
              'Operations',
              'Finance & Accounting',
              'HR & Recruitment',
              'IT',
              'Procurement / Purchasing',
              'Legal / Compliance',
              'R&D / Product',
              'Logistics / Supply Chain',
              'Production / Manufacturing',
              'Project Management / Delivery',
              'Quality Control',
              'Executive / Administration',
              'Other',
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q08_department_headcount',
            type: 'per_item_numeric',
            label: 'Approximately how many employees work in each department?',
            helper: 'One row per department you picked above. A rough number is fine, and so is "Not sure".',
            sourceField: 'q07_departments',
            unknownLabel: 'Not sure',
            tier: 'recommended',
          },
          {
            id: 'q09_core_processes',
            type: 'multi_select',
            label: 'Which processes are important to the day-to-day running of your business?',
            groups: [
              {
                label: 'Sales & Customer',
                options: ['lead generation / sales', 'quotations / proposals', 'order processing', 'customer service'],
              },
              {
                label: 'Supply & Operations',
                options: [
                  'procurement / purchasing',
                  'supplier management',
                  'inventory / warehouse',
                  'logistics / delivery',
                  'production / manufacturing',
                  'project management / delivery',
                ],
              },
              {
                label: 'Corporate & Support',
                options: [
                  'finance / accounting',
                  'collections / payment follow-up',
                  'HR / recruitment',
                  'payroll',
                  'reporting / MI',
                  'internal approvals',
                  'compliance / quality control',
                  'document processing',
                  'scheduling',
                  'Other',
                ],
              },
            ],
            tier: 'essential',
            withOther: true,
          },
        ],
      },
      {
        id: '2b',
        fields: [
          {
            id: 'q10_process_documentation',
            type: 'single_select',
            label: "How well documented are your company's main processes?",
            options: [
              'Most major processes are formally documented',
              'Some processes are documented',
              'Documentation is limited',
              'We do not have formal process documentation',
              'Not sure',
            ],
            tier: 'essential',
          },
          {
            id: 'q10a_documentation_types',
            type: 'multi_select',
            label: 'What types of process documentation are available?',
            tier: 'conditional',
            showWhen: {
              field: 'q10_process_documentation',
              notOneOf: ['We do not have formal process documentation', 'Not sure'],
            },
            withOther: true,
            options: [
              'SOPs',
              'ISO procedures / work instructions',
              'Process maps / flowcharts',
              'Departmental procedures',
              'Policies',
              'Quality manuals',
              'Checklists',
              'Training manuals',
              'Forms / templates',
              'Compliance procedures',
              'Other',
              'Not sure',
            ],
          },
          {
            id: 'q10b_certifications',
            type: 'multi_select',
            label: 'Does your organisation hold any formal management-system certifications or process standards?',
            tier: 'optional',
            // Two differently-worded "Other" options ("Other ISO certification",
            // "Other formal certification / standard") share one sidecar key —
            // decided once here, not per-option.
            withOther: true,
            options: [
              'ISO 9001',
              'ISO 14001',
              'ISO 45001',
              'ISO 27001',
              'Other ISO certification',
              'Other formal certification / standard',
              'None',
              'Not sure',
            ],
          },
          {
            id: 'msg_process_documents',
            type: 'static',
            label:
              'You can upload procedures and process documents after onboarding. Mjadi can analyse them together with employee interviews to identify AI, automation and process-improvement opportunities.',
          },
          {
            id: 'q11_manual_process_areas',
            type: 'multi_select',
            label: 'Which areas do you believe currently involve the most manual or administrative work?',
            groups: [
              {
                label: 'Sales & Customer',
                options: ['lead generation / sales', 'quotations / proposals', 'order processing', 'customer service'],
              },
              {
                label: 'Supply & Operations',
                options: [
                  'procurement / purchasing',
                  'supplier management',
                  'inventory / warehouse',
                  'logistics / delivery',
                  'production / manufacturing',
                  'project management / delivery',
                ],
              },
              {
                label: 'Corporate & Support',
                options: [
                  'finance / accounting',
                  'collections / payment follow-up',
                  'HR / recruitment',
                  'payroll',
                  'reporting / MI',
                  'internal approvals',
                  'compliance / quality control',
                  'document processing',
                  'scheduling',
                  'Other',
                ],
              },
              { label: '', options: ['Not sure'] },
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q12_department_handoffs',
            type: 'textarea',
            label:
              'Are there any areas where one department regularly has to wait for, chase or manually exchange information with another department?',
            tier: 'optional',
            helper: 'If yes, briefly describe one or two examples.',
          },
          {
            id: 'q13_key_person_dependency',
            type: 'textarea',
            label:
              'Are there important tasks or processes that depend heavily on the knowledge of one or a few employees?',
            tier: 'optional',
            helper:
              'For example: only one employee knows how to prepare an important report, handle particular suppliers or carry out a specific procedure.',
          },
          {
            id: 'q14_approval_methods',
            type: 'multi_select',
            label: 'How are internal approvals usually handled?',
            options: [
              'Automated workflow',
              'Through ERP or another business system',
              'Email',
              'Teams / Slack / internal messaging',
              'WhatsApp or similar',
              'Paper / printed forms',
              'Verbal / in person',
              'Combination of methods',
              'Very few approvals required',
              'Not sure',
            ],
            tier: 'essential',
          },
        ],
      },
    ],
  },
  {
    id: 3,
    title: 'How Work Gets Done',
    shortTitle: 'Work',
    screens: [
      {
        id: '3a',
        fields: [
          {
            id: 'msg_time_intro',
            type: 'static',
            label:
              'Think about the organisation as a whole. Select activities that take meaningful employee time rather than things that happen only occasionally.',
          },
          {
            id: 'q15_time_consuming_work',
            type: 'multi_select',
            label: 'Which types of work currently take significant employee time?',
            groups: [
              {
                label: 'Communication & Follow-up',
                options: [
                  'reading / responding to emails or messages',
                  'following up with customers',
                  'following up with suppliers',
                  'following up internally',
                  'answering repetitive questions',
                ],
              },
              {
                label: 'Documents & Data',
                options: [
                  'searching for information',
                  'reading / reviewing documents',
                  'processing scanned documents, forms or images',
                  'working extensively in Excel',
                  'entering data',
                  'uploading / importing data',
                  'moving information between systems',
                ],
              },
              {
                label: 'Analysis & Decisions',
                options: [
                  'comparing information from different sources',
                  'checking information against rules',
                  'analysing information before deciding',
                  'monitoring orders, projects, cases or deadlines',
                ],
              },
              {
                label: 'Creating & Coordinating',
                options: [
                  'preparing reports',
                  'preparing quotations / proposals',
                  'drafting documents / correspondence',
                  'scheduling / coordinating',
                  'creating marketing or content material',
                  'updating systems after work is done',
                ],
              },
              { label: '', options: ['Other', 'Not sure'] },
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q21_high_volume_activity',
            type: 'multi_select_with_detail',
            detailPlaceholder: 'Roughly how often? e.g. 500/day',
            withDetail: true,
            label: 'Are there activities your organisation performs repeatedly or in particularly high volumes?',
            tier: 'recommended',
            withOther: true,
            options: [
              'Customer enquiries',
              'emails / messages',
              'orders',
              'quotations',
              'purchase orders',
              'supplier communications',
              'invoices',
              'payments / collections',
              'documents / forms',
              'scanned documents',
              'data entries',
              'data uploads / imports',
              'reports',
              'applications / requests / cases',
              'customer or supplier follow-ups',
              'social-media / marketing content',
              'Other',
              'None significant',
              'Not sure',
            ],
          },
        ],
      },
      {
        id: '3b',
        fields: [
          {
            id: 'msg_info_intro',
            type: 'static',
            label: 'Information comes in → Employee reviews or thinks → Action follows.',
          },
          {
            id: 'q16_information_types',
            type: 'multi_select',
            label: 'What kinds of information or documents do employees regularly work with?',
            options: [
              'Emails / messages',
              'PDFs',
              'scanned documents',
              'forms',
              'contracts',
              'invoices',
              'purchase orders',
              'quotations',
              'delivery documents',
              'spreadsheets',
              'reports',
              'customer records',
              'supplier records',
              'policies / SOPs',
              'technical documents',
              'images / photographs',
              'website or online information',
              'Other',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q17_information_processing',
            type: 'multi_select',
            label:
              'When employees receive information such as an email, document, spreadsheet or request, what do they commonly need to do with it?',
            options: [
              'Extract specific information',
              'classify or categorise it',
              'check whether information is complete',
              'verify it against rules or policies',
              'compare it with another document or source',
              'summarise it',
              'analyse it',
              'identify errors or exceptions',
              'decide who should handle it',
              'decide what action should happen next',
              'draft a response',
              'enter or update information in a system',
              'create a report or document',
              'escalate unusual cases',
              'Other',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
        ],
      },
      {
        id: '3c',
        fields: [
          {
            id: 'q18_actions_after_review',
            type: 'multi_select',
            label: 'After employees review or process information, what actions do they commonly take?',
            options: [
              'Send an email or message',
              'update ERP, CRM or another system',
              'upload a file or record',
              'create a task',
              'prepare a document',
              'request approval',
              'approve or reject something',
              'follow up',
              'schedule something',
              'notify another employee or department',
              'notify a customer or supplier',
              'escalate an exception',
              'update a spreadsheet',
              'create or update a report',
              'Other',
              'Very little / none',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q19_monitoring_activity',
            type: 'multi_select',
            label: 'What activities require employees to keep checking for changes, updates or exceptions?',
            options: [
              'Customer enquiries',
              'supplier responses',
              'orders',
              'shipments / deliveries',
              'stock levels',
              'payments / overdue accounts',
              'approvals',
              'projects',
              'deadlines',
              'service requests / tickets',
              'compliance requirements',
              'system alerts',
              'competitor or market activity',
              'website / online activity',
              'Other',
              'None that I am aware of',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q20_content_research',
            type: 'multi_select',
            label:
              'Do employees spend meaningful time on any of the following content, research or knowledge activities?',
            tier: 'recommended',
            withOther: true,
            options: [
              'Preparing presentations',
              'writing reports',
              'drafting emails or correspondence',
              'creating marketing content',
              'creating social-media content',
              'managing or scheduling social media',
              'SEO / website content optimisation',
              'market research',
              'competitor research',
              'product descriptions',
              'preparing training materials',
              'creating internal procedures or documentation',
              'analysing customer feedback',
              'researching information online',
              'translating or adapting content',
              'Other',
              'None / not significant',
              'Not sure',
            ],
          },
        ],
      },
    ],
  },
  {
    id: 4,
    title: 'Systems & Information',
    shortTitle: 'Systems',
    screens: [
      {
        id: '4a',
        fields: [
          {
            id: 'q22_business_systems',
            type: 'category_matrix',
            label: 'Which main software systems does your company use?',
            helper:
              'One line per category. Skip any that do not apply — an empty row reads as "we do not use one", which is itself useful to know.',
            tier: 'recommended',
            categories: [
              {
                id: 'erp',
                label: 'ERP / core business system',
                options: [
                  'SAP S/4HANA',
                  'SAP Business One',
                  'Oracle NetSuite',
                  'Oracle Fusion Cloud ERP',
                  'Microsoft Dynamics 365 Business Central',
                  'Microsoft Dynamics 365 Finance & Operations',
                  'Odoo',
                  'Sage 300',
                  'Sage X3',
                  'Epicor Kinetic',
                  'Infor CloudSuite',
                  'Focus ERP',
                  'TallyPrime',
                  'Zoho One',
                  'QuickBooks Enterprise',
                  'Custom / in-house system',
                ],
              },
              {
                id: 'crm',
                label: 'CRM / sales management',
                options: [
                  'Salesforce',
                  'HubSpot',
                  'Microsoft Dynamics 365 Sales',
                  'Zoho CRM',
                  'Pipedrive',
                  'Freshsales',
                  'Odoo CRM',
                  'monday CRM',
                  'Zendesk Sell',
                  'Custom / in-house system',
                  'Spreadsheets',
                ],
              },
              {
                id: 'accounting',
                label: 'Accounting / finance',
                options: [
                  'QuickBooks',
                  'Xero',
                  'Zoho Books',
                  'TallyPrime',
                  'Sage 50',
                  'Focus',
                  'Wafeq',
                  'Microsoft Dynamics 365 Finance',
                  'Oracle NetSuite',
                  'SAP',
                  'Handled by an external accountant',
                  'Spreadsheets',
                ],
              },
              {
                id: 'hr',
                label: 'HR / payroll',
                options: [
                  'BambooHR',
                  'Zoho People',
                  'SAP SuccessFactors',
                  'Oracle HCM Cloud',
                  'Workday',
                  'Darwinbox',
                  'Bayzat',
                  'GulfHR',
                  'Menaitech',
                  'Odoo HR',
                  'Paylocity',
                  'Spreadsheets',
                ],
              },
              {
                id: 'warehouse',
                label: 'Warehouse / inventory',
                options: [
                  'SAP EWM',
                  'Oracle Warehouse Management',
                  'Manhattan Associates',
                  'Microsoft Dynamics 365 SCM',
                  'Odoo Inventory',
                  'Zoho Inventory',
                  'Unleashed',
                  'Fishbowl',
                  'Infor WMS',
                  'Custom / in-house system',
                  'Spreadsheets',
                ],
              },
              {
                id: 'pos',
                label: 'POS / retail',
                options: [
                  'Square',
                  'Shopify POS',
                  'Lightspeed',
                  'Oracle MICROS',
                  'Foodics',
                  'Loyverse',
                  'Odoo POS',
                  'Zoho POS',
                  'Toast',
                  'Custom / in-house system',
                ],
              },
              {
                id: 'project',
                label: 'Project management',
                options: [
                  'Asana',
                  'monday.com',
                  'Jira',
                  'Trello',
                  'ClickUp',
                  'Microsoft Project',
                  'Smartsheet',
                  'Wrike',
                  'Notion',
                  'Primavera P6',
                  'Odoo Projects',
                  'Spreadsheets',
                ],
              },
              {
                id: 'service',
                label: 'Customer service / ticketing',
                options: [
                  'Zendesk',
                  'Freshdesk',
                  'Salesforce Service Cloud',
                  'HubSpot Service Hub',
                  'Intercom',
                  'Zoho Desk',
                  'Jira Service Management',
                  'LiveChat',
                  'WhatsApp Business',
                  'A shared email inbox',
                ],
              },
              {
                id: 'production',
                label: 'Production / manufacturing',
                options: [
                  'SAP PP',
                  'Oracle Manufacturing',
                  'Odoo Manufacturing',
                  'Katana',
                  'MRPeasy',
                  'Epicor Kinetic',
                  'Infor CloudSuite Industrial',
                  'Plex',
                  'Custom / in-house system',
                  'Spreadsheets',
                ],
              },
              {
                id: 'documents',
                label: 'Document management',
                options: [
                  'Microsoft SharePoint',
                  'Google Drive',
                  'Dropbox Business',
                  'Box',
                  'M-Files',
                  'DocuWare',
                  'Laserfiche',
                  'OpenText',
                  'Zoho WorkDrive',
                  'A network shared drive',
                  'Mostly physical files',
                ],
              },
              {
                id: 'bi',
                label: 'Reporting / business intelligence',
                options: [
                  'Microsoft Power BI',
                  'Tableau',
                  'Looker Studio',
                  'Qlik',
                  'Zoho Analytics',
                  'SAP Analytics Cloud',
                  'Oracle Analytics Cloud',
                  'Microsoft Excel',
                  'Google Sheets',
                  'Custom / in-house dashboards',
                ],
              },
              {
                id: 'other',
                label: 'Other important systems',
                options: [
                  'Design / engineering (AutoCAD, SolidWorks…)',
                  'Fleet or logistics tracking',
                  'Quality management',
                  'Maintenance (CMMS)',
                  'Learning management',
                  'Marketing automation',
                  'E-commerce platform',
                  'Booking / scheduling',
                ],
              },
            ],
          },
          {
            id: 'q23_productivity_tools',
            type: 'multi_select',
            label: 'Which of these tools are regularly used by employees?',
            options: [
              'Microsoft 365',
              'Outlook',
              'Excel',
              'Microsoft Teams',
              'SharePoint / OneDrive',
              'Google Workspace',
              'Gmail',
              'Google Drive',
              'Slack',
              'WhatsApp',
              'Zoom',
              'Other',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
        ],
      },
      {
        id: '4b',
        fields: [
          {
            id: 'q24_system_connection',
            type: 'single_select',
            label: 'How well are your main business systems connected?',
            options: [
              'Most systems exchange information automatically',
              'Some systems are integrated while others are separate',
              'Most systems operate separately',
              'Employees frequently copy or re-enter information between systems',
              'Not sure',
            ],
            tier: 'essential',
          },
          {
            id: 'q25_manual_data_movement',
            type: 'multi_select',
            label: 'Where do employees manually copy, move, upload or re-enter information?',
            tier: 'recommended',
            withOther: true,
            options: [
              'From emails into business systems',
              'from Excel into business systems',
              'between CRM and ERP',
              'from business systems into Excel',
              'from websites or online forms into internal systems',
              'from customer portals into internal systems',
              'from supplier portals into internal systems',
              'between internal systems',
              'from paper or scanned documents into systems',
              'Other',
              'Very little / none',
              'Not sure',
            ],
          },
          {
            id: 'q25a_manual_movement_example',
            type: 'text',
            label: 'Briefly describe an important example, if useful.',
            tier: 'optional',
          },
          {
            id: 'q26_information_storage',
            type: 'multi_select',
            label: 'Where is company information mainly stored?',
            options: [
              'ERP / CRM / other business systems',
              'SharePoint / OneDrive',
              'Google Drive',
              'other cloud storage',
              'on-premise servers',
              'employee computers',
              'email inboxes',
              'spreadsheets',
              'physical / paper files',
              'Other',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q27_information_findability',
            type: 'single_select',
            label: 'How easy is it for employees to find the information they need to do their jobs?',
            options: [
              'Very easy — centralised and searchable',
              'Generally easy',
              'Sometimes difficult',
              'Difficult — spread across systems or people',
              'Very difficult — depends on specific employees',
              'Not sure',
            ],
            tier: 'essential',
          },
          {
            id: 'q28_reporting_method',
            type: 'multi_select',
            label: 'How are management or operational reports typically prepared?',
            tier: 'recommended',
            withOther: true,
            options: [
              'Mostly automated dashboards',
              'generated automatically from business systems',
              'generated from systems but manually reviewed or reformatted',
              'mainly prepared in Excel',
              'manually collected from several systems',
              'manually collected from several departments',
              'prepared when requested',
              'require significant written analysis or commentary',
              'Other',
              'Not sure',
            ],
          },
        ],
      },
    ],
  },
  {
    id: 5,
    title: 'External Business Activity',
    shortTitle: 'External',
    screens: [
      {
        id: '5',
        fields: [
          {
            id: 'q29_external_parties_channels',
            type: 'two_stage_matrix',
            label:
              'Which external parties does your organisation regularly interact with, and how do you usually communicate or exchange information with them?',
            helper:
              'Pick the parties you deal with, then say how you reach each one. Most companies reach different parties in different ways — that difference is the useful part.',
            stageOneLabel: 'Which parties do you deal with regularly?',
            stageTwoLabel: 'How do you reach each one?',
            options: [
              'customers / clients',
              'suppliers / vendors',
              'distributors / dealers',
              'contractors / subcontractors',
              'logistics / freight providers',
              'banks / financial institutions',
              'government / regulatory bodies',
              'professional advisers',
              'business partners',
              'Other',
            ],
            channelOptions: [
              'email',
              'phone',
              'WhatsApp',
              'website / online forms',
              'customer or supplier portals',
              'direct system integration / EDI',
              'shared files / cloud folders',
              'mobile apps',
              'social media',
              'in person',
              'paper documents',
              'Other',
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q30_external_manual_work',
            type: 'multi_select',
            label:
              'Which activities involving external parties require significant manual work or repeated follow-up?',
            options: [
              'Responding to enquiries',
              'preparing quotations / proposals',
              'processing customer orders',
              'requesting supplier quotations',
              'comparing supplier offers',
              'creating purchase orders',
              'customer follow-up',
              'supplier follow-up',
              'shipment / delivery follow-up',
              'document exchange',
              'updating customer or supplier portals',
              'processing invoices or statements',
              'collecting information from external parties',
              'updating internal systems',
              'scheduling meetings / appointments',
              'resolving issues or exceptions',
              'Other',
              'Very little / none',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
        ],
      },
    ],
  },
  {
    id: 6,
    title: 'Challenges & Priorities',
    shortTitle: 'Challenges',
    screens: [
      {
        id: '6',
        fields: [
          {
            id: 'q33_top_improvements',
            type: 'parallel_text',
            label: 'If you could significantly improve three things about how work gets done in your company, what would they be?',
            helper: 'Whatever comes to mind first is usually the most telling — no need to deliberate.',
            subLabels: ['First priority', 'Second priority', 'Third priority'],
            tier: 'essential',
          },
          {
            id: 'q31_operational_challenges',
            type: 'multi_select',
            label: 'What are the biggest operational challenges in your organisation today?',
            options: [
              'Too much manual or repetitive work',
              'high employee workload',
              'too much time spent on administration',
              'slow customer or external-party response',
              'slow supplier / procurement processes',
              'disconnected systems',
              'duplicate data entry',
              'slow approvals',
              'difficulty finding information',
              'dependence on particular employees',
              'errors caused by manual work',
              'slow reporting',
              'lack of management visibility / KPIs',
              'too many emails or messages',
              'difficult coordination between departments',
              'difficult coordination with external parties',
              'inventory / stock visibility problems',
              'difficulty scaling',
              'high operating cost',
              'Other',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q32_error_delay_areas',
            type: 'multi_select',
            label: 'Where do errors, delays or inconsistencies occur most often?',
            tier: 'recommended',
            withOther: true,
            options: [
              'Sales / quotations',
              'customer orders',
              'procurement / purchasing',
              'supplier management',
              'inventory / warehouse',
              'logistics / delivery',
              'production / operations',
              'finance / invoicing',
              'HR / payroll',
              'reporting',
              'data entry',
              'scheduling',
              'approvals',
              'documents',
              'communication between departments',
              'communication with external parties',
              'Other',
              'No significant recurring issues',
              'Not sure',
            ],
          },
          {
            id: 'q34_active_projects',
            type: 'textarea',
            label:
              'Are there any major system, digital transformation, automation or AI projects already underway that Mjadi should know about?',
            tier: 'optional',
            helper: 'Examples: ERP implementation, CRM replacement, Power BI, Power Automate, document automation, chatbot, custom AI.',
          },
        ],
      },
    ],
  },
  {
    id: 7,
    title: 'AI, Automation & Employee Readiness',
    shortTitle: 'AI & Readiness',
    screens: [
      {
        id: '7',
        fields: [
          {
            id: 'q35_current_ai_automation',
            type: 'multi_select',
            label: 'Which AI or automation capabilities does your organisation currently use?',
            groups: [
              {
                label: 'Automation',
                options: [
                  'built into ERP / CRM / other existing systems',
                  'Microsoft Power Automate',
                  'Zapier',
                  'Make',
                  'UiPath',
                  'Automation Anywhere',
                  'custom scripts or applications',
                  'other workflow / process automation',
                ],
              },
              {
                label: 'AI',
                options: [
                  'ChatGPT / Claude / similar',
                  'Microsoft Copilot',
                  'Google Gemini / Workspace AI',
                  'AI features built into existing software',
                  'chatbots / conversational AI',
                  'tools that read, extract or check documents',
                  'AI for reporting / analytics',
                  'AI for marketing / content',
                  'AI used within automated workflows',
                  'custom-built AI applications',
                  'AI agents that carry out multi-step tasks',
                ],
              },
              { label: 'Other', options: ['we currently use none of these', 'Other', 'Not sure'] },
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q36_adoption_readiness',
            type: 'single_select',
            label: 'How ready is your organisation to introduce new technology, automation or AI solutions?',
            options: [
              'Very ready — actively looking to implement',
              'Ready if there is a clear business case',
              'Interested, but would prefer to test or pilot first',
              'Cautious about major changes',
              'Not currently ready',
              'Not sure',
            ],
            tier: 'essential',
          },
          {
            id: 'q37_ai_employee_capability',
            type: 'single_select',
            label: "How would you describe employees' current ability to use AI and modern productivity tools effectively?",
            options: [
              'Strong — many employees already use them effectively',
              'Mixed — some capable, others need support',
              'Basic — usage is limited',
              'Very limited — most employees have little experience',
              'We have not assessed this',
              'Not sure',
            ],
            tier: 'essential',
          },
          {
            id: 'q37a_ai_training',
            type: 'multi_select',
            label: 'What AI guidance or training does your organisation currently provide?',
            tier: 'recommended',
            options: [
              'Formal AI policy / acceptable-use guidance',
              'general AI-awareness training',
              'role-specific AI training',
              'Copilot / productivity-AI training',
              'other formal AI training',
              'informal guidance only',
              'no formal guidance or training',
              'Not sure',
            ],
          },
          {
            id: 'q38_failed_ai_projects',
            type: 'textarea',
            label: 'Has your organisation previously tried an AI or automation solution that did not work as expected?',
            tier: 'optional',
            helper: 'If yes, briefly explain what was attempted and what happened.',
          },
        ],
      },
    ],
  },
  {
    id: 8,
    title: 'Governance & What You Want to Achieve',
    shortTitle: 'Governance',
    screens: [
      {
        id: '8',
        fields: [
          {
            id: 'q39_restrictions',
            type: 'multi_select',
            label: 'Are you aware of any privacy, security, regulatory or data restrictions that Mjadi should consider?',
            options: [
              'GDPR',
              'healthcare / patient-data requirements',
              'financial-services regulations',
              'government / confidential-information requirements',
              'local data-residency requirements',
              'ISO 27001 or similar',
              'internal restrictions on cloud systems',
              'internal restrictions on AI',
              'Other',
              'None known',
              'Not sure',
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q40_desired_outcomes',
            type: 'multi_select',
            label: 'What would you most like Mjadi to help your organisation achieve?',
            groups: [
              {
                label: 'Find Opportunities',
                options: [
                  'identify work where AI could assist employees',
                  'identify work AI agents could partially perform',
                  'identify work AI agents could substantially or fully perform with appropriate controls',
                  'reduce repetitive or administrative work',
                  'automate multi-step processes',
                  'improve employee decision support',
                  'make better use of AI already in existing software',
                  'identify opportunities using Microsoft 365 / Copilot or similar',
                  'identify where employee AI training could improve productivity',
                ],
              },
              {
                label: 'Improve the Business',
                options: [
                  'reduce operating costs',
                  'save employee time',
                  'increase productivity',
                  'reduce errors',
                  'improve customer service',
                  'improve supplier / external-party interaction',
                  'improve response times',
                  'improve access to company knowledge',
                  'improve reporting and management visibility',
                  'improve decision-making',
                  'scale without increasing headcount at the same rate',
                  'improve employee experience',
                  'Other',
                ],
              },
            ],
            tier: 'essential',
            withOther: true,
          },
          {
            id: 'q41_specific_investigation',
            type: 'textarea',
            label: 'Is there anything specific you would like Mjadi to investigate during this assessment?',
            tier: 'optional',
            helper:
              'Examples: quotation preparation, supplier follow-up, scanned-document checking, Excel-heavy work, management reporting, marketing activities.',
          },
        ],
      },
    ],
  },
];
export const QUESTIONNAIRE_SECTIONS = QUESTIONNAIRE_STEPS;
export const STEP_COUNT = QUESTIONNAIRE_STEPS.length;

/** The free-text companion for an "Other" choice. */
export const otherKey = (fieldId: string) => `${fieldId}_other`;
/** The per-selection detail companion. */
export const detailKey = (fieldId: string) => `${fieldId}_detail`;

export function allFields(): QuestionnaireField[] {
  return QUESTIONNAIRE_STEPS.flatMap((step) => step.screens.flatMap((screen) => screen.fields));
}

export function fieldIsVisible(field: QuestionnaireField, answers: QuestionnaireAnswers): boolean {
  if (!field.showWhen) return true;
  const current = answers[field.showWhen.field];
  const value = Array.isArray(current) ? current[0] : current;
  if (!value || typeof value !== 'string') return false;
  return !field.showWhen.notOneOf.includes(value);
}

export function isAnswered(value: AnswerValue): boolean {
  if (value == null) return false;
  if (Array.isArray(value)) return value.some((v) => String(v).trim() !== '');
  if (typeof value === 'object') {
    // A matrix row the user opened and left empty is not an answer.
    return Object.values(value).some((v) =>
      Array.isArray(v) ? v.some((x) => String(x).trim() !== '') : String(v ?? '').trim() !== ''
    );
  }
  return String(value).trim() !== '';
}

/**
 * Essential questions only, and only those currently visible — a conditional
 * question that does not apply must not keep the bar below 100.
 */
export function computeCompletionPercent(answers: QuestionnaireAnswers): number {
  const counted = allFields().filter(
    (f) => f.tier === 'essential' && f.type !== 'static' && fieldIsVisible(f, answers)
  );
  if (counted.length === 0) return 0;
  const answered = counted.filter((f) => isAnswered(answers[f.id])).length;
  return Math.round((answered / counted.length) * 100);
}

export function stepTouched(stepId: number, answers: QuestionnaireAnswers): boolean {
  const step = QUESTIONNAIRE_STEPS.find((s) => s.id === stepId);
  if (!step) return false;
  return step.screens
    .flatMap((screen) => screen.fields)
    .some((f) => f.type !== 'static' && fieldIsVisible(f, answers) && isAnswered(answers[f.id]));
}

/** True when every visible Essential question in the step has an answer. */
export function stepComplete(stepId: number, answers: QuestionnaireAnswers): boolean {
  const step = QUESTIONNAIRE_STEPS.find((s) => s.id === stepId);
  if (!step) return false;
  const required = step.screens
    .flatMap((screen) => screen.fields)
    .filter((f) => f.tier === 'essential' && fieldIsVisible(f, answers));
  return required.length > 0 && required.every((f) => isAnswered(answers[f.id]));
}
