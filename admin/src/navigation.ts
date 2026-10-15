import { useCallback, useEffect, useState } from "react";
import type { Section } from "./api";
export const sections: Section[] = [
  "overview",
  "operations",
  "analytics",
  "users",
  "support",
  "community",
  "content",
  "knowledge",
  "staff",
  "audit",
];
export function sectionHref(section: Section) {
  return `#/${section}`;
}
export function resolveSection(
  hash: string,
  allowed: readonly Section[] = sections,
): Section {
  const candidate = hash.replace(/^#\//, "") as Section;
  return allowed.includes(candidate) ? candidate : allowed[0] || "overview";
}
export function useSectionRoute(
  allowed: readonly Section[] = sections,
): [Section, (section: Section) => void] {
  const [section, setSection] = useState(() =>
    resolveSection(window.location.hash, allowed),
  );
  useEffect(() => {
    function sync() {
      const next = resolveSection(window.location.hash, allowed);
      setSection(next);
      if (window.location.hash !== sectionHref(next)) {
        window.history.replaceState(null, "", sectionHref(next));
      }
    }
    sync();
    window.addEventListener("hashchange", sync);
    return () => window.removeEventListener("hashchange", sync);
  }, [allowed]);
  const navigate = useCallback(
    (next: Section) => {
      const target = allowed.includes(next) ? next : allowed[0] || "overview";
      setSection(target);
      window.location.hash = sectionHref(target);
    },
    [allowed],
  );
  return [section, navigate];
}
