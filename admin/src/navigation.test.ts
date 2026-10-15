import { describe,it,expect } from "vitest";
import { sections, resolveSection, sectionHref } from "./navigation";
import { demoResponse } from "./demo-data";
describe("sidebar routes",()=>{
 it("gives every sidebar destination a distinct reloadable URL",()=>{
  expect(new Set(sections.map(sectionHref)).size).toBe(sections.length);
  for(const section of sections) expect(resolveSection(sectionHref(section))).toBe(section);
 });
 it("falls back safely for unknown or unauthorized destinations",()=>{
  expect(resolveSection("#/missing")).toBe("overview");
  expect(resolveSection("#/staff",["users","support"])).toBe("users");
  expect(resolveSection("#/support",["users","support"])).toBe("support");
 });
 it("populates every preview destination and both community tabs",()=>{
  for(const section of sections) {
   const data=demoResponse({section}).data;
   if(Array.isArray(data)) expect(data.length,section).toBeGreaterThan(0);
   else expect(data,section).toBeTruthy();
  }
  expect(demoResponse({section:"community",kind:"comment"}).data).toHaveLength(1);
 });
 it("searches and paginates preview lists",()=>{
  expect(demoResponse({section:"users",query:"member-one"}).data).toHaveLength(1);
  expect(demoResponse({section:"users",query:"nothing-matches"}).data).toHaveLength(0);
  expect(demoResponse({section:"users",page:1}).data).toHaveLength(0);
 });
});
