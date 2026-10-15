import { useState } from "react";
import { Heart, Moon, Sparkles, Smile, Globe2, Activity } from "lucide-react";
import { Breakdown, percent } from "./Statistics";
export type DailyWellbeing = {
  day: string;
  reports: number;
  happy: number;
  down: number;
  neutral: number;
  low_energy: number;
  poor_sleep: number;
  sleepy: number;
  sleepy_reports: number;
  mood_reports: number;
  mood_avg: number | null;
  energy_avg: number | null;
  sleep_avg: number | null;
};
export type AudienceData = {
  as_of: string;
  date: string;
  total: number;
  countries: {
    rows: { country: string; users: number }[];
    other: number;
    unknown: number;
  };
  madhhab: Record<
    "hanafi" | "maliki" | "shafii" | "hanbali" | "unknown" | "unset",
    number
  >;
  cycle: Record<
    | "fresh"
    | "missing"
    | "bleeding"
    | "no_bleeding"
    | "bleeding_unknown"
    | "haid"
    | "tahara"
    | "needs_advisory"
    | "madhhab_unresolved"
    | "unknown"
    | "ovulation"
    | "pre_period"
    | "prediction_coverage",
    number
  >;
  today: DailyWellbeing;
  wellbeing_users_7d: number;
  wellbeing_users_30d: number;
  trend: DailyWellbeing[];
};
const n = (value: number) =>
  new Intl.NumberFormat("ar-SA", { maximumFractionDigits: 2 }).format(value);
export function countryLabel(value: string) {
  if (/^[A-Z]{2}$/.test(value)) {
    try {
      return (
        new Intl.DisplayNames(["ar"], { type: "region" }).of(value) || value
      );
    } catch {
      return value;
    }
  }
  return value;
}
const colors = [
  "#77957d",
  "#ba8496",
  "#baa17d",
  "#719da5",
  "#a2ab80",
  "#d0d4cb",
];
function Metric({
  title,
  value,
  caption,
  icon: Icon,
  tone = "sage",
}: {
  title: string;
  value: number;
  caption: string;
  icon: typeof Heart;
  tone?: string;
}) {
  return (
    <article className={`metric wellness-metric ${tone}`}>
      <div>
        <span>{title}</span>
        <Icon size={20} />
      </div>
      <strong>{n(value)}</strong>
      <small>{caption}</small>
    </article>
  );
}
export function Trend({ rows }: { rows: DailyWellbeing[] }) {
  const series = [
    ["mood_avg", "المزاج", colors[0]],
    ["energy_avg", "الطاقة", colors[1]],
    ["sleep_avg", "النوم", colors[3]],
  ] as const;
  const x = (i: number) => 38 + (i * 684) / Math.max(rows.length - 1, 1);
  const y = (v: number) => 182 - (v - 1) * 36;
  return (
    <div className="wellbeing-chart">
      <div className="chart-legend">
        {series.map(([key, label, color]) => (
          <span key={key}>
            <i style={{ background: color }} />
            {label}
          </span>
        ))}
      </div>
      <svg
        viewBox="0 0 750 218"
        role="img"
        aria-label="متوسط المزاج والطاقة والنوم من ١ إلى ٥؛ الفراغ يعني عدم توفر بيانات"
        style={{ direction: "ltr" }}
      >
        {[1, 2, 3, 4, 5].map((v) => (
          <g key={v}>
            <line x1="38" x2="722" y1={y(v)} y2={y(v)} stroke="#e5e8df" />
            <text x="20" y={y(v) + 5} textAnchor="middle">
              {n(v)}
            </text>
          </g>
        ))}
        {series.map(([key, label, color]) => (
          <g key={key}>
            {rows.map((row, i) => {
              const value = row[key],
                previous = rows[i - 1]?.[key];
              return value === null ? null : (
                <g key={row.day}>
                  {i > 0 && previous !== null && previous !== undefined && (
                    <line
                      x1={x(i - 1)}
                      y1={y(previous)}
                      x2={x(i)}
                      y2={y(value)}
                      stroke={color}
                      strokeWidth="2.5"
                    />
                  )}
                  <circle cx={x(i)} cy={y(value)} r="3.3" fill={color}>
                    <title>{`${row.day} • ${label}: ${n(value)} • ${n(row.reports)} تسجيلات`}</title>
                  </circle>
                </g>
              );
            })}
          </g>
        ))}
        {[0, rows.length - 1]
          .filter((v, i, a) => a.indexOf(v) === i && v >= 0)
          .map((i) => (
            <text
              key={i}
              x={x(i)}
              y="210"
              textAnchor={i === 0 ? "start" : "end"}
            >
              {rows[i].day.slice(5)}
            </text>
          ))}
      </svg>
      {!rows.some((row) => row.reports > 0) && (
        <p className="chart-empty">لم تصل تسجيلات عافية لهذه الفترة بعد</p>
      )}
    </div>
  );
}
export default function Audience({ data: d }: { data: AudienceData }) {
  const [days, setDays] = useState<7 | 30>(30);
  const t = d.today,
    c = d.cycle,
    rows = d.trend.slice(-days);
  const reportPct = percent(t.reports, d.total);
  const countries: [string, number, string][] = d.countries.rows.map((r, i) => [
    countryLabel(r.country),
    r.users,
    colors[i % 5],
  ]);
  if (d.countries.other)
    countries.push(["بلدان أخرى", d.countries.other, colors[4]]);
  countries.push(["غير محفوظ", d.countries.unknown, colors[5]]);
  const date = new Intl.DateTimeFormat("ar-SA", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Riyadh",
  }).format(new Date(d.as_of));
  return (
    <div className="audience-stats audience-view">
      <section className="audience-hero">
        <div>
          <span className="eyebrow">NISWAH / AUDIENCE & WELLBEING</span>
          <h2>افهمي نسوة، يوماً بعد يوم</h2>
          <p>
            مؤشرات مجمّعة من {n(d.total)} حساب مسجل. آخر تحديث: {date} بتوقيت
            الرياض.
          </p>
          <span className="badge">للمالك فقط · بدون سجلات فردية</span>
        </div>
        <div
          className="coverage-ring"
          style={{
            background: `conic-gradient(#819b7c ${reportPct}%, #e6e9df 0)`,
          }}
        >
          <div>
            <strong>{n(reportPct)}٪</strong>
            <span>سجّلن العافية اليوم</span>
            <small>
              {n(t.reports)} من {n(d.total)}
            </small>
          </div>
        </div>
      </section>
      <div className="stats-heading">
        <div>
          <h2>كيف يشعرن اليوم؟</h2>
          <p>
            تاريخ التسجيل {d.date} • إجابات يومية وليست مراقبة لحظية. نفس
            المستخدمة قد تظهر في أكثر من مؤشر.
          </p>
        </div>
      </div>
      <div className="metrics">
        <Metric
          title="مزاج جيد"
          value={t.happy}
          caption="تقييم المزاج ٤–٥ من ٥"
          icon={Smile}
        />
        <Metric
          title="مزاج منخفض"
          value={t.down}
          caption="تقييم المزاج ١–٢ من ٥، وليس تشخيصاً"
          icon={Heart}
          tone="rose"
        />
        <Metric
          title="يشعرن بالنعاس"
          value={t.sleepy}
          caption={`إجابة صريحة من ${n(t.sleepy_reports)} مشاركة في سؤال النعاس`}
          icon={Moon}
        />
        <Metric
          title="طاقة منخفضة"
          value={t.low_energy}
          caption="تقييم الطاقة ١–٢ من ٥"
          icon={Sparkles}
          tone="sand"
        />
      </div>
      <div className="stats-grid">
        <Breakdown
          title="توزيع المزاج اليوم"
          description={`من إجمالي الحسابات • ${n(t.mood_reports)} إجابة صالحة`}
          total={d.total}
          rows={[
            ["جيد · ٤–٥", t.happy, colors[0]],
            ["متوسط · ٣", t.neutral, colors[2]],
            ["منخفض · ١–٢", t.down, colors[1]],
            ["بلا إجابة صالحة اليوم", d.total - t.mood_reports, colors[5]],
          ]}
        />
        <section className="panel breakdown">
          <div className="panel-heading">
            <div>
              <h2>المشاركة وجودة النوم</h2>
              <p>عدد المستخدمات الفريدات، وليست عدد مرات فتح التطبيق</p>
            </div>
            <Activity size={20} />
          </div>
          <div className="signin-summary">
            <div>
              <strong>{n(d.wellbeing_users_7d)}</strong>
              <span>سجّلن خلال ٧ أيام</span>
            </div>
            <div>
              <strong>{n(d.wellbeing_users_30d)}</strong>
              <span>سجّلن خلال ٣٠ يوماً</span>
            </div>
          </div>
          <p className="stats-note">
            {n(t.poor_sleep)} قيّمن النوم اليوم بـ١–٢ من ٥. النعاس وجودة النوم
            والطاقة أسئلة مستقلة. {n(d.total - t.reports)} حساب بلا تسجيل عافية
            لهذا التاريخ.
          </p>
        </section>
      </div>
      <section className="panel wellness-trend">
        <div className="panel-heading">
          <div>
            <h2>اتجاهات العافية</h2>
            <p>
              متوسط الإجابات من ١ إلى ٥ • الفراغ في الرسم يعني عدم توفر بيانات
            </p>
          </div>
          <div className="period-switch" aria-label="فترة الرسم">
            {([7, 30] as const).map((v) => (
              <button
                key={v}
                aria-pressed={days === v}
                onClick={() => setDays(v)}
              >
                {n(v)} أيام
              </button>
            ))}
          </div>
        </div>
        <Trend rows={rows} />
        <p className="stats-note">
          تغيّر المتوسط قد يعكس تغيّر المشاركات. التسجيلات مؤرخة حسب جهاز
          المستخدمة؛ المقارنة بتاريخ الرياض. لا يُستدل منها على علاقة سببية.
        </p>
        <details>
          <summary>الأرقام اليومية وحجم العينة</summary>
          <div className="table-scroll">
            <table>
              <thead>
                <tr>
                  <th>التاريخ</th>
                  <th>التسجيلات</th>
                  <th>المزاج /٥</th>
                  <th>الطاقة /٥</th>
                  <th>النوم /٥</th>
                </tr>
              </thead>
              <tbody>
                {[...rows].reverse().map((r) => (
                  <tr key={r.day}>
                    <td>{r.day}</td>
                    <td>{n(r.reports)}</td>
                    {(["mood_avg", "energy_avg", "sleep_avg"] as const).map(
                      (k) => (
                        <td key={k}>{r[k] === null ? "—" : n(r[k])}</td>
                      ),
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </details>
      </section>
      <div className="stats-heading">
        <div>
          <h2>الدورة والحالة الفقهية</h2>
          <p>
            آخر ملخص محسوب في التطبيق خلال ٢٤ ساعة: {n(c.fresh)} حساب. بلا ملخص
            حديث: {n(c.missing)}.
          </p>
        </div>
        <span className="badge">ملاحظة مسجلة ≠ توقّع</span>
      </div>
      <div className="stats-grid">
        <Breakdown
          title="الحالة المعروضة في التطبيق"
          description="حالة مبنية على سجل اليوم؛ تصنيف المحرك وليس فتوى معتمدة"
          total={d.total}
          rows={[
            ["حيض", c.haid, colors[1]],
            ["طهارة", c.tahara, colors[0]],
            ["تحتاج استشارة", c.needs_advisory, colors[2]],
            ["المذهب غير محدد مع نزف", c.madhhab_unresolved, colors[3]],
            ["غير معروفة أو غير حديثة", c.unknown, colors[5]],
          ]}
        />
        <Breakdown
          title="النزف المُسجّل"
          description="سجل مؤرخ بيوم فتح الملخص، وصل خلال ٢٤ ساعة؛ النزف لا يساوي دائماً الحيض"
          total={d.total}
          rows={[
            ["نزف مسجل", c.bleeding, colors[1]],
            ["عدم نزف مسجل", c.no_bleeding, colors[0]],
            ["بلا ملاحظة حديثة", c.bleeding_unknown, colors[5]],
          ]}
        />
      </div>
      <div className="prediction-strip">
        <div>
          <span className="eyebrow">تقديرات وليست حالات مؤكدة</span>
          <h3>التبويض وما قبل الحيض</h3>
          <p>
            حسب محرك التوقعات الحالي. تغطية التوقع: {n(c.prediction_coverage)}{" "}
            من {n(d.total)} حساب؛ غير المتوفر{" "}
            {n(d.total - c.prediction_coverage)}.
          </p>
        </div>
        <div>
          <strong>{n(c.ovulation)}</strong>
          <span>يوم التبويض المتوقع</span>
        </div>
        <div>
          <strong>{n(c.pre_period)}</strong>
          <span>حيض متوقع خلال ١–٧ أيام</span>
        </div>
      </div>
      <p className="stats-note">
        التوقع منفصل عن الطهارة والحيض وقد يتداخل معهما. لا نستخدم افتراضات «٢٨
        يوماً» أو «طهارة» لملء البيانات الناقصة. تحديث الملخص يتطلب فتح التطبيق
        وإرسال البيانات بنجاح.
      </p>
      <div className="stats-heading">
        <div>
          <h2>من تستخدم نسوة؟</h2>
          <p>
            توزيعات من جميع الحسابات المسجلة • الحسابات المجهولة مستبعدة من جميع
            أرقام هذه الصفحة
          </p>
        </div>
        <Globe2 size={22} />
      </div>
      <div className="stats-grid">
        <Breakdown
          title="البلدان المحفوظة"
          description="بلد إعداد الصلاة المختار؛ لا يدل على الجنسية أو الإقامة. أعلى ١٢ بلداً"
          total={d.total}
          rows={countries}
        />
        <Breakdown
          title="المذهب المختار"
          description="الاختيار الصريح فقط؛ لا نستخدم القيمة الافتراضية القديمة"
          total={d.total}
          rows={[
            ["حنفي", d.madhhab.hanafi, colors[0]],
            ["مالكي", d.madhhab.maliki, colors[2]],
            ["شافعي", d.madhhab.shafii, colors[3]],
            ["حنبلي", d.madhhab.hanbali, colors[1]],
            ["اختارت: لا أعرف", d.madhhab.unknown, colors[4]],
            ["لم يُحفظ اختيار صالح", d.madhhab.unset, colors[5]],
          ]}
        />
      </div>
      <section className="panel insight-guide">
        <h2>استخدمي الأرقام لاتخاذ قرارات أوضح</h2>
        <ul>
          <li>البلدان واللغة: حددي أولويات الترجمة وأوقات الدعم.</li>
          <li>
            توزيع المذاهب: رتبي مراجعة المحتوى الفقهي وفق احتياجات الجمهور.
          </li>
          <li>
            العافية والمشاركة: راقبي الاتجاه وحجم العينة معاً لتقييم تجربة
            التسجيل.
          </li>
          <li>
            تغطية الدورة: راجعي البيانات الناقصة قبل تفسير أي تغيّر في الحالات
            أو التوقعات.
          </li>
        </ul>
        <p className="stats-note">
          تعرض الصفحة أعداداً مجمّعة فقط؛ لا تتضمن أسماء أو ملاحظات صحية أو
          محادثات خاصة أو إحداثيات.
        </p>
      </section>
    </div>
  );
}
