import { describe, it, expect } from "vitest";
import { shouldUseDemo } from "./preview-mode";
import { demoAudience, demoStatistics, demoResponse } from "./demo-data";
describe("local read-only preview", () => {
  it("requires an explicit development-only opt-in", () => {
    expect(shouldUseDemo(true, "?demo=1")).toBe(true);
    expect(shouldUseDemo(true, "")).toBe(false);
    expect(shouldUseDemo(true, "?demo=0")).toBe(false);
    expect(shouldUseDemo(false, "?demo=1")).toBe(false);
  });
  it("provides consistent fictional reporting populations", () => {
    expect(
      Object.values(demoStatistics.marital).reduce((a, b) => a + b, 0),
    ).toBe(demoStatistics.total);
    expect(
      demoAudience.today.happy +
        demoAudience.today.neutral +
        demoAudience.today.down,
    ).toBe(demoAudience.today.reports);
    for (const distribution of Object.values(
      demoAudience.checkin_details!.ratings,
    )) {
      expect(
        distribution.rows.reduce((total, r) => total + r.users, 0) +
          distribution.unknown,
      ).toBe(demoAudience.today.reports);
    }
    expect(demoResponse({ section: "analytics" }).data).toBe(demoAudience);
    expect(demoResponse({ section: "users" }).data).toEqual([]);
  });
});
