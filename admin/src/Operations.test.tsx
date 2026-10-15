import { describe, it, expect } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import Operations, { Attention } from "./Operations";
const data = {
  as_of: "2026-10-15T10:00:00Z",
  alerts: [],
  open_incidents: 0,
  overdue_incidents: 0,
  incidents: [],
  assignees: [],
  funnel: { state: "not_connected", since: null, steps: [] },
  ai: [
    {
      advisor: "ai-assistant-chat",
      state: "not_connected",
      last_seen_at: null,
      requests: null,
      server_errors: null,
      rate_limited: null,
      rejected: null,
      p95_ms: null,
      model_calls: null,
      model_failures: null,
      input_tokens: null,
      output_tokens: null,
      usage_missing: null,
    },
  ],
};
describe("operational monitoring", () => {
  it("does not render disconnected sources as healthy or zero", () => {
    const html = renderToStaticMarkup(
      <Operations
        data={data}
        action={() => {}}
        busy={false}
        navigate={() => {}}
        owner
      />,
    );
    expect(html).toContain("غير متصل / لا بيانات");
    expect(html).toContain("تتبّع الخطوات لم يرسل بيانات بعد");
    expect(html).toContain("التكاليف غير مربوطة بالفوترة");
    expect(html).not.toContain("NaN");
  });
  it("shows actionable overdue work without claiming all integrations are healthy", () => {
    const html = renderToStaticMarkup(
      <Attention
        data={{ alerts: [], open_incidents: 2, overdue_incidents: 1 }}
        navigate={() => {}}
      />,
    );
    expect(html).toContain("تجاوزت الموعد");
    expect(html).toContain("هذا لا يؤكد سلامة مصادر القياس غير المتصلة");
  });
});
