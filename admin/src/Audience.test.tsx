import { describe, it, expect } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import Audience, {
  Trend,
  countryLabel,
  type AudienceData,
  type DailyWellbeing,
} from "./Audience";
const day: DailyWellbeing = {
  day: "2026-10-15",
  reports: 0,
  happy: 0,
  down: 0,
  neutral: 0,
  low_energy: 0,
  poor_sleep: 0,
  sleepy: 0,
  sleepy_reports: 0,
  mood_reports: 0,
  mood_avg: null,
  energy_avg: null,
  sleep_avg: null,
};
export const empty: AudienceData = {
  as_of: "2026-10-15T12:00:00Z",
  date: "2026-10-15",
  total: 0,
  countries: { rows: [], other: 0, unknown: 0 },
  madhhab: {
    hanafi: 0,
    maliki: 0,
    shafii: 0,
    hanbali: 0,
    unknown: 0,
    unset: 0,
  },
  cycle: {
    fresh: 0,
    missing: 0,
    bleeding: 0,
    no_bleeding: 0,
    bleeding_unknown: 0,
    haid: 0,
    tahara: 0,
    needs_advisory: 0,
    madhhab_unresolved: 0,
    unknown: 0,
    ovulation: 0,
    pre_period: 0,
    prediction_coverage: 0,
  },
  today: day,
  wellbeing_users_7d: 0,
  wellbeing_users_30d: 0,
  trend: [day],
};
describe("audience and wellbeing analytics", () => {
  it("keeps absent readings empty and predictions visibly estimated", () => {
    const html = renderToStaticMarkup(<Audience data={empty} />);
    expect(html).not.toMatch(/NaN|Infinity/);
    expect(html).toContain("لم تصل تسجيلات");
    expect(html).toContain("تقديرات وليست حالات مؤكدة");
    expect(html).toContain("لا نستخدم القيمة الافتراضية القديمة");
    expect(html).toContain("إجابة صريحة");
    expect(html).toContain("بلا إجابة صالحة اليوم");
  });
  it("does not turn missing days into zeroes or connect across gaps", () => {
    const present = { ...day, reports: 1, mood_avg: 4 };
    const html = renderToStaticMarkup(
      <Trend
        rows={[
          present,
          { ...day, day: "2026-10-14" },
          { ...present, day: "2026-10-13" },
        ]}
      />,
    );
    expect(html.match(/<circle/g) || []).toHaveLength(2);
    expect(html).not.toContain('stroke-width="2.5"');
  });
  it("labels country codes and escapes legacy saved labels", () => {
    expect(countryLabel("SA")).toBe("المملكة العربية السعودية");
    const html = renderToStaticMarkup(
      <Audience
        data={{
          ...empty,
          total: 1,
          countries: {
            rows: [{ country: "<script>alert(1)</script>", users: 1 }],
            other: 0,
            unknown: 0,
          },
        }}
      />,
    );
    expect(html).not.toContain("<script>");
    expect(html).toContain("&lt;script&gt;");
  });
});
