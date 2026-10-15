import { describe, it, expect, vi } from "vitest";
const { createClient } = vi.hoisted(() => ({ createClient: vi.fn() }));
vi.mock("@supabase/supabase-js", () => ({ createClient }));
vi.stubEnv("DEV", true);
vi.stubGlobal("window", { location: { search: "?demo=1" } });
const { api, client } = await import("./api");
describe("demo data isolation", () => {
  it("serves local fixtures without initializing a database client", async () => {
    const result = await api("list", { section: "analytics" });
    expect(result.data.total).toBe(2400);
    expect(client).toBeNull();
    expect(createClient).not.toHaveBeenCalled();
  });
  it("refuses all mutation actions", async () => {
    await expect(api("create_incident", { title: "sample" })).rejects.toThrow("المعاينة للعرض فقط");
    await expect(api("set_staff", {})).rejects.toThrow("المعاينة للعرض فقط");
    expect(createClient).not.toHaveBeenCalled();
  });
});
