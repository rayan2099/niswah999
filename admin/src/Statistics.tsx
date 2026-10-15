import { Users, UserCheck, CalendarDays, LogIn } from "lucide-react";
export type StatisticsData = {
  total: number;
  new_today: number;
  new_7d: number;
  new_30d: number;
  verified: number;
  unverified: number;
  onboarded: number;
  incomplete: number;
  signed_in_7d: number;
  signed_in_30d: number;
  marital: { married: number; not_married: number; unknown: number };
  age: Record<
    "under_18" | "18_24" | "25_34" | "35_44" | "45_plus" | "unknown",
    number
  >;
  language: { ar: number; en: number; unknown: number };
};
const num = (n: number) => new Intl.NumberFormat("ar-SA").format(n);
export function percent(n: number, total: number) {
  return total > 0 ? Math.round((n / total) * 100) : 0;
}
function Breakdown({
  title,
  description,
  rows,
  total,
}: {
  title: string;
  description: string;
  rows: [string, number, string][];
  total: number;
}) {
  return (
    <section className="panel breakdown">
      <div className="panel-heading">
        <div>
          <h2>{title}</h2>
          <p>{description}</p>
        </div>
      </div>
      <div className="breakdown-rows">
        {rows.map(([label, value, color]) => (
          <div className="breakdown-row" key={label}>
            <div>
              <span>
                <i style={{ background: color }} />
                {label}
              </span>
              <strong>
                {num(value)}{" "}
                <small>
                  {total > 0 ? `${num(percent(value, total))}٪` : "—"}
                </small>
              </strong>
            </div>
            <div className="distribution-track">
              <span
                style={{
                  width: `${percent(value, total)}%`,
                  background: color,
                }}
              />
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
export default function Statistics({ data }: { data: StatisticsData }) {
  const cards = [
    [
      "تسجيلات اليوم",
      data.new_today,
      "من منتصف الليل بتوقيت الرياض",
      CalendarDays,
    ],
    ["تسجيلات آخر ٣٠ يوماً", data.new_30d, "نافذة متحركة: ٣٠ يوماً", Users],
    ["حسابات مؤكدة", data.verified, "بريد إلكتروني أو هاتف مؤكد", UserCheck],
    [
      "دخول خلال ٧ أيام",
      data.signed_in_7d,
      "آخر تسجيل دخول، وليس نشاط الاستخدام",
      LogIn,
    ],
  ] as const;
  return (
    <section className="audience-stats" aria-label="إحصاءات المستخدمات">
      <div className="stats-heading">
        <div>
          <h2>تعرّف على جمهور نسوة</h2>
          <p>
            توزيعات مجمّعة من {num(data.total)} حساب مسجل، باستثناء الجلسات
            المجهولة.
          </p>
        </div>
        <span className="badge">للمالك فقط</span>
      </div>
      <div className="metrics">
        {cards.map(([title, value, caption, Icon]) => (
          <article className="metric" key={title}>
            <div>
              <span>{title}</span>
              <Icon size={19} />
            </div>
            <strong>{num(value)}</strong>
            <small>{caption}</small>
          </article>
        ))}
      </div>
      <div className="stats-grid">
        <Breakdown
          title="الحالة الاجتماعية"
          description="حسب الإجابة المحفوظة في الحساب"
          total={data.total}
          rows={[
            ["متزوجات", data.marital.married, "#809a7d"],
            ["غير متزوجات", data.marital.not_married, "#bb8c9b"],
            ["لم تُحفظ إجابة", data.marital.unknown, "#c7cbbf"],
          ]}
        />
        <Breakdown
          title="الفئات العمرية"
          description="عمر تقريبي من سنة الميلاد المحفوظة"
          total={data.total}
          rows={[
            ["أقل من ١٨", data.age.under_18, "#b8c4a9"],
            ["١٨–٢٤", data.age["18_24"], "#8da583"],
            ["٢٥–٣٤", data.age["25_34"], "#607e66"],
            ["٣٥–٤٤", data.age["35_44"], "#b28e9b"],
            ["٤٥ فأكثر", data.age["45_plus"], "#c7adb7"],
            ["غير متوفر", data.age.unknown, "#d1d5c9"],
          ]}
        />
        <Breakdown
          title="لغة التطبيق"
          description="التفضيل المحفوظ، ولا يدل على الجنسية"
          total={data.total}
          rows={[
            ["العربية", data.language.ar, "#7f9c86"],
            ["English", data.language.en, "#b79aab"],
            ["غير متوفر", data.language.unknown, "#c7cbbf"],
          ]}
        />
        <Breakdown
          title="إكمال التهيئة"
          description="حالة onboarding المحفوظة في الحساب"
          total={data.total}
          rows={[
            ["مكتملة", data.onboarded, "#809a7d"],
            ["غير مكتملة أو بلا ملف", data.incomplete, "#c6ab91"],
          ]}
        />
        <Breakdown
          title="تأكيد الحساب"
          description="تأكيد البريد الإلكتروني أو رقم الهاتف"
          total={data.total}
          rows={[
            ["مؤكد", data.verified, "#809a7d"],
            ["لم يُؤكّد", data.unverified, "#c6ab91"],
          ]}
        />
        <section className="panel breakdown">
          <div className="panel-heading">
            <div>
              <h2>تسجيل الدخول مؤخراً</h2>
              <p>حسابات لديها آخر تسجيل دخول في الفترة</p>
            </div>
          </div>
          <div className="signin-summary">
            <div>
              <strong>{num(data.signed_in_7d)}</strong>
              <span>آخر ٧ أيام</span>
            </div>
            <div>
              <strong>{num(data.signed_in_30d)}</strong>
              <span>آخر ٣٠ يوماً</span>
            </div>
          </div>
          <p className="stats-note">
            الفترتان متداخلتان. هذه الأرقام لا تقيس المستخدمات النشطات يومياً أو
            مدة استخدام التطبيق.
          </p>
        </section>
      </div>
      <p className="stats-note">
        الحالة الاجتماعية: «غير متزوجة» تشمل من أجابت بلا؛ لا نفترض أنها عزباء
        أو مطلقة أو أرملة. الحسابات القديمة أو الإجابات التي لم تصل للخادم تظهر
        ضمن «لم تُحفظ إجابة». النسب من إجمالي الحسابات، وقد يختلف مجموع النسب عن
        ١٠٠٪ بسبب التقريب.
      </p>
    </section>
  );
}
