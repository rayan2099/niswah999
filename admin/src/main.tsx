import React, {
  useEffect,
  useState,
  type FormEvent,
  type ReactNode,
} from "react";
import { createRoot } from "react-dom/client";
import type { Session } from "@supabase/supabase-js";
import {
  LayoutDashboard,
  Users,
  LifeBuoy,
  MessagesSquare,
  BookOpen,
  ShieldCheck,
  FileText,
  History,
  LogOut,
  ArrowLeft,
  RefreshCw,
  Plus,
  Search,
  ChevronLeft,
  ChevronRight,
  LockKeyhole,
  Check,
  X,
  EyeOff,
  Eye,
  Menu,
  Activity,
} from "lucide-react";
import {
  api,
  client,
  configurationError,
  environment,
  access,
  type Role,
  type Section,
} from "./api";
import "./style.css";
import { isDemo } from "./preview-mode";
import Statistics from "./Statistics";
import Audience from "./Audience";
import Operations, { Attention } from "./Operations";
type Row = Record<string, any>;
const titles: Record<Section, string> = {
  overview: "نظرة عامة",
  operations: "مركز العمليات",
  analytics: "الجمهور والعافية",
  users: "المستخدمات",
  support: "الدعم والمتابعة",
  community: "إدارة المجتمع",
  content: "مسودات المحتوى",
  knowledge: "المراجعة العلمية",
  staff: "فريق الإدارة",
  audit: "سجل النشاط",
};
const descriptions: Record<Section, string> = {
  overview: "صورة واضحة عن نسوة، والأعمال التي تحتاج انتباهك.",
  operations: "متابعة المهام والقياس التشغيلي ومسار التهيئة والذكاء الاصطناعي.",
  analytics:
    "توزيع الجمهور، والحالة المسجلة، واتجاهات العافية مع وضوح تغطية البيانات.",
  users: "معلومات الحساب والمساعدة، مع الحفاظ على خصوصية السجلات الصحية.",
  support: "طلبات مسجلة بواسطة الفريق، من أول متابعة حتى الحل.",
  community: "مراجعة المنشورات والتعليقات العامة وإخفاء المحتوى عند الحاجة.",
  content: "مساحة إعداد المحتوى قبل مراجعته وربطه بالتطبيق.",
  knowledge: "الأدلة والمصادر وقرارات المراجعين، لكل نسخة على حدة.",
  staff: "صلاحيات محددة لكل دور، ووصول مخصص للحسابات المعتمدة.",
  audit: "سجل عمليات القراءة والتغييرات، ومن قام بها ومتى.",
};
const icons = {
  overview: LayoutDashboard,
  operations: Activity,
  analytics: Activity,
  users: Users,
  support: LifeBuoy,
  community: MessagesSquare,
  content: FileText,
  knowledge: BookOpen,
  staff: ShieldCheck,
  audit: History,
};
const roleNames: Record<Role, string> = {
  owner: "المالك",
  support: "الدعم",
  moderator: "مشرف المجتمع",
  editor: "محرر المحتوى",
  medical_reviewer: "مراجع طبي",
  fiqh_reviewer: "مراجع فقهي",
  operator: "التشغيل",
};
const statusNames: Record<string, string> = {
  open: "مفتوح",
  in_progress: "قيد المتابعة",
  resolved: "تم الحل",
  approved: "موافقة المراجع",
  changes_requested: "تحتاج تعديلاً",
  rejected: "مرفوض",
  DRAFT: "مسودة",
  PUBLISHED: "منشور",
  RETIRED: "متقاعد",
};
const number = (n: unknown) =>
  new Intl.NumberFormat("ar-SA").format(Number(n) || 0);
const date = (v: string) =>
  v
    ? new Date(v).toLocaleString("ar-SA", {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: "Asia/Riyadh",
      })
    : "—";
function Badge({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: string;
}) {
  return <span className={`badge ${tone}`}>{children}</span>;
}
function Notice({
  children,
  error = false,
}: {
  children: ReactNode;
  error?: boolean;
}) {
  return (
    <div
      className={`notice ${error ? "error" : ""}`}
      role={error ? "alert" : "status"}
    >
      {children}
    </div>
  );
}
function Brand() {
  return (
    <div className="brand">
      <span className="brand-mark">ن</span>
      <div>
        <strong>نسوة</strong>
        <small>NISWAH · ADMIN</small>
      </div>
    </div>
  );
}
function Button({
  children,
  onClick,
  disabled = false,
}: {
  children: ReactNode;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button className="button" onClick={onClick} disabled={disabled}>
      {children}
    </button>
  );
}
function App() {
  const [session, setSession] = useState<Session | null>(null),
    [initial, setInitial] = useState(true);
  const [role, setRole] = useState<Role | null>(null),
    [ready, setReady] = useState(false),
    [error, setError] = useState("");
  const [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [busy, setBusy] = useState(false);
  const [factor, setFactor] = useState(""),
    [qr, setQr] = useState(""),
    [code, setCode] = useState(""),
    [mfaLoading, setMfaLoading] = useState(false);
  const [section, setSection] = useState<Section>("overview");
  useEffect(() => {
    if (!client) {
      setInitial(false);
      return;
    }
    client.auth.getSession().then(({ data, error }) => {
      if (error) setError("تعذر استعادة الجلسة");
      setSession(data.session);
      setInitial(false);
    });
    const {
      data: { subscription },
    } = client.auth.onAuthStateChange((_event, next) => {
      setSession(next);
    });
    return () => subscription.unsubscribe();
  }, []);
  useEffect(() => {
    let active = true;
    setReady(false);
    setRole(null);
    setError("");
    setFactor("");
    setQr("");
    setCode("");
    if (!session || !client) return;
    setMfaLoading(true);
    (async () => {
      try {
        const info = await api("session");
        if (!access[info.role as Role])
          throw new Error("صلاحية الحساب غير معروفة");
        const { data: level, error: levelError } =
          await client.auth.mfa.getAuthenticatorAssuranceLevel();
        if (levelError) throw levelError;
        if (!active) return;
        setRole(info.role);
        setSection(access[info.role as Role][0]);
        if (level?.currentLevel === "aal2") {
          setReady(true);
          return;
        }
        const { data: factors, error: fError } =
          await client.auth.mfa.listFactors();
        if (fError) throw fError;
        if (active)
          setFactor(
            factors.totp.find((f) => f.status === "verified")?.id || "",
          );
      } catch (e) {
        if (active)
          setError(e instanceof Error ? e.message : "تعذر التحقق من الحساب");
      } finally {
        if (active) setMfaLoading(false);
      }
    })();
    return () => {
      active = false;
    };
  }, [session?.access_token]);
  async function login(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const { error } = await client!.auth.signInWithPassword({
        email,
        password,
      });
      if (error)
        throw new Error("تعذر تسجيل الدخول. تحقق من البريد وكلمة المرور.");
      setPassword("");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function enroll() {
    setBusy(true);
    setError("");
    try {
      const { data: factors, error: fe } = await client!.auth.mfa.listFactors();
      if (fe) throw fe;
      for (const f of factors.all.filter(
        (f) =>
          f.factor_type === "totp" &&
          f.status === "unverified" &&
          f.friendly_name === "Niswah Admin",
      )) {
        const r = await client!.auth.mfa.unenroll({ factorId: f.id });
        if (r.error) throw r.error;
      }
      const { data, error } = await client!.auth.mfa.enroll({
        factorType: "totp",
        friendlyName: "Niswah Admin",
        issuer: "Niswah",
      });
      if (error) throw error;
      setFactor(data.id);
      setQr(data.totp.qr_code);
    } catch {
      setError("تعذر إعداد التحقق الثنائي. حاول مجدداً.");
    } finally {
      setBusy(false);
    }
  }
  async function verify(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const { error } = await client!.auth.mfa.challengeAndVerify({
        factorId: factor,
        code,
      });
      if (error) throw new Error("رمز التحقق غير صحيح أو انتهت صلاحيته.");
      setQr("");
      setCode("");
      const r = await client!.auth.getSession();
      setSession(r.data.session);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function logout() {
    setReady(false);
    setRole(null);
    setQr("");
    const r = await client!.auth.signOut({ scope: "local" });
    if (r.error) {
      sessionStorage.removeItem("niswah-admin-session");
      location.reload();
    }
    setSession(null);
  }
  if (configurationError)
    return (
      <Gate>
        <Brand />
        <h1>لوحة إدارة نسوة</h1>
        <Notice error>{configurationError}</Notice>
        <p>لا تُعرض أي بيانات حتى يكتمل إعداد البيئة.</p>
      </Gate>
    );
  if (initial)
    return (
      <Gate>
        <Brand />
        <p role="status">جارٍ التحقق من الجلسة…</p>
      </Gate>
    );
  if (!session)
    return (
      <Gate>
        <Brand />
        <span className="eyebrow">مساحة الفريق</span>
        <h1>كل ما تحتاجه لإدارة نسوة.</h1>
        <p>دخول آمن للفريق المعتمد، وصلاحيات تناسب مسؤولياتك.</p>
        <form onSubmit={login}>
          <label>
            البريد الإلكتروني
            <input
              type="email"
              autoComplete="username"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              dir="ltr"
            />
          </label>
          <label>
            كلمة المرور
            <input
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              dir="ltr"
            />
          </label>
          {error && <Notice error>{error}</Notice>}
          <button className="button primary" disabled={busy}>
            {busy ? "جارٍ الدخول…" : "تسجيل الدخول"}
            <ArrowLeft size={17} />
          </button>
        </form>
        <small className="muted">
          <LockKeyhole size={14} /> الحسابات المضافة إلى فريق الإدارة فقط.
        </small>
        <Env />
      </Gate>
    );
  if (!ready || !role)
    return (
      <Gate>
        <Brand />
        <h1>{role ? "التحقق بخطوتين" : "التحقق من صلاحياتك"}</h1>
        {error && <Notice error>{error}</Notice>}
        {mfaLoading ? (
          <p role="status">جارٍ التحقق…</p>
        ) : role ? (
          <>
            <p>
              {qr
                ? "امسح الرمز بتطبيق المصادقة، ثم أدخل الرمز المكون من ستة أرقام."
                : "أكمل التحقق الثنائي للوصول إلى لوحة الإدارة."}
            </p>
            {qr && (
              <img
                className="qr"
                alt="رمز إعداد تطبيق المصادقة"
                src={`data:image/svg+xml;charset=utf-8,${encodeURIComponent(qr)}`}
              />
            )}{" "}
            {factor ? (
              <form onSubmit={verify}>
                <label>
                  رمز تطبيق المصادقة
                  <input
                    autoComplete="one-time-code"
                    inputMode="numeric"
                    pattern="[0-9]{6}"
                    maxLength={6}
                    required
                    value={code}
                    onChange={(e) =>
                      setCode(e.target.value.replace(/[^0-9]/g, ""))
                    }
                    dir="ltr"
                  />
                </label>
                <button className="button primary" disabled={busy}>
                  تحقق ومتابعة
                </button>
              </form>
            ) : (
              <Button disabled={busy} onClick={enroll}>
                إعداد تطبيق المصادقة
              </Button>
            )}
          </>
        ) : null}
        <button className="text-button" onClick={logout}>
          تسجيل الخروج
        </button>
        <Env />
      </Gate>
    );
  return (
    <Dashboard
      key={session.user.id}
      role={role}
      email={session.user.email || ""}
      section={section}
      setSection={setSection}
      logout={logout}
    />
  );
}
function Gate({ children }: { children: ReactNode }) {
  return (
    <main className="gate">
      <div className="gate-card">
        {children}
        {import.meta.env.DEV && (
          <a className="button primary preview-link" href="/?demo=1">
            عرض تجريبي للوحة الإدارة <ArrowLeft size={17} />
          </a>
        )}
      </div>
      <aside className="gate-art">
        <div className="orbit one" />
        <div className="orbit two" />
        <div className="art-copy">
          <span>نسوة، بعناية.</span>
          <p>
            مساحة واحدة.
            <br />
            رؤية أوضح، وأثر أقرب.
          </p>
        </div>
        <span className="art-foot">NISWAH OPERATIONS</span>
      </aside>
    </main>
  );
}
function Env() {
  if (isDemo) return <span className="badge">معاينة · بيانات وهمية</span>;
  return (
    <span
      className={`environment ${environment === "production" ? "production" : ""}`}
    >
      <span />
      {environment === "production" ? "البيئة الفعلية" : "بيئة الاختبار"}
    </span>
  );
}
function Dashboard({
  role,
  email,
  section,
  setSection,
  logout,
}: {
  role: Role;
  email: string;
  section: Section;
  setSection: (s: Section) => void;
  logout: () => void;
}) {
  const [data, setData] = useState<any>(null),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(""),
    [success, setSuccess] = useState("");
  const [query, setQuery] = useState(""),
    [search, setSearch] = useState(""),
    [page, setPage] = useState(0),
    [kind, setKind] = useState("post"),
    [refresh, setRefresh] = useState(0),
    [mobile, setMobile] = useState(false);
  const [modal, setModal] = useState<"ticket" | "draft" | "staff" | null>(null),
    [selected, setSelected] = useState<Row | null>(null),
    [acting, setActing] = useState(false);
  useEffect(() => {
    setPage(0);
    setQuery("");
    setSearch("");
    setSelected(null);
    setModal(null);
    setSuccess("");
  }, [section]);
  useEffect(() => {
    let alive = true;
    setLoading(true);
    setData(null);
    setError("");
    api("list", { section, query: search, page, kind })
      .then((r) => {
        if (alive) setData(r.data);
      })
      .catch((e) => {
        if (alive) setError(e.message);
      })
      .finally(() => {
        if (alive) setLoading(false);
      });
    return () => {
      alive = false;
    };
  }, [section, search, page, kind, refresh]);
  async function action(name: string, input: Row) {
    setActing(true);
    setError("");
    setSuccess("");
    try {
      await api(name, input);
      setSuccess("تم حفظ الإجراء بنجاح.");
      setModal(null);
      setSelected(null);
      setRefresh((v) => v + 1);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setActing(false);
    }
  }
  const Icon = icons[section];
  return (
    <div className="shell">
      <aside className={`sidebar ${mobile ? "open" : ""}`}>
        <Brand />
        <div className="nav-caption">إدارة المنصة</div>
        <nav>
          {access[role].map((s) => {
            const I = icons[s];
            return (
              <button
                key={s}
                className={s === section ? "selected" : ""}
                onClick={() => {
                  setSection(s);
                  setMobile(false);
                }}
              >
                <I size={19} />
                {titles[s]}
                {s === section && <span className="nav-dot" />}
              </button>
            );
          })}
        </nav>
        <div className="sidebar-bottom">
          <div className="privacy-note">
            <ShieldCheck size={21} />
            <p>
              خصوصية المستخدمات أولاً
              <small>الوصول حسب الدور، وكل إجراء مسجل.</small>
            </p>
          </div>
          <div className="staff-profile">
            <span className="avatar">{email[0]?.toUpperCase()}</span>
            <div>
              <strong>{roleNames[role]}</strong>
              <small dir="ltr">{email}</small>
            </div>
            <button aria-label="تسجيل الخروج" onClick={logout}>
              <LogOut size={18} />
            </button>
          </div>
        </div>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <div className="breadcrumb">
            <button
              className="menu-button"
              aria-label="فتح القائمة"
              onClick={() => setMobile(!mobile)}
            >
              <Menu />
            </button>
            <span>مساحة العمل</span>
            <ChevronLeft size={14} />
            <strong>{titles[section]}</strong>
          </div>
          <Env />
        </header>
        <main className="main">
          {isDemo && (
            <div className="notice demo-notice" role="status">
              <strong>معاينة تفاعلية — جميع الأرقام وهمية</strong>
              <span>
                استكشف النظرة العامة والجمهور والعافية ومركز العمليات من
                القائمة. لا يوجد اتصال ببيانات المستخدمات، ولا تُحفظ التغييرات.
              </span>
            </div>
          )}
          <div className="page-heading">
            <div>
              <span className="eyebrow">NISWAH / OPERATIONS</span>
              <h1>{titles[section]}</h1>
              <p>{descriptions[section]}</p>
            </div>
            <Button disabled={loading} onClick={() => setRefresh((v) => v + 1)}>
              <RefreshCw size={16} className={loading ? "spinning" : ""} />
              تحديث
            </Button>
          </div>
          {error && <Notice error>{error}</Notice>}
          {success && <Notice>{success}</Notice>}
          {section === "overview" ? (
            loading ? (
              <Loading />
            ) : (
              data && (
                <Overview
                  data={data}
                  navigate={setSection}
                  owner={role === "owner"}
                />
              )
            )
          ) : section === "analytics" ? (
            loading ? (
              <Loading />
            ) : (
              data && <Audience data={data} />
            )
          ) : section === "operations" ? (
            loading ? (
              <Loading />
            ) : (
              data && (
                <Operations
                  data={data}
                  action={action}
                  busy={acting}
                  navigate={setSection}
                  owner={role === "owner"}
                />
              )
            )
          ) : (
            <>
              <div className="toolbar">
                <form
                  className="search"
                  onSubmit={(e) => {
                    e.preventDefault();
                    setPage(0);
                    setSearch(query);
                  }}
                >
                  <Search size={18} />
                  <input
                    aria-label="بحث"
                    placeholder={
                      section === "users"
                        ? "بحث بالبريد أو الهاتف أو معرّف الحساب…"
                        : "بحث…"
                    }
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                  />
                  <button>بحث</button>
                </form>
                {section === "community" && (
                  <select
                    aria-label="نوع المحتوى"
                    value={kind}
                    onChange={(e) => {
                      setKind(e.target.value);
                      setPage(0);
                    }}
                  >
                    <option value="post">المنشورات</option>
                    <option value="comment">التعليقات</option>
                  </select>
                )}
                {["support", "content", "staff"].includes(section) && (
                  <button
                    className="button primary"
                    onClick={() =>
                      setModal(
                        section === "support"
                          ? "ticket"
                          : section === "content"
                            ? "draft"
                            : "staff",
                      )
                    }
                  >
                    <Plus size={17} />
                    {section === "support"
                      ? "طلب جديد"
                      : section === "content"
                        ? "مسودة جديدة"
                        : "إدارة صلاحية"}
                  </button>
                )}
              </div>
              {section === "knowledge" && (
                <Notice>
                  قرارات المراجعين مستقلة عن التحقق من المصادر. تسجيل الموافقة
                  هنا لا يغيّر أهلية النسخة أو ينشرها تلقائياً.
                </Notice>
              )}
              {section === "support" && (
                <p className="muted small">
                  طلبات داخلية يسجلها الفريق. إرسال طلبات الدعم من التطبيق لم
                  يُربط بهذه المساحة بعد.
                </p>
              )}
              {section === "content" && (
                <p className="muted small">
                  هذه مسودات محفوظة للفريق. لا تُنشر في التطبيق أو تُضاف إلى
                  إجابات الذكاء الاصطناعي.
                </p>
              )}
              <section className="panel data-panel">
                <div className="panel-heading">
                  <h2>
                    <Icon size={18} />
                    {titles[section]}
                  </h2>
                  <Badge>٢٥ سجلاً لكل صفحة</Badge>
                </div>
                {loading ? (
                  <Loading />
                ) : Array.isArray(data) && data.length ? (
                  <div className="table-scroll">
                    <DataTable
                      section={section}
                      rows={data}
                      onSelect={setSelected}
                      acting={acting}
                      action={action}
                      kind={kind}
                    />
                  </div>
                ) : !error ? (
                  <Empty />
                ) : null}
              </section>
              <div className="pagination">
                <Button
                  disabled={page === 0 || loading}
                  onClick={() => setPage((p) => p - 1)}
                >
                  <ChevronRight size={15} />
                  السابق
                </Button>
                <span>صفحة {number(page + 1)}</span>
                <Button
                  disabled={loading || !Array.isArray(data) || data.length < 25}
                  onClick={() => setPage((p) => p + 1)}
                >
                  التالي
                  <ChevronLeft size={15} />
                </Button>
              </div>
            </>
          )}
          <footer className="page-footer">
            <span>نسوة · مساحة إدارة الفريق</span>
            <span>التوقيت: الرياض</span>
          </footer>
        </main>
      </div>
      {modal && (
        <Modal
          title={
            modal === "ticket"
              ? "تسجيل طلب دعم"
              : modal === "draft"
                ? "إنشاء مسودة محتوى"
                : "إدارة وصول أحد أعضاء الفريق"
          }
          close={() => !acting && setModal(null)}
        >
          <form
            onSubmit={(e) => {
              e.preventDefault();
              const f = Object.fromEntries(new FormData(e.currentTarget));
              action(
                modal === "ticket"
                  ? "create_ticket"
                  : modal === "draft"
                    ? "create_draft"
                    : "set_staff",
                {
                  ...f,
                  ...(modal === "staff" ? { active: f.active === "true" } : {}),
                },
              );
            }}
          >
            {modal === "ticket" ? (
              <>
                <Field
                  label="موضوع الطلب"
                  name="subject"
                  minLength={3}
                  maxLength={160}
                />
                <Field
                  label="معرّف حساب المستخدمة (اختياري)"
                  name="user_id"
                  required={false}
                />
                <label>
                  الأولوية
                  <select name="priority">
                    <option value="normal">عادية</option>
                    <option value="high">عالية</option>
                  </select>
                </label>
                <p className="muted small">
                  اكتب وصفاً مختصراً دون تفاصيل صحية أو محادثات خاصة.
                </p>
              </>
            ) : modal === "draft" ? (
              <>
                <Field
                  label="عنوان المسودة"
                  name="title"
                  minLength={3}
                  maxLength={160}
                />
                <label>
                  المجال
                  <select name="domain">
                    <option value="HEALTH">التثقيف الصحي</option>
                    <option value="FIQH">الفقه</option>
                    <option value="NISWAH_PRODUCT">دليل نسوة</option>
                  </select>
                </label>
                <label>
                  اللغة
                  <select name="language">
                    <option value="ar">العربية</option>
                    <option value="en">English</option>
                  </select>
                </label>
                <label>
                  النص
                  <textarea
                    name="body"
                    required
                    minLength={10}
                    maxLength={20000}
                    rows={7}
                  />
                </label>
              </>
            ) : (
              <>
                <Notice>
                  الحساب يجب أن يكون موجوداً وبريده مؤكداً. هذا الإجراء يغيّر
                  صلاحيات الوصول فوراً.
                </Notice>
                <Field label="البريد الإلكتروني" name="email" type="email" />
                <label>
                  الدور
                  <select name="role">
                    {Object.entries(roleNames).map(([r, n]) => (
                      <option key={r} value={r}>
                        {n}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  حالة الوصول
                  <select name="active">
                    <option value="true">نشط</option>
                    <option value="false">إلغاء الوصول</option>
                  </select>
                </label>
              </>
            )}
            {error && <Notice error>{error}</Notice>}
            <button className="button primary" disabled={acting}>
              {acting ? "جارٍ الحفظ…" : "حفظ"}
            </button>
          </form>
        </Modal>
      )}
      {selected && (
        <Modal
          title={
            section === "knowledge"
              ? "تفاصيل الدليل والمراجعة"
              : section === "community"
                ? "مراجعة محتوى المجتمع"
                : "تفاصيل المسودة"
          }
          close={() => !acting && setSelected(null)}
        >
          {section === "knowledge" ? (
            <>
              <div className="detail-meta">
                <Badge>{selected.domain}</Badge>
                <Badge>{selected.madhhab || "عام"}</Badge>
                <Badge>
                  v{selected.version} · {selected.language}
                </Badge>
              </div>
              <h3 dir="auto">
                {selected.knowledge_key} — {selected.topic}
              </h3>
              <p className="preserve" dir="auto">
                {selected.canonical_statement}
              </p>
              {selected.qualification_note && (
                <Notice>{selected.qualification_note}</Notice>
              )}
              <h3>المصادر</h3>
              {selected.sources?.length ? (
                selected.sources.map((s: Row, i: number) => (
                  <div className="source" key={i} dir="auto">
                    <strong>{s.title}</strong>
                    <p>{s.locator}</p>
                    <small>{s.reference}</small>
                  </div>
                ))
              ) : (
                <p>لا توجد مصادر مرتبطة بهذه النسخة.</p>
              )}
              <h3>قرارات المراجعة</h3>
              {selected.reviews?.length ? (
                selected.reviews.map((r: Row, i: number) => (
                  <div className="source" key={i}>
                    <Badge>{statusNames[r.decision]}</Badge>
                    <p dir="auto">{r.note}</p>
                    <small>
                      {date(r.created_at)} · {r.reviewer_id}
                    </small>
                  </div>
                ))
              ) : (
                <p className="muted">
                  لم تُسجّل مراجعة بشرية عبر لوحة الإدارة لهذه النسخة.
                </p>
              )}
              {["medical_reviewer", "fiqh_reviewer"].includes(role) && (
                <form
                  onSubmit={(e) => {
                    e.preventDefault();
                    const f = Object.fromEntries(new FormData(e.currentTarget));
                    action("review", { ...f, id: selected.id });
                  }}
                >
                  <label>
                    قرار المراجع
                    <select name="decision">
                      <option value="changes_requested">تحتاج تعديلاً</option>
                      <option value="approved">موافقة المراجع</option>
                      <option value="rejected">رفض</option>
                    </select>
                  </label>
                  <label>
                    ملاحظات المراجعة
                    <textarea
                      required
                      minLength={10}
                      maxLength={3000}
                      name="note"
                      rows={4}
                    />
                  </label>
                  <button className="button primary" disabled={acting}>
                    حفظ قرار المراجعة
                  </button>
                </form>
              )}
            </>
          ) : section === "community" ? (
            <>
              <Badge tone={selected.is_hidden ? "rose" : "green"}>
                {selected.is_hidden ? "مخفي" : "ظاهر"}
              </Badge>
              <h3 dir="auto">{selected.title || "تعليق"}</h3>
              <p className="preserve" dir="auto">
                {selected.content}
              </p>
              <form
                onSubmit={(e) => {
                  e.preventDefault();
                  const f = new FormData(e.currentTarget);
                  action("moderate", {
                    id: selected.id,
                    kind,
                    hidden: !selected.is_hidden,
                    note: f.get("note"),
                  });
                }}
              >
                <label>
                  سبب الإجراء
                  <textarea
                    required
                    name="note"
                    minLength={5}
                    maxLength={500}
                    rows={3}
                  />
                </label>
                <button className="button primary" disabled={acting}>
                  {selected.is_hidden ? (
                    <Eye size={17} />
                  ) : (
                    <EyeOff size={17} />
                  )}{" "}
                  {selected.is_hidden ? "استعادة الظهور" : "إخفاء المحتوى"}
                </button>
              </form>
            </>
          ) : (
            <>
              <Badge>
                {selected.domain} · {selected.language}
              </Badge>
              <h3 dir="auto">{selected.title}</h3>
              <p className="preserve" dir="auto">
                {selected.body}
              </p>
            </>
          )}
          {error && <Notice error>{error}</Notice>}
        </Modal>
      )}
    </div>
  );
}
function Overview({
  data,
  navigate,
  owner,
}: {
  data: Row;
  navigate: (s: Section) => void;
  owner: boolean;
}) {
  const metrics = [
    ["إجمالي الحسابات", data.users, "حساب مسجل", Users],
    ["حسابات جديدة", data.new_users_7d, "خلال آخر ٧ أيام", Activity],
    ["أكملن التهيئة", data.onboarded, "حسب حالة الحساب", Check],
    ["طلبات تحتاج متابعة", data.open_tickets, "طلبات لم تُحل بعد", LifeBuoy],
  ] as const;
  const max = Math.max(1, ...data.signups.map((v: Row) => Number(v.count)));
  return (
    <>
      <div className="welcome-banner">
        <div>
          <span className="eyebrow">معاً، نعتني بالتفاصيل</span>
          <h2>رؤية أشمل. عناية أفضل.</h2>
          <p>تابع نمو المنصة، وامنح الأولوية لما يحتاج تدخّل الفريق.</p>
        </div>
        <div className="banner-symbol">
          ن<span>✦</span>
        </div>
      </div>
      <div className="metrics">
        {metrics.map(([title, value, caption, I]) => (
          <article className="metric" key={title}>
            <div>
              <span>{title}</span>
              <I size={19} />
            </div>
            <strong>{number(value)}</strong>
            <small>{caption}</small>
          </article>
        ))}
      </div>
      {data.attention && (
        <Attention data={data.attention} navigate={navigate} />
      )}
      {owner && data.statistics && <Statistics data={data.statistics} />}
      <div className="overview-grid">
        <section className="panel">
          <div className="panel-heading">
            <div>
              <h2>الحسابات الجديدة</h2>
              <p>التسجيلات اليومية · آخر ١٤ يوماً</p>
            </div>
            <Badge>{isDemo ? "بيانات وهمية" : "بيانات فعلية"}</Badge>
          </div>
          <div
            className="chart"
            role="img"
            aria-label="الرسم البياني للتسجيلات خلال أربعة عشر يوماً"
          >
            {data.signups.map((v: Row) => (
              <div className="chart-column" key={v.day}>
                <span className="chart-value">{number(v.count)}</span>
                <div className="bar-track">
                  <div
                    className="bar"
                    style={{
                      height: `${Math.max(v.count > 0 ? 3 : 0, (Number(v.count) / max) * 100)}%`,
                    }}
                  />
                </div>
                <small>
                  {new Date(v.day).toLocaleDateString("ar-SA", {
                    day: "numeric",
                    month: "numeric",
                    calendar: "gregory",
                  })}
                </small>
              </div>
            ))}
          </div>
        </section>
        <section className="panel">
          <div className="panel-heading">
            <h2>قائمة المتابعة</h2>
            <span className="status-dot" />
          </div>
          <div className="followup">
            <LifeBuoy />
            <div>
              <strong>طلبات الدعم</strong>
              <p>{number(data.open_tickets)} طلب لم يُحل</p>
            </div>
            {owner && (
              <button
                aria-label="فتح الدعم"
                onClick={() => navigate("support")}
              >
                <ArrowLeft size={18} />
              </button>
            )}
          </div>
          <div className="followup">
            <BookOpen />
            <div>
              <strong>قاعدة المعرفة</strong>
              <p>
                {number(data.knowledge_versions)} نسخة ·{" "}
                {number(data.review_decisions)} قرار مراجعة
              </p>
            </div>
            {owner && (
              <button
                aria-label="فتح المراجعة العلمية"
                onClick={() => navigate("knowledge")}
              >
                <ArrowLeft size={18} />
              </button>
            )}
          </div>
          <div className="followup">
            <MessagesSquare />
            <div>
              <strong>المجتمع</strong>
              <p>{number(data.posts)} منشور ظاهر</p>
            </div>
            {owner && (
              <button
                aria-label="فتح المجتمع"
                onClick={() => navigate("community")}
              >
                <ArrowLeft size={18} />
              </button>
            )}
          </div>
          <div className="privacy-callout">
            <ShieldCheck size={18} />
            <p>
              هذه الإحصاءات مجمّعة. لا تتضمن سجلات الدورة أو الحمل أو الرسائل
              الخاصة.
            </p>
          </div>
        </section>
      </div>
      <p className="muted small">
        آخر تحديث: {date(data.as_of)} · نشاط الاستخدام والاحتفاظ وتكاليف الذكاء
        الاصطناعي تتطلب ربط القياس لاحقاً.
      </p>
    </>
  );
}
function DataTable({
  section,
  rows,
  onSelect,
  acting,
  action,
}: {
  section: Section;
  rows: Row[];
  onSelect: (r: Row) => void;
  acting: boolean;
  action: (name: string, input: Row) => void;
  kind: string;
}) {
  const columns: Record<
    Exclude<Section, "overview" | "operations" | "analytics">,
    string[]
  > = {
    users: ["الحساب", "تاريخ التسجيل", "التأكيد", "التهيئة", "آخر دخول"],
    support: ["الموضوع", "الحساب", "الأولوية", "الحالة", "المتابعة"],
    community: ["المحتوى", "التصنيف", "التاريخ", "الظهور", "الإجراء"],
    content: ["العنوان", "المجال", "اللغة", "التاريخ", "التفاصيل"],
    knowledge: [
      "المعرّف والموضوع",
      "المجال",
      "النسخة",
      "حالة النشر",
      "التفاصيل",
    ],
    staff: ["البريد", "الدور", "الوصول", "تاريخ الإضافة"],
    audit: ["الإجراء", "المنفّذ", "الهدف", "التاريخ", "التفاصيل"],
  };
  return (
    <table>
      <thead>
        <tr>
          {columns[
            section as Exclude<Section, "overview" | "operations" | "analytics">
          ].map((c) => (
            <th key={c}>{c}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((r) => (
          <tr key={r.id || r.user_id}>
            {section === "users" ? (
              <>
                <td>
                  <strong dir="ltr">{r.email || r.phone || "حساب"}</strong>
                  <small className="mono">{r.id}</small>
                </td>
                <td>{date(r.created_at)}</td>
                <td>
                  <Badge tone={r.verified ? "green" : "rose"}>
                    {r.verified ? "مؤكد" : "غير مؤكد"}
                  </Badge>
                </td>
                <td>{r.onboarding_completed ? "مكتملة" : "لم تكتمل"}</td>
                <td>{date(r.last_sign_in_at)}</td>
              </>
            ) : section === "support" ? (
              <>
                <td>
                  <strong>{r.subject}</strong>
                  <small className="mono">{r.id.slice(0, 8)}</small>
                </td>
                <td>
                  <small className="mono">{r.user_id || "غير مرتبط"}</small>
                </td>
                <td>
                  <Badge tone={r.priority === "high" ? "rose" : "neutral"}>
                    {r.priority === "high" ? "عالية" : "عادية"}
                  </Badge>
                </td>
                <td>
                  <Badge>{statusNames[r.status]}</Badge>
                </td>
                <td>
                  <select
                    aria-label={`حالة الطلب ${r.subject}`}
                    value={r.status}
                    disabled={acting}
                    onChange={(e) =>
                      action("update_ticket", {
                        id: r.id,
                        status: e.target.value,
                      })
                    }
                  >
                    {["open", "in_progress", "resolved"].map((s) => (
                      <option value={s} key={s}>
                        {statusNames[s]}
                      </option>
                    ))}
                  </select>
                </td>
              </>
            ) : section === "community" ? (
              <>
                <td>
                  <strong className="truncate" dir="auto">
                    {r.title || r.content}
                  </strong>
                  <small>
                    {r.is_anonymous ? "منشور مجهول الهوية" : "محتوى عام"}
                  </small>
                </td>
                <td>{r.category || "تعليق"}</td>
                <td>{date(r.created_at)}</td>
                <td>
                  <Badge tone={r.is_hidden ? "rose" : "green"}>
                    {r.is_hidden ? "مخفي" : "ظاهر"}
                  </Badge>
                </td>
                <td>
                  <button className="text-button" onClick={() => onSelect(r)}>
                    مراجعة <ArrowLeft size={14} />
                  </button>
                </td>
              </>
            ) : section === "content" ? (
              <>
                <td>
                  <strong dir="auto">{r.title}</strong>
                  <small>مسودة غير منشورة</small>
                </td>
                <td>{r.domain}</td>
                <td>{r.language}</td>
                <td>{date(r.created_at)}</td>
                <td>
                  <button className="text-button" onClick={() => onSelect(r)}>
                    عرض
                  </button>
                </td>
              </>
            ) : section === "knowledge" ? (
              <>
                <td>
                  <strong className="mono">{r.knowledge_key}</strong>
                  <small dir="auto">{r.topic}</small>
                </td>
                <td>
                  <Badge>{r.domain}</Badge>
                  <small>{r.madhhab}</small>
                </td>
                <td>
                  {r.version} · {r.language}
                </td>
                <td>
                  <Badge>{statusNames[r.publication_state]}</Badge>
                  <small>
                    {r.reviews?.length
                      ? `${number(r.reviews.length)} قرار مراجعة`
                      : "بدون مراجعة عبر اللوحة"}
                  </small>
                </td>
                <td>
                  <button className="text-button" onClick={() => onSelect(r)}>
                    الأدلة والمراجعة <ArrowLeft size={14} />
                  </button>
                </td>
              </>
            ) : section === "staff" ? (
              <>
                <td dir="ltr">{r.email}</td>
                <td>{roleNames[r.role as Role]}</td>
                <td>
                  <Badge tone={r.active ? "green" : "rose"}>
                    {r.active ? "نشط" : "ملغى"}
                  </Badge>
                </td>
                <td>{date(r.created_at)}</td>
              </>
            ) : (
              <>
                <td>
                  <Badge>{r.action}</Badge>
                </td>
                <td className="mono">{r.actor_id}</td>
                <td className="mono">{r.target_id || "—"}</td>
                <td>{date(r.created_at)}</td>
                <td>
                  <code>{JSON.stringify(r.details)}</code>
                </td>
              </>
            )}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
function Modal({
  children,
  title,
  close,
}: {
  children: ReactNode;
  title: string;
  close: () => void;
}) {
  const ref = React.useRef<HTMLDivElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement;
    ref.current?.focus();
    const old = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = old;
      previous?.focus();
    };
  }, []);
  return (
    <div
      className="modal-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget) close();
      }}
      onKeyDown={(e) => {
        if (e.key === "Escape") close();
        if (e.key === "Tab") {
          const list = Array.from(
            ref.current!.querySelectorAll<HTMLElement>(
              'button:not(:disabled),input,textarea,select,[tabindex="0"]',
            ),
          );
          const first = list[0],
            last = list[list.length - 1];
          if (e.shiftKey && document.activeElement === first) {
            e.preventDefault();
            last?.focus();
          } else if (!e.shiftKey && document.activeElement === last) {
            e.preventDefault();
            first?.focus();
          }
        }
      }}
    >
      <div
        className="modal"
        ref={ref}
        tabIndex={-1}
        role="dialog"
        aria-modal="true"
        aria-label={title}
      >
        <header>
          <h2>{title}</h2>
          <button aria-label="إغلاق" onClick={close}>
            <X size={20} />
          </button>
        </header>
        {children}
      </div>
    </div>
  );
}
function Field({
  label,
  name,
  type = "text",
  required = true,
  minLength,
  maxLength,
}: {
  label: string;
  name: string;
  type?: string;
  required?: boolean;
  minLength?: number;
  maxLength?: number;
}) {
  return (
    <label>
      {label}
      <input
        name={name}
        type={type}
        required={required}
        minLength={minLength}
        maxLength={maxLength}
        dir={type === "email" ? "ltr" : "auto"}
      />
    </label>
  );
}
function Loading() {
  return (
    <div className="empty" role="status">
      <RefreshCw className="spinning" />
      <p>جارٍ تحميل البيانات…</p>
    </div>
  );
}
function Empty() {
  return (
    <div className="empty">
      <FileText size={30} />
      <h3>لا توجد سجلات لعرضها</h3>
      <p>ستظهر البيانات هنا عند توفرها، أو جرّب تغيير البحث.</p>
    </div>
  );
}
function DemoApp() {
  const [section, setSection] = useState<Section>("overview");
  return (
    <Dashboard
      role="owner"
      email="preview@niswah.invalid"
      section={section}
      setSection={setSection}
      logout={() => {
        window.location.href = "/";
      }}
    />
  );
}
createRoot(document.getElementById("root")!).render(
  isDemo ? <DemoApp /> : <App />,
);
