// @vitest-environment jsdom
import { act } from "react";
import { expect, it, vi } from "vitest";
// Prime the same fixture module the preview API loads asynchronously.
import "./demo-data";

it("navigates actual sidebar screens without rendering another section's payload", async () => {
  vi.stubEnv("DEV",true);
  vi.stubGlobal("IS_REACT_ACT_ENVIRONMENT",true);
  window.history.replaceState(null,"","/?demo=1#/overview");
  vi.spyOn(window,"scrollTo").mockImplementation(()=>{});
  document.body.innerHTML='<div id="root"></div>';
  await act(async()=>{ await import("./main"); });
  expect(document.querySelector("h1")?.textContent).toBe("نظرة عامة");
  async function click(section:string,title:string,content:string) {
    const link=document.querySelector<HTMLAnchorElement>(`.sidebar a[href="#/${section}"]`);
    expect(link).not.toBeNull();
    await act(async()=>{link!.dispatchEvent(new MouseEvent("click",{bubbles:true,button:0}));});
    expect(window.location.hash).toBe(`#/${section}`);
    expect(document.querySelector("h1")?.textContent).toBe(title);
    expect(document.body.textContent).toContain(content);
    expect(document.querySelector('.sidebar a[aria-current="page"]')?.getAttribute("href")).toBe(`#/${section}`);
  }
  await click("operations","مركز العمليات","مسار التهيئة");
  await click("analytics","الجمهور والعافية","تفاصيل التسجيل اليومي");
  await click("overview","نظرة عامة","إجمالي الحسابات");
  await click("analytics","الجمهور والعافية","اتجاهات العافية");
  await click("operations","مركز العمليات","مراقبة الذكاء الاصطناعي");
  await click("users","المستخدمات","member-one@niswah.invalid");
  await click("support","الدعم والمتابعة","مثال: استفسار عن إعدادات التطبيق");
  await click("community","إدارة المجتمع","مثال تجريبي: مشاركة تجربة تنظيم اليوم");
  await click("content","مسودات المحتوى","مثال: دليل البدء مع نسوة");
  await click("knowledge","المراجعة العلمية","DEMO-PRODUCT-001");
  await click("staff","فريق الإدارة","owner@niswah.invalid");
  await click("audit","سجل النشاط","read.analytics");
  await click("overview","نظرة عامة","إجمالي الحسابات");
});
