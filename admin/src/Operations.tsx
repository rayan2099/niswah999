import {
  Activity,
  AlertTriangle,
  ArrowLeft,
  Clock3,
  Plus,
  ShieldCheck,
} from "lucide-react";
import type { FormEvent } from "react";
import type { Section } from "./api";
type Row = Record<string, any>;
const n = (v: unknown) =>
  v === null || v === undefined
    ? "—"
    : new Intl.NumberFormat("ar-SA").format(Number(v));
const date = (v: string) =>
  v
    ? new Date(v).toLocaleString("ar-SA", {
        dateStyle: "medium",
        timeStyle: "short",
        timeZone: "Asia/Riyadh",
      })
    : "لم تصل بيانات";
const advisorNames: Record<string, string> = {
  "ai-assistant-chat": "مساعدة نسوة",
  "dr-niswah-chat": "طبيبة نسوة",
  "fiqh-advisor-chat": "المستشارة الفقهية",
  "dream-interpreter-chat": "تفسير الأحلام",
};
const steps: Record<string, string> = {
  started: "بدء التهيئة",
  madhhab: "اختيار المذهب",
  marital: "الحالة الاجتماعية",
  location: "إعداد الموقع",
  last_period: "آخر دورة",
  period_length: "مدة الحيض",
  privacy: "الخصوصية",
  welcome: "صفحة الترحيب",
  completed: "حفظ إكمال التهيئة",
};
const stateNames: Record<string, string> = {
  receiving: "تصل بيانات",
  not_connected: "غير متصل / لا بيانات",
  stale: "لا بيانات حديثة",
};
const statusNames: Record<string, string> = {
  open: "مفتوح",
  acknowledged: "قيد المتابعة",
  resolved: "تم الحل",
};
export function Attention({
  data,
  navigate,
}: {
  data: Row;
  navigate: (section: Section) => void;
}) {
  const alerts: Row[] = data.alerts || [];
  return (
    <section className="panel attention-panel">
      <div className="panel-heading">
        <div>
          <h2>
            <AlertTriangle size={18} />
            يحتاج انتباهك
          </h2>
          <p>إشارات فعلية، ومتابعات لها مسؤول وموعد.</p>
        </div>
        <button className="text-button" onClick={() => navigate("operations")}>
          مركز العمليات <ArrowLeft size={15} />
        </button>
      </div>
      <div className="attention-summary">
        <span>
          <strong>{n(data.open_incidents)}</strong> متابعة مفتوحة
        </span>
        <span className={data.overdue_incidents ? "overdue" : ""}>
          <Clock3 size={15} />
          <strong>{n(data.overdue_incidents)}</strong> تجاوزت الموعد
        </span>
      </div>
      {alerts.length ? (
        <div className="attention-list">
          {alerts.slice(0, 4).map((a) => (
            <div key={a.key}>
              <span className={`signal-dot ${a.severity}`} />
              <span>{a.title}</span>
              <strong>{n(a.count)}</strong>
            </div>
          ))}
        </div>
      ) : (
        <p className="operations-note">
          لا توجد إشارات تستوفي قواعد التنبيه الحالية. هذا لا يؤكد سلامة مصادر
          القياس غير المتصلة.
        </p>
      )}
    </section>
  );
}
export default function Operations({
  data,
  action,
  busy,
  navigate,
  owner,
}: {
  data: Row;
  action: (name: string, input: Row) => void;
  busy: boolean;
  navigate: (s: Section) => void;
  owner: boolean;
}) {
  function create(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const f = Object.fromEntries(new FormData(e.currentTarget));
    action("create_incident", { ...f, due_at: `${f.due_date}T23:59:59+03:00` });
  }
  const funnel = data.funnel;
  const baseline =
    Number(funnel.steps.find((s: Row) => s.step === "started")?.reached) || 0;
  return (
    <div className="operations">
      <Attention
        data={{
          alerts: data.alerts,
          open_incidents: data.open_incidents,
          overdue_incidents: data.overdue_incidents,
        }}
        navigate={navigate}
      />
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>الإشارات والمتابعة</h2>
            <p>كل إشارة قابلة للتحويل إلى متابعة مستقلة.</p>
          </div>
        </div>
        {data.alerts.length ? (
          data.alerts.map((a: Row) => (
            <div className="signal-row" key={a.key}>
              <AlertTriangle size={18} />
              <div>
                <strong>{a.title}</strong>
                <small>
                  {a.key === "ai_errors"
                    ? "٥ إخفاقات نهائية أو أكثر خلال آخر ساعة"
                    : a.key === "telemetry_stale"
                      ? "قد يعني غياب الاستخدام أو انقطاع القياس؛ لا يعني بالضرورة تعطل الخدمة"
                      : a.key === "review_backlog"
                        ? "غياب قرار داخل هذه اللوحة لا ينفي وجود مراجعة خارجها"
                        : "طلبات بأولوية عالية أو مفتوحة أكثر من ٤٨ ساعة"}
                </small>
              </div>
              <span className="badge">{n(a.count)}</span>
              {owner && a.section !== "operations" && (
                <button
                  className="text-button"
                  onClick={() => navigate(a.section)}
                >
                  فتح القسم
                </button>
              )}
              <button
                className="button"
                disabled={
                  busy ||
                  data.incidents.some(
                    (i: Row) => i.source === a.key && i.status !== "resolved",
                  )
                }
                onClick={() =>
                  action("create_incident", { title: a.title, source: a.key })
                }
              >
                <Plus size={14} />
                فتح متابعة
              </button>
            </div>
          ))
        ) : (
          <p className="operations-note">لا توجد إشارات حالية.</p>
        )}
        <details className="new-incident">
          <summary>
            <Plus size={16} />
            متابعة يدوية جديدة
          </summary>
          <form onSubmit={create} className="incident-create">
            <label>
              عنوان مختصر
              <input
                name="title"
                required
                minLength={5}
                maxLength={160}
                placeholder="مثلاً: التحقق من فشل وصول رسائل التأكيد"
              />
            </label>
            <Assignee people={data.assignees} />
            <label>
              الموعد — نهاية اليوم بتوقيت الرياض
              <input name="due_date" type="date" required />
            </label>
            <button className="button primary" disabled={busy}>
              حفظ المتابعة
            </button>
          </form>
          <p className="operations-note">
            اكتب عنواناً تشغيلياً، دون معلومات صحية أو محادثات خاصة.
          </p>
        </details>
      </section>
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>سجل المتابعات</h2>
            <p>أول ١٠٠ سجل، المفتوح أولاً ثم حسب الموعد.</p>
          </div>
        </div>
        {data.incidents.length ? (
          <div className="incident-list">
            {data.incidents.map((i: Row) => (
              <details className="incident" key={i.id}>
                <summary>
                  <div>
                    <strong>{i.title}</strong>
                    <small>
                      {i.assignee_email || "غير مسند"} · الموعد:{" "}
                      {date(i.due_at)}
                    </small>
                  </div>
                  <span
                    className={`badge ${i.status !== "resolved" && new Date(i.due_at) < new Date() ? "rose" : ""}`}
                  >
                    {statusNames[i.status]}
                  </span>
                </summary>
                <form
                  className="incident-edit"
                  onSubmit={(e) => {
                    e.preventDefault();
                    const f = Object.fromEntries(new FormData(e.currentTarget));
                    action("update_incident", {
                      ...f,
                      id: i.id,
                      due_at: `${f.due_date}T23:59:59+03:00`,
                    });
                  }}
                >
                  <Assignee
                    people={data.assignees}
                    value={i.assigned_to || ""}
                  />
                  <label>
                    الحالة
                    <select name="status" defaultValue={i.status}>
                      {Object.entries(statusNames).map(([key, label]) => (
                        <option key={key} value={key}>
                          {label}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label>
                    الموعد بتوقيت الرياض
                    <input
                      name="due_date"
                      type="date"
                      required
                      defaultValue={new Date(i.due_at).toLocaleDateString(
                        "en-CA",
                        { timeZone: "Asia/Riyadh" },
                      )}
                    />
                  </label>
                  <button className="button primary" disabled={busy}>
                    حفظ التحديث
                  </button>
                </form>
              </details>
            ))}
          </div>
        ) : (
          <p className="operations-note">لا توجد متابعات مسجلة بعد.</p>
        )}
      </section>
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>مسار التهيئة</h2>
            <p>وصول إلى الخطوات منذ بدء القياس · {date(funnel.since)}</p>
          </div>
          <span className="badge">{stateNames[funnel.state]}</span>
        </div>
        {funnel.state === "not_connected" ? (
          <div className="disconnected">
            <Activity />
            <h3>تتبّع الخطوات لم يرسل بيانات بعد</h3>
            <p>
              يبدأ القياس بعد تثبيت نسخة التطبيق التي تتضمن التتبّع. لا نستنتج
              خطوات الحسابات القديمة من حالة الإكمال.
            </p>
          </div>
        ) : (
          <>
            <div className="funnel">
              {funnel.steps.map((s: Row) => {
                const pct =
                  baseline > 0 ? Math.round((s.reached / baseline) * 100) : 0;
                return (
                  <div className="funnel-row" key={s.step}>
                    <span>{steps[s.step]}</span>
                    <div className="distribution-track">
                      <span
                        style={{ width: `${pct}%`, background: "#90a585" }}
                      />
                    </div>
                    <strong>{n(s.reached)}</strong>
                    <small>{n(pct)}٪</small>
                  </div>
                );
              })}
            </div>
            <p className="operations-note">
              كل حساب يُحسب مرة واحدة لكل خطوة. هذه أحداث وصول للخطوات، ولا تثبت
              اختيار إجابة أو التخلي عن التسجيل. انقطاع الشبكة واستئناف التهيئة
              قد يسببان فجوات.
            </p>
          </>
        )}
      </section>
      <section className="panel">
        <div className="panel-heading">
          <div>
            <h2>مراقبة الذكاء الاصطناعي</h2>
            <p>آخر ٧ أيام · مخرجات تشغيلية بدون نص المحادثات.</p>
          </div>
          <span className="badge">التكاليف غير مربوطة بالفوترة</span>
        </div>
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>المساعد / آخر حدث</th>
                <th>القياس</th>
                <th>طلبات HTTP</th>
                <th>أخطاء الخادم</th>
                <th>تقييد المعدّل</th>
                <th>طلبات مرفوضة</th>
                <th>P95 بالمللي ثانية</th>
                <th>محاولات التوليد / إخفاقات</th>
                <th>رموز الإدخال / الإخراج</th>
              </tr>
            </thead>
            <tbody>
              {data.ai.map((a: Row) => (
                <tr key={a.advisor}>
                  <td>
                    <strong>{advisorNames[a.advisor]}</strong>
                    <small>{date(a.last_seen_at)}</small>
                  </td>
                  <td>
                    <span
                      className={`badge ${a.state === "stale" ? "rose" : ""}`}
                    >
                      {stateNames[a.state]}
                    </span>
                  </td>
                  <td>{n(a.requests)}</td>
                  <td>{n(a.server_errors)}</td>
                  <td>{n(a.rate_limited)}</td>
                  <td>{n(a.rejected)}</td>
                  <td>{n(a.p95_ms)}</td>
                  <td>
                    {n(a.model_calls)} / {n(a.model_failures)}
                  </td>
                  <td>
                    {n(a.input_tokens)} / {n(a.output_tokens)}
                    {a.usage_missing > 0 && (
                      <small>
                        {n(a.usage_missing)} عملية بلا بيانات رموز مكتملة
                      </small>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="operations-note">
          التوليد مستقل عن حالة HTTP: قد يرجع المساعد رسالة بديلة بنجاح HTTP رغم
          فشل النموذج. الرموز تخص الرد النهائي الناجح فقط، ولا تشمل تكلفة
          المحاولات الفاشلة أو التسعير أو الفاتورة. «—» تعني عدم وصول قياس لهذه
          الفترة، ولا تعني صفراً. لا تقيس هذه الشاشة دقة الإجابات أو جودة
          الاستشهادات.
        </p>
      </section>
      <section className="panel">
        <div className="panel-heading">
          <h2>
            <ShieldCheck size={17} />
            مصادر تحتاج ربطاً لاحقاً
          </h2>
        </div>
        <div className="integration-grid">
          {[
            "أخطاء التطبيق وتقارير الأعطال",
            "تسليم البريد ورموز التحقق",
            "تكلفة AI والفوترة الفعلية",
            "تقييم جودة الإجابات والاستشهادات",
          ].map((name) => (
            <div key={name}>
              <span>{name}</span>
              <span className="badge">غير متصل</span>
            </div>
          ))}
        </div>
      </section>
      <p className="operations-note">
        آخر تحديث: {date(data.as_of)} · المتابعات داخل لوحة الإدارة؛ إرسال
        تنبيهات خارجية غير مفعّل.
      </p>
    </div>
  );
}
function Assignee({ people, value = "" }: { people: Row[]; value?: string }) {
  return (
    <label>
      المسؤول
      <select name="assigned_to" defaultValue={value}>
        <option value="">غير مسند</option>
        {people.map((p) => (
          <option key={p.user_id} value={p.user_id}>
            {p.email}
          </option>
        ))}
      </select>
    </label>
  );
}
