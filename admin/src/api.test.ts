import { describe, it, expect, vi } from "vitest";
vi.stubGlobal("sessionStorage", {
  getItem: () => null,
  setItem: () => {},
  removeItem: () => {},
});
const { validateConfig, access } = await import("./api");
describe("deployment boundary", () => {
  const key = (role: string, ref: string) =>
    `header.${btoa(JSON.stringify({ role, ref }))}.signature`;
  it("refuses privileged keys, mismatched hosts and projects", () => {
    expect(
      validateConfig(
        "https://stage.supabase.co",
        "sb_secret_bad",
        "stage",
        "staging",
      ),
    ).toBeTruthy();
    expect(
      validateConfig(
        "https://stage.supabase.co",
        key("service_role", "stage"),
        "stage",
        "staging",
      ),
    ).toBeTruthy();
    expect(
      validateConfig(
        "https://production.supabase.co",
        key("anon", "stage"),
        "stage",
        "staging",
      ),
    ).toBeTruthy();
    expect(
      validateConfig(
        "https://stage.supabase.co",
        key("anon", "production"),
        "stage",
        "staging",
      ),
    ).toBeTruthy();
    expect(
      validateConfig(
        "http://stage.supabase.co",
        key("anon", "stage"),
        "stage",
        "staging",
      ),
    ).toBeTruthy();
  });
  it("accepts matching public keys in explicitly labelled environments", () => {
    expect(
      validateConfig(
        "https://stage.supabase.co",
        key("anon", "stage"),
        "stage",
        "staging",
      ),
    ).toBeNull();
    expect(
      validateConfig(
        "https://stage.supabase.co",
        "sb_publishable_example",
        "stage",
        "staging",
      ),
    ).toBeNull();
    expect(
      validateConfig(
        "https://stage.supabase.co",
        "sb_publishable_example",
        "stage",
        "",
      ),
    ).toBeTruthy();
  });
  it("does not offer reviewers or support team-wide administration", () => {
    expect(access.support).not.toContain("staff");
    expect(access.owner).toContain("analytics");
    expect(access.operator).not.toContain("analytics");
    expect(access.medical_reviewer).toEqual(["knowledge"]);
    expect(access.fiqh_reviewer).toEqual(["knowledge"]);
  });
});
