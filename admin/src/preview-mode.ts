// A local development preview only. This never grants backend authorization.
export function shouldUseDemo(development: boolean, search: string) {
  return development && new URLSearchParams(search).get("demo") === "1";
}
export const isDemo = shouldUseDemo(
  import.meta.env.DEV,
  typeof window === "undefined" ? "" : window.location.search,
);
