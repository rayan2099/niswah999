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
  assignees: [],
  incidents: [],
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
    default:
      return { data: [] };
  }
}
