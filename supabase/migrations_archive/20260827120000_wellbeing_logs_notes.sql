-- Adds an optional free-text "ملاحظات" (notes) field to the daily
-- wellbeing check-in, alongside mood/energy/sleep. Purely additive —
-- nullable, no default beyond NULL, so existing rows and every other
-- reader of this table are unaffected.

ALTER TABLE wellbeing_logs ADD COLUMN IF NOT EXISTS notes TEXT;
