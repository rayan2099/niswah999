import { describe, it, expect } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import Statistics, { percent, type StatisticsData } from "./Statistics";
const data: StatisticsData = {
  total: 0,
  new_today: 0,
  new_7d: 0,
  new_30d: 0,
  verified: 0,
  unverified: 0,
  onboarded: 0,
  incomplete: 0,
  signed_in_7d: 0,
  signed_in_30d: 0,
  marital: { married: 0, not_married: 0, unknown: 0 },
  age: {
    under_18: 0,
    "18_24": 0,
    "25_34": 0,
    "35_44": 0,
    "45_plus": 0,
    unknown: 0,
  },
  language: { ar: 0, en: 0, unknown: 0 },
};
describe("audience statistics", () => {
  it("renders an empty population without NaN or misleading percentages", () => {
    const html = renderToStaticMarkup(<Statistics data={data} />);
    expect(html).not.toMatch(/NaN|Infinity/);
    expect(percent(0, 0)).toBe(0);
  });
  it("keeps unknown answers distinct from unmarried users", () => {
    const html = renderToStaticMarkup(
      <Statistics
        data={{
          ...data,
          total: 4,
          marital: { married: 1, not_married: 1, unknown: 2 },
        }}
      />,
    );
    expect(html).toContain("لم تُحفظ إجابة");
    expect(html).toContain("غير متزوجات");
    expect(percent(2, 4)).toBe(50);
    expect(html).toContain("آخر تسجيل دخول، وليس نشاط الاستخدام");
  });
});
