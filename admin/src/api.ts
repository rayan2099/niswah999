import { createClient } from "@supabase/supabase-js";
export type Role =
  | "owner"
  | "support"
  | "moderator"
  | "editor"
  | "medical_reviewer"
  | "fiqh_reviewer"
  | "operator";
export type Section =
  | "overview"
  | "operations"
  | "users"
  | "support"
  | "community"
  | "content"
  | "knowledge"
  | "staff"
  | "audit";
export const access: Record<Role, Section[]> = {
  owner: [
    "overview",
    "operations",
    "users",
    "support",
    "community",
    "content",
    "knowledge",
    "staff",
    "audit",
  ],
  support: ["users", "support"],
  moderator: ["community"],
  editor: ["content"],
  medical_reviewer: ["knowledge"],
  fiqh_reviewer: ["knowledge"],
  operator: ["overview", "operations"],
};
export function validateConfig(
  url: string,
  key: string,
  ref: string,
  environment: string,
): string | null {
  try {
    if (
      !url ||
      !key ||
      !ref ||
      !["staging", "production"].includes(environment)
    )
      return "إعداد الاتصال غير مكتمل. يرجى التواصل مع مسؤول النشر.";
    const parsed = new URL(url);
    if (
      parsed.protocol !== "https:" ||
      parsed.hostname !== `${ref}.supabase.co`
    )
      return "إعداد البيئة لا يطابق مشروع البيانات.";
    if (key.startsWith("sb_secret_")) return "مفتاح غير مناسب للمتصفح.";
    if (!key.startsWith("sb_publishable_")) {
      const payload = JSON.parse(
        atob(key.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")),
      );
      if (payload.role !== "anon" || payload.ref !== ref)
        return "يجب استخدام المفتاح العام للمشروع الصحيح.";
    }
    return null;
  } catch {
    return "تعذر التحقق من إعداد الاتصال.";
  }
}
const url = import.meta.env.VITE_SUPABASE_URL || "";
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || "";
export const environment = import.meta.env.VITE_APP_ENV || "";
export const configurationError = validateConfig(
  url,
  key,
  import.meta.env.VITE_SUPABASE_PROJECT_REF || "",
  environment,
);
export const client = configurationError
  ? null
  : createClient(url, key, {
      auth: {
        storage: sessionStorage,
        storageKey: "niswah-admin-session",
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: false,
      },
    });
export async function api(action: string, input: Record<string, unknown> = {}) {
  if (!client) throw new Error("إعداد الاتصال غير مكتمل");
  const { data, error } = await client.rpc("niswah_admin_api", {
    p_action: action,
    p_input: input,
  });
  if (error) {
    const messages: Record<string, string> = {
      "Staff access required": "هذا الحساب غير مضاف إلى فريق الإدارة.",
      "Session invalid": "انتهت الجلسة. سجّل الخروج ثم ادخل مجدداً.",
      "MFA required": "يرجى إكمال التحقق الثنائي.",
      "Permission denied": "لا تملك صلاحية تنفيذ هذا الإجراء.",
      "Verified account not found":
        "لم يتم العثور على حساب ببريد مؤكد. يجب إنشاء الحساب وتأكيده أولاً.",
      "Keep at least one active owner": "يجب إبقاء مالك واحد نشط على الأقل.",
      "Qualified reviewer role required": "يتطلب هذا الإجراء حساب مراجع مختص.",
    };
    throw new Error(
      messages[error.message] ||
        "تعذر تنفيذ الطلب. راجع المدخلات وحاول مجدداً.",
    );
  }
  return data;
}
