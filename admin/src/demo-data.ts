import type { AudienceData, DailyWellbeing } from "./Audience";
import type { StatisticsData } from "./Statistics";
// Entirely fictional presentation fixtures. No account/database data is loaded.
const asOf = "2026-10-15T12:00:00Z";
export const demoStatistics: StatisticsData = {
  total: 2400,
  new_today: 38,
  new_7d: 242,
  new_30d: 780,
  verified: 2160,
  unverified: 240,
  onboarded: 1920,
  incomplete: 480,
  signed_in_7d: 1640,
  signed_in_30d: 2080,
  marital: { married: 1100, not_married: 940, unknown: 360 },
  age: {
    under_18: 120,
    "18_24": 760,
    "25_34": 900,
    "35_44": 400,
    "45_plus": 100,
    unknown: 120,
  },
  language: { ar: 2100, en: 240, unknown: 60 },
};
const trend: DailyWellbeing[] = Array.from({ length: 30 }, (_, i) => ({
  day: new Date(Date.UTC(2026, 8, 16 + i)).toISOString().slice(0, 10),
  reports: 620 + i * 10,
  happy: 280 + i * 4,
  down: 110 + i,
  neutral: 230 + i * 5,
  low_energy: 160 + i,
  poor_sleep: 130 + i,
  sleepy: 190 + i * 2,
  sleepy_reports: 440 + i * 7,
  mood_reports: 620 + i * 10,
  mood_avg: Math.round((3.3 + Math.sin(i / 4) * 0.25 + i * 0.008) * 100) / 100,
  energy_avg:
    Math.round((3.05 + Math.cos(i / 5) * 0.2 + i * 0.006) * 100) / 100,
  sleep_avg: Math.round((3.2 + Math.sin(i / 6) * 0.3) * 100) / 100,
}));
const distribution = {
  rows: [
    { score: 1, users: 50 },
    { score: 2, users: 89 },
    { score: 3, users: 375 },
    { score: 4, users: 260 },
    { score: 5, users: 136 },
  ],
  unknown: 0,
};
export const demoAudience: AudienceData = {
  as_of: asOf,
  date: "2026-10-15",
  total: 2400,
  countries: {
    rows: [
      { country: "SA", users: 1480 },
      { country: "AE", users: 220 },
      { country: "EG", users: 180 },
      { country: "KW", users: 110 },
      { country: "GB", users: 70 },
      { country: "QA", users: 60 },
    ],
    other: 100,
    unknown: 180,
  },
  madhhab: {
    hanafi: 280,
    maliki: 220,
    shafii: 420,
    hanbali: 1020,
    unknown: 300,
    unset: 160,
  },
  cycle: {
    fresh: 1800,
    missing: 600,
    bleeding: 440,
    no_bleeding: 1120,
    bleeding_unknown: 840,
    haid: 350,
    tahara: 1120,
    needs_advisory: 60,
    madhhab_unresolved: 30,
    unknown: 840,
    ovulation: 98,
    pre_period: 270,
    prediction_coverage: 1280,
  },
  today: trend[29],
  wellbeing_users_7d: 1550,
  wellbeing_users_30d: 1940,
  trend,
  checkin_details: {
    ratings: {
      mood: distribution,
      energy: {
        rows: [
          { score: 1, users: 65 },
          { score: 2, users: 124 },
          { score: 3, users: 340 },
          { score: 4, users: 260 },
          { score: 5, users: 121 },
        ],
        unknown: 0,
      },
      sleep: {
        rows: [
          { score: 1, users: 45 },
          { score: 2, users: 114 },
          { score: 3, users: 360 },
          { score: 4, users: 280 },
          { score: 5, users: 111 },
        ],
        unknown: 0,
      },
    },
    with_notes: 240,
    without_notes: 670,
  },
};
const alerts = [
  {
    key: "support_backlog",
    title: "طلبات دعم تحتاج متابعة — مثال تجريبي",
    count: 8,
    severity: "normal",
    section: "support",
  },
];
export const demoOperations = {
  as_of: asOf,
  alerts,
  open_incidents: 2,
  overdue_incidents: 1,
  assignees: [{ user_id: "demo-operator", email: "operations@niswah.invalid" }],
  incidents: [
    {
      id: "demo-incident-1",
      title: "مراجعة طلبات الدعم التجريبية",
      source: "support_backlog",
      status: "open",
      assigned_to: "demo-operator",
      assignee_email: "operations@niswah.invalid",
      due_at: "2026-10-14T20:59:59Z",
    },
    {
      id: "demo-incident-2",
      title: "متابعة تجربة التهيئة — مثال",
      source: "manual",
      status: "acknowledged",
      assigned_to: null,
      assignee_email: null,
      due_at: "2099-10-20T20:59:59Z",
    },
  ],
  funnel: {
    state: "receiving",
    since: "2026-09-16T00:00:00Z",
    steps: [
      "started",
      "madhhab",
      "marital",
      "location",
      "last_period",
      "period_length",
      "privacy",
      "welcome",
      "completed",
    ].map((step, i) => ({
      step,
      reached: [2400, 2320, 2210, 2120, 2090, 2050, 2000, 1950, 1920][i],
    })),
  },
  ai: [
    "ai-assistant-chat",
    "dr-niswah-chat",
    "fiqh-advisor-chat",
    "dream-interpreter-chat",
  ].map((advisor, i) => ({
    advisor,
    state: "receiving",
    last_seen_at: asOf,
    requests: 1200 - i * 200,
    server_errors: 3,
    rate_limited: 6,
    rejected: 4,
    p95_ms: 2400 + i * 300,
    model_calls: 1180 - i * 200,
    model_failures: 2,
    input_tokens: 95000 - i * 12000,
    output_tokens: 42000 - i * 5000,
    usage_missing: 0,
  })),
};
export const demoRecords: Record<string, Record<string, unknown>[]> = {
  users: [
    {
      id: "demo-user-1",
      email: "member-one@niswah.invalid",
      verified: true,
      onboarding_completed: true,
      created_at: "2026-10-13T08:00:00Z",
      last_sign_in_at: asOf,
    },
    {
      id: "demo-user-2",
      email: "member-two@niswah.invalid",
      verified: false,
      onboarding_completed: false,
      created_at: "2026-10-15T08:00:00Z",
      last_sign_in_at: null,
    },
  ],
  support: [
    {
      id: "demo-ticket-1",
      user_id: "demo-user-1",
      subject: "مثال: استفسار عن إعدادات التطبيق",
      priority: "high",
      status: "open",
      created_at: asOf,
    },
    {
      id: "demo-ticket-2",
      user_id: "demo-user-2",
      subject: "مثال: متابعة تأكيد الحساب",
      priority: "normal",
      status: "in_progress",
      created_at: asOf,
    },
  ],
  community: [
    {
      id: "demo-post-1",
      title: "مثال تجريبي: مشاركة تجربة تنظيم اليوم",
      content: "هذا نص تجريبي لعرض شاشة مراجعة المجتمع فقط.",
      category: "general",
      is_anonymous: true,
      is_hidden: false,
      created_at: asOf,
    },
    {
      id: "demo-post-2",
      title: "مثال تجريبي: محتوى قيد المراجعة",
      content: "هذا مثال مخفي لعرض حالة الإشراف.",
      category: "general",
      is_anonymous: false,
      is_hidden: true,
      created_at: asOf,
    },
  ],
  comments: [
    {
      id: "demo-comment-1",
      content: "تعليق تجريبي لعرض واجهة المراجعة.",
      is_anonymous: true,
      is_hidden: false,
      created_at: asOf,
    },
  ],
  content: [
    {
      id: "demo-draft-1",
      title: "مثال: دليل البدء مع نسوة",
      body: "مسودة تجريبية فقط، وليست محتوى منشوراً أو إرشاداً صحياً معتمداً.",
      domain: "NISWAH_PRODUCT",
      language: "ar",
      created_at: asOf,
    },
    {
      id: "demo-draft-2",
      title: "Example: Welcome to Niswah",
      body: "Fictional editorial draft for the dashboard preview.",
      domain: "NISWAH_PRODUCT",
      language: "en",
      created_at: asOf,
    },
  ],
  knowledge: [
    {
      id: "demo-knowledge-1",
      knowledge_key: "DEMO-PRODUCT-001",
      topic: "مثال لواجهة عرض الأدلة",
      domain: "NISWAH_PRODUCT",
      madhhab: null,
      version: 1,
      language: "ar",
      publication_state: "DRAFT",
      canonical_statement:
        "نص تجريبي لشرح واجهة مراجعة المعرفة؛ ليس حكماً أو نصيحة طبية.",
      qualification_note: "بيانات وهمية للمعاينة فقط.",
      sources: [
        {
          title: "مرجع تجريبي لواجهة العرض",
          locator: "موضع مرجعي تجريبي",
          reference: "DEMO-REFERENCE",
        },
      ],
      reviews: [],
    },
    {
      id: "demo-knowledge-2",
      knowledge_key: "DEMO-REVIEW-002",
      topic: "مثال لقرار مراجعة غير منشور",
      domain: "FIQH",
      madhhab: "HANBALI",
      version: 2,
      language: "ar",
      publication_state: "DRAFT",
      canonical_statement: "مثال واجهة فقط؛ لا يحتوي على فتوى.",
      sources: [],
      reviews: [
        {
          decision: "changes_requested",
          note: "قرار تجريبي: يحتاج استكمال المراجعة.",
          created_at: asOf,
        },
      ],
    },
  ],
  staff: [
    {
      user_id: "demo-owner",
      email: "owner@niswah.invalid",
      role: "owner",
      active: true,
      created_at: asOf,
    },
    {
      user_id: "demo-operator",
      email: "operations@niswah.invalid",
      role: "operator",
      active: true,
      created_at: asOf,
    },
    {
      user_id: "demo-editor",
      email: "editor@niswah.invalid",
      role: "editor",
      active: false,
      created_at: asOf,
    },
  ],
  audit: [
    {
      id: "demo-audit-1",
      action: "read.analytics",
      actor_id: "demo-owner",
      target_id: null,
      details: { demo: true },
      created_at: asOf,
    },
    {
      id: "demo-audit-2",
      action: "create_draft",
      actor_id: "demo-editor",
      target_id: "demo-draft-1",
      details: { demo: true },
      created_at: asOf,
    },
  ],
};
export function demoResponse(input: Record<string, unknown>) {
  switch (input.section) {
    case "overview":
      return {
        data: {
          as_of: asOf,
          users: 2400,
          new_users_7d: 242,
          onboarded: 1920,
          open_tickets: 12,
          posts: 380,
          knowledge_versions: 180,
          review_decisions: 74,
          statistics: demoStatistics,
          attention: { alerts, open_incidents: 2, overdue_incidents: 1 },
          signups: Array.from({ length: 14 }, (_, i) => ({
            day: new Date(Date.UTC(2026, 9, 2 + i)).toISOString().slice(0, 10),
            count: 20 + ((i * 13) % 29),
          })),
        },
      };
    case "analytics":
      return { data: demoAudience };
    case "operations":
      return { data: demoOperations };
    default: {
      const key =
        input.section === "community" && input.kind === "comment"
          ? "comments"
          : String(input.section);
      const query = String(input.query || "")
        .trim()
        .toLocaleLowerCase();
      const rows = (demoRecords[key] || []).filter(
        (row) =>
          !query || JSON.stringify(row).toLocaleLowerCase().includes(query),
      );
      const page = Math.max(0, Math.floor(Number(input.page) || 0));
      return { data: rows.slice(page * 25, page * 25 + 25) };
    }
  }
}
