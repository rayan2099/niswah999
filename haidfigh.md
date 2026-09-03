# Niswah Fiqh Engine: Multi-Madhhab Rule Specification
> **Status:** Draft Implementation Spec (Pending Human Scholar Review)  
> **Scope:** Defines the absolute rule bounds for Menstruation (الحيض), Purity (الطهر), and Istihadah across the four primary schools of jurisprudence (Madhhabs).

---

## 🏛️ Comprehensive Four-Madhhab Fiqh Engine Specifications Matrix

### 1. Hanafi School (المذهب الحنفي)
* **Minimum Duration of Haid (أقل الحيض):** 3 full days and 3 nights (72 hours). Any continuous or combined bleeding less than this is classified as *Istihadah* (or *fasid* blood), meaning the woman does not stop praying or fasting.
* **Maximum Duration of Haid (أكثر الحيض):** 10 full days and 10 nights (240 hours). Any blood exceeding 10 days shifts into *Istihadah*.
* **Minimum Period of Purity (أقل الطهر):** 15 days clean between two distinct menstrual cycles. If bleeding restarts before 15 days of absolute purity elapse, it is treated as continuing non-menstrual bleeding.
* **Maximum Period of Purity (أكثر الطهر):** Unbounded (no maximum limit); a woman may remain in a state of purity for months or years.
* **Intermittent Blood / Talfiq (تلفيق الدم):** If a woman bleeds for a day, stops for a day, and bleeds again within the 10-day window, the intermediate clean days are bridged and factored into the total calculation.

### 2. Maliki School (المذهب المالكي)
* **Minimum Duration of Haid (أقل الحيض):** No fixed minimum limit in time. Even a single drop or momentary instance of blood seen with intent or normal pattern (*'Adah*) can constitute Haid.
* **Maximum Duration of Haid (أكثر الحيض):** 15 days. If bleeding passes 15 days, she transitions into the rulings of a *Mutahayyira* (perplexed) or *Mustahadah* based on her established habit.
* **Minimum Period of Purity (أقل الطهر):** 15 days of absolute purity separating two menstrual cycles.
* **Core Principle:** Heavily relies on personal habit (*'Adah*) and distinguishing between a beginner (*Mubtada'ah*) and a woman with an established routine (*Mu'tadah*).

### 3. Shafi'i School (المذهب الشافعي)
* **Minimum Duration of Haid (أقل الحيض):** 1 day and 1 night (24 cumulative hours). It does not have to be continuous, provided the actual hours of bleeding within a 15-day rolling frame total 24 hours.
* **Maximum Duration of Haid (أكثر الحيض):** 15 days and nights. Total combined bleeding and spotting within a 15-day window cannot exceed this hard ceiling.
* **Minimum Period of Purity (أقل الطهر):** 15 days.
* **Tamyiz Rule (التمييز):** When irregular bleeding exceeds 15 days, the woman relies on distinguishing strong, dark, thick blood (Haid) from light, thin blood (Istihadah), provided the strong blood respects the minimum and maximum boundaries.

### 4. Hanbali School (المذهب الحنبلي)
* **Minimum Duration of Haid (أقل الحيض):** 1 day and 1 night (24 hours).
* **Maximum Duration of Haid (أكثر الحيض):** 15 days.
* **Minimum Period of Purity (أقل الطهر):** 15 days.
* **Habit vs. Beginner Rule:** A woman with a known pattern follows her established days. A beginner (*Mubtada'ah*) without a fixed habit defaults to standard duration averages (typically 6 or 7 days, or utilizes blood characteristics via *Tamyiz*) until a firm personal habit is established.

---

## 💻 Engine Implementation Directives

1. **Pure Factual Arithmetic:** 
   - Derive cycle day and length strictly from actual logged Haid-start dates per instance.
   - Strip out all 28-day assumptions, hardcoded fallbacks, and dummy placeholders.
   - When history is insufficient (fewer than 2 logged cycles to establish a baseline), display an explicit *"Log your cycle to see your day"* UI state.

2. **Dynamic Madhhab Selection:**
   - The user selects their preferred school in their profile/settings.
   - The engine evaluates rules based dynamically on the user's selected school boundaries (e.g., enforcing Hanafi's 3–10 day limits vs. Shafi'i/Maliki/Hanbali's 1–15 day limits with 24-hour minimums).