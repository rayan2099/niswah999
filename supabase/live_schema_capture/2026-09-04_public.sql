


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."madhhab_type" AS ENUM (
    'hanafi',
    'maliki',
    'shafii',
    'hanbali'
);


ALTER TYPE "public"."madhhab_type" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_access_user"("row_user_id" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  select auth.uid() = row_user_id or public.is_admin();
$$;


ALTER FUNCTION "public"."can_access_user"("row_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_user_profile"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.users (
    id,
    email_hash,
    display_name,
    madhhab,
    language,
    onboarding_completed,
    premium_status,
    created_at,
    updated_at
  )
  values (
    new.id,
    md5(coalesce(new.email, 'anonymous')),
    coalesce(new.raw_user_meta_data ->> 'display_name', new.raw_user_meta_data ->> 'full_name', 'Sister'),
    'HANBALI',
    'ar',
    false,
    true,
    now(),
    now()
  )
  on conflict (id) do nothing;

  return new;
end;
$$;


ALTER FUNCTION "public"."create_user_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_my_account"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;


ALTER FUNCTION "public"."delete_my_account"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$ BEGIN     INSERT INTO public.profiles (id, full_name, selected_madhhab)     VALUES (         NEW.id,          NEW.raw_user_meta_data->>'full_name',          COALESCE((NEW.raw_user_meta_data->>'selected_madhhab')::public.madhhab_type, 'shafii')     );     RETURN NEW; END; $$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists (
    select 1 from public.users
    where id = auth.uid() and role = 'admin'
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_conversation_participant"("conversation" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM private_conversations pc
    WHERE pc.id = conversation
      AND (pc.participant_one = auth.uid() OR pc.participant_two = auth.uid())
  );
$$;


ALTER FUNCTION "public"."is_conversation_participant"("conversation" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."touch_private_conversation"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  UPDATE private_conversations
  SET updated_at = now()
  WHERE id = NEW.conversation_id;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."touch_private_conversation"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."adah_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "cycle_number" integer DEFAULT 0 NOT NULL,
    "haid_start" timestamp with time zone NOT NULL,
    "haid_end" timestamp with time zone,
    "haid_duration_hours" numeric,
    "tuhr_duration_days" numeric,
    "blood_color_pattern" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "blood_thickness_pattern" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "istihadah_episode" boolean DEFAULT false NOT NULL,
    "scholar_consulted" boolean DEFAULT false NOT NULL,
    "notes" "text"
);


ALTER TABLE "public"."adah_ledger" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "chat_type" "text" NOT NULL,
    "role" "text" NOT NULL,
    "content" "text" NOT NULL,
    "timestamp" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "chat_history_chat_type_check" CHECK (("chat_type" = ANY (ARRAY['dream'::"text", 'doctor'::"text", 'niswah'::"text"])))
);


ALTER TABLE "public"."chat_history" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_messages" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "content" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "chat_messages_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'assistant'::"text", 'system'::"text"])))
);


ALTER TABLE "public"."chat_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_threads" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" DEFAULT 'New conversation'::"text" NOT NULL,
    "thread_type" "text" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "chat_threads_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'archived'::"text", 'deleted'::"text"]))),
    CONSTRAINT "chat_threads_thread_type_check" CHECK (("thread_type" = ANY (ARRAY['drNiswah'::"text", 'dreamInterpreter'::"text", 'general'::"text", 'fiqhAdvisory'::"text"])))
);


ALTER TABLE "public"."chat_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."community_comments" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "post_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "author_name" "text" NOT NULL,
    "content" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "community_comments_content_length" CHECK ((("char_length"("btrim"("content")) >= 1) AND ("char_length"("btrim"("content")) <= 500)))
);


ALTER TABLE "public"."community_comments" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."community_likes" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "post_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."community_likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."community_posts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "author_name" "text" NOT NULL,
    "title" "text" NOT NULL,
    "content" "text" NOT NULL,
    "category" "text" NOT NULL,
    "tags" "jsonb" DEFAULT '[]'::"jsonb",
    "is_anonymous" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "community_posts_category_check" CHECK (("category" = ANY (ARRAY['support'::"text", 'prayer'::"text", 'wellness'::"text", 'parenting'::"text", 'fertility'::"text", 'general'::"text"]))),
    CONSTRAINT "community_posts_content_length" CHECK ((("char_length"("btrim"("content")) >= 1) AND ("char_length"("btrim"("content")) <= 1000))),
    CONSTRAINT "community_posts_title_length" CHECK ((("char_length"("btrim"("title")) >= 1) AND ("char_length"("btrim"("title")) <= 80)))
);


ALTER TABLE "public"."community_posts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cycle_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "date" "date" NOT NULL,
    "time_logged" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fiqh_state" "text" DEFAULT 'TAHARA'::"text" NOT NULL,
    "flow_intensity" "text" DEFAULT 'medium'::"text" NOT NULL,
    "blood_color" "text" DEFAULT 'red'::"text" NOT NULL,
    "blood_thickness" "text" DEFAULT 'normal'::"text" NOT NULL,
    "kursuf_used" boolean DEFAULT false NOT NULL,
    "discharge_internal" boolean DEFAULT false NOT NULL,
    "is_predicted" boolean DEFAULT false NOT NULL,
    "prediction_confidence" numeric DEFAULT 1 NOT NULL,
    "ramadan_day" integer,
    "fasting_status" "text",
    "symptoms" "jsonb",
    "sleep_quality" integer,
    "energy_level" integer,
    "mood" integer,
    "feeling" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "flow" "text",
    "cycle_day" integer,
    "sync_status" "text" DEFAULT 'synced'::"text" NOT NULL,
    "updated_at" timestamp with time zone,
    CONSTRAINT "cycle_entries_blood_color_check" CHECK (("blood_color" = ANY (ARRAY['red'::"text", 'dark'::"text", 'brown'::"text", 'pink'::"text", 'other'::"text"]))),
    CONSTRAINT "cycle_entries_blood_thickness_check" CHECK (("blood_thickness" = ANY (ARRAY['thick'::"text", 'thin'::"text", 'normal'::"text"]))),
    CONSTRAINT "cycle_entries_fasting_status_check" CHECK (("fasting_status" = ANY (ARRAY['obligatory'::"text", 'lifted'::"text", 'qadha'::"text"]))),
    CONSTRAINT "cycle_entries_fiqh_state_check" CHECK (("fiqh_state" = ANY (ARRAY['HAID'::"text", 'TAHARA'::"text", 'NIFAS'::"text", 'ISTIHADAH'::"text"]))),
    CONSTRAINT "cycle_entries_flow_check" CHECK (("flow" = ANY (ARRAY['none'::"text", 'spotting'::"text", 'light'::"text", 'medium'::"text", 'heavy'::"text"]))),
    CONSTRAINT "cycle_entries_flow_intensity_check" CHECK (("flow_intensity" = ANY (ARRAY['none'::"text", 'spotting'::"text", 'light'::"text", 'medium'::"text", 'heavy'::"text"])))
);


ALTER TABLE "public"."cycle_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."cycle_logs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date",
    "bleeding_intensity" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."cycle_logs" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."dream_entries" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "description" "text" NOT NULL,
    "mood" "text",
    "tags" "jsonb" DEFAULT '[]'::"jsonb",
    "interpretation" "text",
    "rating" integer,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "dream_entries_mood_check" CHECK (("mood" = ANY (ARRAY['peaceful'::"text", 'anxious'::"text", 'joyful'::"text", 'mysterious'::"text", 'fearful'::"text"]))),
    CONSTRAINT "dream_entries_rating_check" CHECK ((("rating" >= 1) AND ("rating" <= 5)))
);


ALTER TABLE "public"."dream_entries" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."flagged_conversations" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "thread_id" "uuid",
    "message_excerpt" "text" NOT NULL,
    "matched_categories" "text"[] NOT NULL,
    "reviewed" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."flagged_conversations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."istihadah_episodes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "start_date" "date",
    "end_date" "date",
    "madhhab_at_time" "text",
    "tamyiz_applied" boolean DEFAULT false NOT NULL,
    "blood_distinguishable" boolean,
    "reverted_to_adah" boolean DEFAULT false NOT NULL,
    "adah_days_used" integer,
    "notes" "text"
);


ALTER TABLE "public"."istihadah_episodes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."nifas_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "birth_date" timestamp with time zone NOT NULL,
    "madhhab_max_days" integer,
    "expected_end" "date",
    "actual_end" "date",
    "breastfeeding_started" boolean DEFAULT false NOT NULL,
    "notes" "text",
    CONSTRAINT "nifas_records_madhhab_max_days_check" CHECK (("madhhab_max_days" = ANY (ARRAY[40, 60])))
);


ALTER TABLE "public"."nifas_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."prayer_log" (
    "id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "date" "date" NOT NULL,
    "prayer_name" "text" NOT NULL,
    "scheduled_time" timestamp with time zone,
    "status" "text" NOT NULL,
    "fiqh_state_at_time" "text",
    "period_started_after_prayer_entered" boolean,
    "notes" "text",
    CONSTRAINT "prayer_log_prayer_name_check" CHECK (("prayer_name" = ANY (ARRAY['fajr'::"text", 'dhuhr'::"text", 'asr'::"text", 'maghrib'::"text", 'isha'::"text"]))),
    CONSTRAINT "prayer_log_status_check" CHECK (("status" = ANY (ARRAY['prayed'::"text", 'qadha_required'::"text", 'lifted'::"text", 'missed'::"text"])))
);


ALTER TABLE "public"."prayer_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pregnancy_profile" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "tracking_basis" "text",
    "reference_date" "date",
    "manual_week_value" integer,
    "manual_week_set_at" timestamp with time zone,
    "is_postpartum" boolean DEFAULT false NOT NULL,
    "postpartum_start_date" "date",
    "high_risk_flags" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "fasting_status" "text" DEFAULT 'not_applicable'::"text" NOT NULL,
    "locale" "text" DEFAULT 'ar'::"text" NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pregnancy_profile_fasting_status_check" CHECK (("fasting_status" = ANY (ARRAY['not_applicable'::"text", 'fasting'::"text", 'not_fasting'::"text", 'unsure'::"text"]))),
    CONSTRAINT "pregnancy_profile_manual_week_value_check" CHECK ((("manual_week_value" >= 1) AND ("manual_week_value" <= 42))),
    CONSTRAINT "pregnancy_profile_tracking_basis_check" CHECK (("tracking_basis" = ANY (ARRAY['lmp'::"text", 'due_date'::"text", 'conception_date'::"text", 'manual_week'::"text"])))
);


ALTER TABLE "public"."pregnancy_profile" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."pregnancy_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "lmp_date" "date",
    "due_date" "date",
    "current_week" integer,
    "birth_date" "date",
    "nifas_id" "uuid",
    "weekly_notes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL
);


ALTER TABLE "public"."pregnancy_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."private_conversations" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "participant_one" "uuid" NOT NULL,
    "participant_two" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "no_self_conversation" CHECK (("participant_one" <> "participant_two"))
);


ALTER TABLE "public"."private_conversations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."private_messages" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "is_read" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "private_messages_content_check" CHECK ((("length"("content") > 0) AND ("length"("content") <= 5000)))
);


ALTER TABLE "public"."private_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text",
    "selected_madhhab" "public"."madhhab_type" DEFAULT 'shafii'::"public"."madhhab_type" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."ramadan_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "hijri_year" integer NOT NULL,
    "total_missed_fasting" integer DEFAULT 0 NOT NULL,
    "qadha_completed" integer DEFAULT 0 NOT NULL,
    "qadha_schedule" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL
);


ALTER TABLE "public"."ramadan_records" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."secret_vault" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "encrypted_content" "text",
    "entry_type" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."secret_vault" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."symptoms_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "cycle_entry_id" "uuid",
    "date" "date" NOT NULL,
    "symptom_type" "text" NOT NULL,
    "severity" integer,
    "body_location" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "symptoms_log_severity_check" CHECK ((("severity" >= 1) AND ("severity" <= 5)))
);


ALTER TABLE "public"."symptoms_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "email_hash" "text",
    "madhhab" "text" DEFAULT 'HANBALI'::"text" NOT NULL,
    "language" "text" DEFAULT 'ar'::"text" NOT NULL,
    "birth_year" integer,
    "display_name" "text",
    "anonymous_mode" boolean DEFAULT false NOT NULL,
    "premium_status" boolean DEFAULT true NOT NULL,
    "premium_expires_at" timestamp with time zone,
    "avg_cycle_length" integer DEFAULT 28 NOT NULL,
    "avg_haid_duration" integer DEFAULT 5 NOT NULL,
    "known_adah_days" integer,
    "adah_confidence" integer DEFAULT 0 NOT NULL,
    "goal_flags" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "conditions" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "notification_prefs" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "pregnant" boolean DEFAULT false NOT NULL,
    "pregnancy_week" integer,
    "reflect_health" boolean DEFAULT false NOT NULL,
    "prayer_city" "text",
    "prayer_country" "text",
    "prayer_city_ar" "text",
    "prayer_country_ar" "text",
    "prayer_lat" double precision,
    "prayer_lon" double precision,
    "location_lat" double precision,
    "location_lng" double precision,
    "location_name" "text",
    "manual_prayer_offsets" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "role" "text" DEFAULT 'user'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "onboarding_completed" boolean DEFAULT false NOT NULL,
    CONSTRAINT "users_language_check" CHECK (("language" = ANY (ARRAY['en'::"text", 'ar'::"text"]))),
    CONSTRAINT "users_madhhab_check" CHECK (("madhhab" = ANY (ARRAY['HANAFI'::"text", 'MALIKI'::"text", 'SHAFII'::"text", 'HANBALI'::"text"]))),
    CONSTRAINT "users_role_check" CHECK (("role" = ANY (ARRAY['user'::"text", 'admin'::"text"])))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."wellbeing_logs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "log_date" "date" NOT NULL,
    "mood" integer NOT NULL,
    "energy" integer NOT NULL,
    "sleep" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "wellbeing_logs_energy_check" CHECK ((("energy" >= 1) AND ("energy" <= 5))),
    CONSTRAINT "wellbeing_logs_mood_check" CHECK ((("mood" >= 1) AND ("mood" <= 5))),
    CONSTRAINT "wellbeing_logs_sleep_check" CHECK ((("sleep" >= 1) AND ("sleep" <= 5)))
);


ALTER TABLE "public"."wellbeing_logs" OWNER TO "postgres";


ALTER TABLE ONLY "public"."adah_ledger"
    ADD CONSTRAINT "adah_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_history"
    ADD CONSTRAINT "chat_history_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_threads"
    ADD CONSTRAINT "chat_threads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."community_comments"
    ADD CONSTRAINT "community_comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."community_likes"
    ADD CONSTRAINT "community_likes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."community_posts"
    ADD CONSTRAINT "community_posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cycle_entries"
    ADD CONSTRAINT "cycle_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."cycle_logs"
    ADD CONSTRAINT "cycle_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."dream_entries"
    ADD CONSTRAINT "dream_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."flagged_conversations"
    ADD CONSTRAINT "flagged_conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."istihadah_episodes"
    ADD CONSTRAINT "istihadah_episodes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."nifas_records"
    ADD CONSTRAINT "nifas_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."prayer_log"
    ADD CONSTRAINT "prayer_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pregnancy_profile"
    ADD CONSTRAINT "pregnancy_profile_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pregnancy_profile"
    ADD CONSTRAINT "pregnancy_profile_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "public"."pregnancy_records"
    ADD CONSTRAINT "pregnancy_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."private_conversations"
    ADD CONSTRAINT "private_conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."private_messages"
    ADD CONSTRAINT "private_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."ramadan_records"
    ADD CONSTRAINT "ramadan_records_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."secret_vault"
    ADD CONSTRAINT "secret_vault_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."symptoms_log"
    ADD CONSTRAINT "symptoms_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."private_conversations"
    ADD CONSTRAINT "unique_pair" UNIQUE ("participant_one", "participant_two");



ALTER TABLE ONLY "public"."community_likes"
    ADD CONSTRAINT "unique_post_like" UNIQUE ("post_id", "user_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wellbeing_logs"
    ADD CONSTRAINT "wellbeing_logs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."wellbeing_logs"
    ADD CONSTRAINT "wellbeing_logs_user_id_log_date_key" UNIQUE ("user_id", "log_date");



CREATE INDEX "adah_ledger_user_cycle_idx" ON "public"."adah_ledger" USING "btree" ("user_id", "cycle_number" DESC);



CREATE INDEX "chat_history_user_type_ts_idx" ON "public"."chat_history" USING "btree" ("user_id", "chat_type", "timestamp");



CREATE INDEX "cycle_entries_user_date_idx" ON "public"."cycle_entries" USING "btree" ("user_id", "date" DESC, "time_logged" DESC);



CREATE INDEX "idx_chat_messages_thread_id_created_at" ON "public"."chat_messages" USING "btree" ("thread_id", "created_at");



CREATE INDEX "idx_chat_messages_user_id" ON "public"."chat_messages" USING "btree" ("user_id");



CREATE INDEX "idx_chat_threads_user_id_created_at" ON "public"."chat_threads" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_community_comments_post_id_created_at" ON "public"."community_comments" USING "btree" ("post_id", "created_at");



CREATE INDEX "idx_community_likes_post_id" ON "public"."community_likes" USING "btree" ("post_id");



CREATE INDEX "idx_community_likes_user_id" ON "public"."community_likes" USING "btree" ("user_id");



CREATE INDEX "idx_community_posts_category_created_at" ON "public"."community_posts" USING "btree" ("category", "created_at" DESC);



CREATE INDEX "idx_community_posts_user_id_created_at" ON "public"."community_posts" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_dream_entries_user_id_created_at" ON "public"."dream_entries" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_flagged_conversations_reviewed" ON "public"."flagged_conversations" USING "btree" ("reviewed") WHERE ("reviewed" = false);



CREATE INDEX "idx_flagged_conversations_user_id_created_at" ON "public"."flagged_conversations" USING "btree" ("user_id", "created_at" DESC);



CREATE INDEX "idx_private_conversations_participant_one" ON "public"."private_conversations" USING "btree" ("participant_one");



CREATE INDEX "idx_private_conversations_participant_two" ON "public"."private_conversations" USING "btree" ("participant_two");



CREATE INDEX "idx_private_conversations_updated_at" ON "public"."private_conversations" USING "btree" ("updated_at" DESC);



CREATE INDEX "idx_private_messages_conversation_id_created_at" ON "public"."private_messages" USING "btree" ("conversation_id", "created_at");



CREATE INDEX "idx_private_messages_sender_id" ON "public"."private_messages" USING "btree" ("sender_id");



CREATE INDEX "idx_wellbeing_logs_user_date" ON "public"."wellbeing_logs" USING "btree" ("user_id", "log_date" DESC);



CREATE INDEX "prayer_log_user_date_idx" ON "public"."prayer_log" USING "btree" ("user_id", "date" DESC);



CREATE INDEX "ramadan_records_user_year_idx" ON "public"."ramadan_records" USING "btree" ("user_id", "hijri_year");



CREATE OR REPLACE TRIGGER "trg_touch_private_conversation" AFTER INSERT ON "public"."private_messages" FOR EACH ROW EXECUTE FUNCTION "public"."touch_private_conversation"();



CREATE OR REPLACE TRIGGER "users_set_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();



ALTER TABLE ONLY "public"."adah_ledger"
    ADD CONSTRAINT "adah_ledger_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_history"
    ADD CONSTRAINT "chat_history_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."chat_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_threads"
    ADD CONSTRAINT "chat_threads_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."community_comments"
    ADD CONSTRAINT "community_comments_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."community_posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."community_comments"
    ADD CONSTRAINT "community_comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."community_likes"
    ADD CONSTRAINT "community_likes_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."community_posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."community_likes"
    ADD CONSTRAINT "community_likes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."community_posts"
    ADD CONSTRAINT "community_posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cycle_entries"
    ADD CONSTRAINT "cycle_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."cycle_logs"
    ADD CONSTRAINT "cycle_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."dream_entries"
    ADD CONSTRAINT "dream_entries_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."flagged_conversations"
    ADD CONSTRAINT "flagged_conversations_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."chat_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."flagged_conversations"
    ADD CONSTRAINT "flagged_conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."istihadah_episodes"
    ADD CONSTRAINT "istihadah_episodes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."nifas_records"
    ADD CONSTRAINT "nifas_records_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."prayer_log"
    ADD CONSTRAINT "prayer_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pregnancy_profile"
    ADD CONSTRAINT "pregnancy_profile_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."pregnancy_records"
    ADD CONSTRAINT "pregnancy_records_nifas_id_fkey" FOREIGN KEY ("nifas_id") REFERENCES "public"."nifas_records"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pregnancy_records"
    ADD CONSTRAINT "pregnancy_records_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."private_conversations"
    ADD CONSTRAINT "private_conversations_participant_one_fkey" FOREIGN KEY ("participant_one") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."private_conversations"
    ADD CONSTRAINT "private_conversations_participant_two_fkey" FOREIGN KEY ("participant_two") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."private_messages"
    ADD CONSTRAINT "private_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."private_conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."private_messages"
    ADD CONSTRAINT "private_messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."ramadan_records"
    ADD CONSTRAINT "ramadan_records_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."secret_vault"
    ADD CONSTRAINT "secret_vault_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."symptoms_log"
    ADD CONSTRAINT "symptoms_log_cycle_entry_id_fkey" FOREIGN KEY ("cycle_entry_id") REFERENCES "public"."cycle_entries"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."symptoms_log"
    ADD CONSTRAINT "symptoms_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."wellbeing_logs"
    ADD CONSTRAINT "wellbeing_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Participants can read messages in their conversations" ON "public"."private_messages" FOR SELECT USING ("public"."is_conversation_participant"("conversation_id"));



CREATE POLICY "Participants can read their conversations" ON "public"."private_conversations" FOR SELECT USING ((("auth"."uid"() = "participant_one") OR ("auth"."uid"() = "participant_two")));



CREATE POLICY "Participants can send messages in their conversations" ON "public"."private_messages" FOR INSERT WITH CHECK ((("auth"."uid"() = "sender_id") AND "public"."is_conversation_participant"("conversation_id")));



CREATE POLICY "Participants can update their conversations" ON "public"."private_conversations" FOR UPDATE USING ((("auth"."uid"() = "participant_one") OR ("auth"."uid"() = "participant_two"))) WITH CHECK ((("auth"."uid"() = "participant_one") OR ("auth"."uid"() = "participant_two")));



CREATE POLICY "Recipients can mark messages as read" ON "public"."private_messages" FOR UPDATE USING (("public"."is_conversation_participant"("conversation_id") AND ("auth"."uid"() <> "sender_id"))) WITH CHECK (("public"."is_conversation_participant"("conversation_id") AND ("auth"."uid"() <> "sender_id")));



CREATE POLICY "Users can create comments on visible posts" ON "public"."community_comments" FOR INSERT WITH CHECK ((("auth"."uid"() = "user_id") AND (EXISTS ( SELECT 1
   FROM "public"."community_posts" "cp"
  WHERE ("cp"."id" = "community_comments"."post_id")))));



CREATE POLICY "Users can create conversations they participate in" ON "public"."private_conversations" FOR INSERT WITH CHECK ((("auth"."uid"() = "participant_one") OR ("auth"."uid"() = "participant_two")));



CREATE POLICY "Users can create their own community_posts" ON "public"."community_posts" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete own cycle logs" ON "public"."cycle_logs" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own chat messages" ON "public"."chat_messages" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own chat_threads" ON "public"."chat_threads" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own community_comments" ON "public"."community_comments" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete their own community_posts" ON "public"."community_posts" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert messages into their own chat threads" ON "public"."chat_messages" FOR INSERT WITH CHECK ((("auth"."uid"() = "user_id") AND (EXISTS ( SELECT 1
   FROM "public"."chat_threads" "ct"
  WHERE (("ct"."id" = "chat_messages"."thread_id") AND ("ct"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Users can insert own cycle logs" ON "public"."cycle_logs" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can insert own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can insert their own chat_threads" ON "public"."chat_threads" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can like as themselves" ON "public"."community_likes" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only delete their own dream_entries" ON "public"."dream_entries" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only delete their own pregnancy_profile" ON "public"."pregnancy_profile" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only delete their own wellbeing_logs" ON "public"."wellbeing_logs" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only insert their own dream_entries" ON "public"."dream_entries" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only insert their own pregnancy_profile" ON "public"."pregnancy_profile" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only insert their own wellbeing_logs" ON "public"."wellbeing_logs" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only read their own dream_entries" ON "public"."dream_entries" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only read their own pregnancy_profile" ON "public"."pregnancy_profile" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only read their own wellbeing_logs" ON "public"."wellbeing_logs" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only update their own dream_entries" ON "public"."dream_entries" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only update their own pregnancy_profile" ON "public"."pregnancy_profile" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can only update their own wellbeing_logs" ON "public"."wellbeing_logs" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can read all community_comments" ON "public"."community_comments" FOR SELECT USING (true);



CREATE POLICY "Users can read all community_likes" ON "public"."community_likes" FOR SELECT USING (true);



CREATE POLICY "Users can read all community_posts" ON "public"."community_posts" FOR SELECT USING (true);



CREATE POLICY "Users can read their own chat_messages or messages in their thr" ON "public"."chat_messages" FOR SELECT USING ((("auth"."uid"() = "user_id") OR (EXISTS ( SELECT 1
   FROM "public"."chat_threads" "ct"
  WHERE (("ct"."id" = "chat_messages"."thread_id") AND ("ct"."user_id" = "auth"."uid"()))))));



CREATE POLICY "Users can read their own chat_threads" ON "public"."chat_threads" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can remove their own like" ON "public"."community_likes" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own cycle logs" ON "public"."cycle_logs" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Users can update their own chat messages" ON "public"."chat_messages" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own chat_threads" ON "public"."chat_threads" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own community_comments" ON "public"."community_comments" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can update their own community_posts" ON "public"."community_posts" FOR UPDATE USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own cycle logs" ON "public"."cycle_logs" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can view own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



ALTER TABLE "public"."adah_ledger" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "adah_ledger_own" ON "public"."adah_ledger" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."chat_history" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "chat_history_own" ON "public"."chat_history" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."chat_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_threads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."community_comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."community_likes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."community_posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."cycle_entries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "cycle_entries_own" ON "public"."cycle_entries" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."cycle_logs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."dream_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."flagged_conversations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."istihadah_episodes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "istihadah_episodes_own" ON "public"."istihadah_episodes" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."nifas_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "nifas_records_own" ON "public"."nifas_records" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."prayer_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "prayer_log_own" ON "public"."prayer_log" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."pregnancy_profile" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pregnancy_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "pregnancy_records_own" ON "public"."pregnancy_records" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."private_conversations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."private_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."ramadan_records" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "ramadan_records_own" ON "public"."ramadan_records" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."secret_vault" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "secret_vault_own" ON "public"."secret_vault" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."symptoms_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "symptoms_log_own" ON "public"."symptoms_log" USING ("public"."can_access_user"("user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_delete_own" ON "public"."users" FOR DELETE USING ((("auth"."uid"() = "id") OR "public"."is_admin"()));



CREATE POLICY "users_insert_own" ON "public"."users" FOR INSERT WITH CHECK ((("auth"."uid"() = "id") AND ("role" = 'user'::"text")));



CREATE POLICY "users_read_own" ON "public"."users" FOR SELECT USING ("public"."can_access_user"("id"));



CREATE POLICY "users_update_own" ON "public"."users" FOR UPDATE USING ((("auth"."uid"() = "id") OR "public"."is_admin"())) WITH CHECK ((("auth"."uid"() = "id") OR "public"."is_admin"()));



ALTER TABLE "public"."wellbeing_logs" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."can_access_user"("row_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_access_user"("row_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."can_access_user"("row_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_user_profile"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_user_profile"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_user_profile"() TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_my_account"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_conversation_participant"("conversation" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_conversation_participant"("conversation" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_conversation_participant"("conversation" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";



GRANT ALL ON FUNCTION "public"."touch_private_conversation"() TO "anon";
GRANT ALL ON FUNCTION "public"."touch_private_conversation"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."touch_private_conversation"() TO "service_role";



GRANT ALL ON TABLE "public"."adah_ledger" TO "anon";
GRANT ALL ON TABLE "public"."adah_ledger" TO "authenticated";
GRANT ALL ON TABLE "public"."adah_ledger" TO "service_role";



GRANT ALL ON TABLE "public"."chat_history" TO "anon";
GRANT ALL ON TABLE "public"."chat_history" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_history" TO "service_role";



GRANT ALL ON TABLE "public"."chat_messages" TO "anon";
GRANT ALL ON TABLE "public"."chat_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_messages" TO "service_role";



GRANT ALL ON TABLE "public"."chat_threads" TO "anon";
GRANT ALL ON TABLE "public"."chat_threads" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_threads" TO "service_role";



GRANT ALL ON TABLE "public"."community_comments" TO "anon";
GRANT ALL ON TABLE "public"."community_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."community_comments" TO "service_role";



GRANT ALL ON TABLE "public"."community_likes" TO "anon";
GRANT ALL ON TABLE "public"."community_likes" TO "authenticated";
GRANT ALL ON TABLE "public"."community_likes" TO "service_role";



GRANT ALL ON TABLE "public"."community_posts" TO "anon";
GRANT ALL ON TABLE "public"."community_posts" TO "authenticated";
GRANT ALL ON TABLE "public"."community_posts" TO "service_role";



GRANT ALL ON TABLE "public"."cycle_entries" TO "anon";
GRANT ALL ON TABLE "public"."cycle_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."cycle_entries" TO "service_role";



GRANT ALL ON TABLE "public"."cycle_logs" TO "anon";
GRANT ALL ON TABLE "public"."cycle_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."cycle_logs" TO "service_role";



GRANT ALL ON TABLE "public"."dream_entries" TO "anon";
GRANT ALL ON TABLE "public"."dream_entries" TO "authenticated";
GRANT ALL ON TABLE "public"."dream_entries" TO "service_role";



GRANT ALL ON TABLE "public"."flagged_conversations" TO "anon";
GRANT ALL ON TABLE "public"."flagged_conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."flagged_conversations" TO "service_role";



GRANT ALL ON TABLE "public"."istihadah_episodes" TO "anon";
GRANT ALL ON TABLE "public"."istihadah_episodes" TO "authenticated";
GRANT ALL ON TABLE "public"."istihadah_episodes" TO "service_role";



GRANT ALL ON TABLE "public"."nifas_records" TO "anon";
GRANT ALL ON TABLE "public"."nifas_records" TO "authenticated";
GRANT ALL ON TABLE "public"."nifas_records" TO "service_role";



GRANT ALL ON TABLE "public"."prayer_log" TO "anon";
GRANT ALL ON TABLE "public"."prayer_log" TO "authenticated";
GRANT ALL ON TABLE "public"."prayer_log" TO "service_role";



GRANT ALL ON TABLE "public"."pregnancy_profile" TO "anon";
GRANT ALL ON TABLE "public"."pregnancy_profile" TO "authenticated";
GRANT ALL ON TABLE "public"."pregnancy_profile" TO "service_role";



GRANT ALL ON TABLE "public"."pregnancy_records" TO "anon";
GRANT ALL ON TABLE "public"."pregnancy_records" TO "authenticated";
GRANT ALL ON TABLE "public"."pregnancy_records" TO "service_role";



GRANT ALL ON TABLE "public"."private_conversations" TO "anon";
GRANT ALL ON TABLE "public"."private_conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."private_conversations" TO "service_role";



GRANT ALL ON TABLE "public"."private_messages" TO "anon";
GRANT ALL ON TABLE "public"."private_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."private_messages" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."ramadan_records" TO "anon";
GRANT ALL ON TABLE "public"."ramadan_records" TO "authenticated";
GRANT ALL ON TABLE "public"."ramadan_records" TO "service_role";



GRANT ALL ON TABLE "public"."secret_vault" TO "anon";
GRANT ALL ON TABLE "public"."secret_vault" TO "authenticated";
GRANT ALL ON TABLE "public"."secret_vault" TO "service_role";



GRANT ALL ON TABLE "public"."symptoms_log" TO "anon";
GRANT ALL ON TABLE "public"."symptoms_log" TO "authenticated";
GRANT ALL ON TABLE "public"."symptoms_log" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."wellbeing_logs" TO "anon";
GRANT ALL ON TABLE "public"."wellbeing_logs" TO "authenticated";
GRANT ALL ON TABLE "public"."wellbeing_logs" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







