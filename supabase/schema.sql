-- Supabase Schema for niswah app

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- TABLE: users
CREATE TABLE users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email_hash TEXT, -- hashed — never store plain email
  madhhab TEXT CHECK (madhhab IN ('HANAFI','MALIKI','SHAFII','HANBALI')),
  language TEXT DEFAULT 'en',
  birth_year INT,
  display_name TEXT,
  anonymous_mode BOOLEAN DEFAULT false,
  premium_status BOOLEAN DEFAULT false,
  premium_expires_at TIMESTAMPTZ,
  avg_cycle_length INT DEFAULT 28,
  avg_haid_duration INT DEFAULT 5,
  known_adah_days INT,
  adah_confidence INT DEFAULT 0,
  goal_flags JSONB DEFAULT '[]',
  conditions JSONB DEFAULT '[]',
  notification_prefs JSONB DEFAULT '{}',
  prayer_calculation_method TEXT DEFAULT 'MWL',
  location_lat FLOAT,
  location_lng FLOAT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- TABLE: profiles (1:1 extension of auth.users — single source of truth for AuthRepositoryImpl & UserProfileRepository)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT,
  selected_madhhab TEXT DEFAULT 'shafii',
  email TEXT,
  display_name TEXT,
  anonymous_mode BOOLEAN DEFAULT false,
  phone_number TEXT,
  bio TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- TABLE: chat_threads
CREATE TABLE chat_threads (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'New conversation',
  thread_type TEXT NOT NULL CHECK (thread_type IN ('drNiswah','dreamInterpreter','general','fiqhAdvisory')),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','archived','deleted')),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- TABLE: chat_messages
CREATE TABLE chat_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  thread_id UUID NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user','assistant','system')),
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_chat_threads_user_id_created_at
  ON chat_threads(user_id, created_at DESC);

CREATE INDEX idx_chat_messages_thread_id_created_at
  ON chat_messages(thread_id, created_at ASC);

CREATE INDEX idx_chat_messages_user_id
  ON chat_messages(user_id);

ALTER TABLE chat_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own chat_threads" ON chat_threads
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own chat_threads" ON chat_threads
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own chat_threads" ON chat_threads
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own chat_threads" ON chat_threads
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can read their own chat_messages or messages in their threads" ON chat_messages
  FOR SELECT USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1
      FROM chat_threads ct
      WHERE ct.id = chat_messages.thread_id
        AND ct.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can insert messages into their own chat threads" ON chat_messages
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM chat_threads ct
      WHERE ct.id = chat_messages.thread_id
        AND ct.user_id = auth.uid()
    )
  );

CREATE POLICY "Users can update their own chat messages" ON chat_messages
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own chat messages" ON chat_messages
  FOR DELETE USING (auth.uid() = user_id);

-- TABLE: community_posts
CREATE TABLE community_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  author_name TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('support','prayer','wellness','parenting','fertility','general')),
  tags JSONB DEFAULT '[]',
  is_anonymous BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT community_posts_title_length CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  CONSTRAINT community_posts_content_length CHECK (char_length(btrim(content)) BETWEEN 1 AND 1000)
);

-- TABLE: community_comments
CREATE TABLE community_comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  author_name TEXT NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT community_comments_content_length CHECK (char_length(btrim(content)) BETWEEN 1 AND 500)
);

-- TABLE: community_likes
CREATE TABLE community_likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT unique_post_like UNIQUE (post_id, user_id)
);

CREATE INDEX idx_community_posts_user_id_created_at
  ON community_posts(user_id, created_at DESC);

CREATE INDEX idx_community_posts_category_created_at
  ON community_posts(category, created_at DESC);

CREATE INDEX idx_community_comments_post_id_created_at
  ON community_comments(post_id, created_at ASC);

CREATE INDEX idx_community_likes_post_id ON community_likes(post_id);
CREATE INDEX idx_community_likes_user_id ON community_likes(user_id);

ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read all community_posts" ON community_posts
  FOR SELECT USING (true);

CREATE POLICY "Users can create their own community_posts" ON community_posts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own community_posts" ON community_posts
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own community_posts" ON community_posts
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can read all community_comments" ON community_comments
  FOR SELECT USING (true);

CREATE POLICY "Users can create comments on visible posts" ON community_comments
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1
      FROM community_posts cp
      WHERE cp.id = community_comments.post_id
    )
  );

CREATE POLICY "Users can update their own community_comments" ON community_comments
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own community_comments" ON community_comments
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Users can read all community_likes" ON community_likes
  FOR SELECT USING (true);

CREATE POLICY "Users can like as themselves" ON community_likes
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can remove their own like" ON community_likes
  FOR DELETE USING (auth.uid() = user_id);

-- TABLE: cycle_entries
-- Reconciled 2026-08-25 against the actual live table (via
-- information_schema.columns) after discovering this block had drifted
-- from reality in multiple ways — see the two migrations below for the
-- history. sleep_quality/energy_level/mood/feeling predate this session
-- and were never documented here; symptoms is jsonb, not text[].
CREATE TABLE cycle_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  time_logged TIMESTAMPTZ NOT NULL DEFAULT now(),
  fiqh_state TEXT NOT NULL DEFAULT 'TAHARA'
    CHECK (fiqh_state IN ('HAID','TAHARA','NIFAS','ISTIHADAH')),
  flow_intensity TEXT NOT NULL DEFAULT 'medium'
    CHECK (flow_intensity IN ('none','spotting','light','medium','heavy')),
  blood_color TEXT NOT NULL DEFAULT 'red'
    CHECK (blood_color IN ('red','dark','brown','pink','other')),
  blood_thickness TEXT NOT NULL DEFAULT 'normal'
    CHECK (blood_thickness IN ('thick','thin','normal')),
  kursuf_used BOOLEAN NOT NULL DEFAULT false,
  discharge_internal BOOLEAN NOT NULL DEFAULT false,
  is_predicted BOOLEAN NOT NULL DEFAULT false,
  prediction_confidence NUMERIC NOT NULL DEFAULT 1,
  ramadan_day INT,
  fasting_status TEXT CHECK (fasting_status IN ('obligatory','lifted','qadha')),
  symptoms JSONB,
  sleep_quality INT,
  energy_level INT,
  mood INT,
  feeling TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ,
  -- Columns actually read/written by the app's CycleLog entity — added
  -- 2026-08-26 after discovering the columns above were never populated
  -- by any client code (see 20260826090000_cycle_entries_app_columns.sql
  -- and 20260825210000_cycle_entries_updated_at_and_fiqh_default.sql).
  flow TEXT CHECK (flow IN ('none','spotting','light','medium','heavy')),
  cycle_day INT,
  sync_status TEXT NOT NULL DEFAULT 'synced'
);

-- TABLE: symptoms_log
CREATE TABLE symptoms_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cycle_entry_id UUID REFERENCES cycle_entries(id) ON DELETE SET NULL,
  date DATE NOT NULL,
  symptom_type TEXT NOT NULL,
  severity INT CHECK (severity BETWEEN 1 AND 5),
  body_location TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- TABLE: prayer_entries (renamed from prayer_log)
CREATE TABLE prayer_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  prayer_name TEXT CHECK (prayer_name IN ('fajr','dhuhr','asr','maghrib','isha')),
  scheduled_time TIMESTAMPTZ,
  status TEXT CHECK (status IN ('prayed','qadha_required','lifted','missed')),
  fiqh_state_at_time TEXT,
  period_started_after_prayer_entered BOOLEAN,
  notes TEXT,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- TABLE: adah_ledger
CREATE TABLE adah_ledger (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  cycle_number INT,
  haid_start TIMESTAMPTZ NOT NULL,
  haid_end TIMESTAMPTZ,
  haid_duration_hours FLOAT,
  tuhr_duration_days FLOAT,
  blood_color_pattern JSONB DEFAULT '[]',
  blood_thickness_pattern JSONB DEFAULT '[]',
  istihadah_episode BOOLEAN DEFAULT false,
  scholar_consulted BOOLEAN DEFAULT false,
  notes TEXT
);

-- TABLE: istihadah_episodes
CREATE TABLE istihadah_episodes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  start_date DATE,
  end_date DATE,
  madhhab_at_time TEXT,
  tamyiz_applied BOOLEAN DEFAULT false,
  blood_distinguishable BOOLEAN,
  reverted_to_adah BOOLEAN DEFAULT false,
  adah_days_used INT,
  notes TEXT
);

-- TABLE: nifas_records
CREATE TABLE nifas_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  birth_date TIMESTAMPTZ NOT NULL,
  madhhab_max_days INT CHECK (madhhab_max_days IN (40, 60)),
  expected_end DATE,
  actual_end DATE,
  breastfeeding_started BOOLEAN DEFAULT false,
  notes TEXT
);

-- TABLE: ramadan_records
CREATE TABLE ramadan_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  hijri_year INT,
  total_missed_fasting INT DEFAULT 0,
  qadha_completed INT DEFAULT 0,
  qadha_schedule JSONB DEFAULT '[]'
);

-- TABLE: pregnancy_milestones (renamed from pregnancy_records)
CREATE TABLE pregnancy_milestones (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lmp_date DATE,
  due_date DATE,
  current_week INT,
  birth_date DATE,
  nifas_id UUID REFERENCES nifas_records(id) ON DELETE SET NULL,
  weekly_notes JSONB DEFAULT '{}',
  week INT,
  trimester TEXT CHECK (trimester IN ('first','second','third')),
  label TEXT,
  summary TEXT,
  date DATE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- TABLE: pregnancy_profile (single source of truth for the "طبيبة" chat's
-- personalization context — see supabase/functions/dr-niswah-chat/index.ts.
-- Deliberately separate from pregnancy_milestones/nifas_records above.)
CREATE TABLE pregnancy_profile (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
  tracking_basis TEXT CHECK (tracking_basis IN ('lmp','due_date','conception_date','manual_week')),
  reference_date DATE,
  manual_week_value INT CHECK (manual_week_value BETWEEN 1 AND 42),
  manual_week_set_at TIMESTAMPTZ,
  is_postpartum BOOLEAN NOT NULL DEFAULT false,
  postpartum_start_date DATE,
  high_risk_flags TEXT[] NOT NULL DEFAULT '{}',
  fasting_status TEXT NOT NULL DEFAULT 'not_applicable'
    CHECK (fasting_status IN ('not_applicable','fasting','not_fasting','unsure')),
  locale TEXT NOT NULL DEFAULT 'ar',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- TABLE: secret_vault_entries
CREATE TABLE secret_vault_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  encrypted_content TEXT, -- AES-256 encrypted client-side
  entry_type TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- TABLE: educational_resources
CREATE TABLE educational_resources (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  category TEXT NOT NULL CHECK (category IN ('health','fiqh','family','wellness','spouse')),
  title TEXT NOT NULL,
  summary TEXT,
  content TEXT NOT NULL,
  author TEXT DEFAULT 'Niswah Team',
  read_minutes INT DEFAULT 4,
  tags JSONB DEFAULT '[]',
  is_spouse_guide BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- TABLE: dream_entries
CREATE TABLE dream_entries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  mood TEXT CHECK (mood IN ('peaceful','anxious','joyful','mysterious','fearful')),
  tags JSONB DEFAULT '[]',
  interpretation TEXT,
  rating INT CHECK (rating BETWEEN 1 AND 5),
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ROW LEVEL SECURITY (RLS)
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE cycle_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE symptoms_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE prayer_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE adah_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE istihadah_episodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE nifas_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE ramadan_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE pregnancy_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE pregnancy_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE secret_vault_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE educational_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE dream_entries ENABLE ROW LEVEL SECURITY;

-- Policies for users
CREATE POLICY "Users can only read their own data" ON users FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can only insert their own data" ON users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can only update their own data" ON users FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can only delete their own data" ON users FOR DELETE USING (auth.uid() = id);

-- Policies for profiles
CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- Policies for cycle_entries
CREATE POLICY "Users can only read their own cycle_entries" ON cycle_entries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own cycle_entries" ON cycle_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own cycle_entries" ON cycle_entries FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own cycle_entries" ON cycle_entries FOR DELETE USING (auth.uid() = user_id);

-- Policies for symptoms_log
CREATE POLICY "Users can only read their own symptoms_log" ON symptoms_log FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own symptoms_log" ON symptoms_log FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own symptoms_log" ON symptoms_log FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own symptoms_log" ON symptoms_log FOR DELETE USING (auth.uid() = user_id);

-- Policies for prayer_entries
CREATE POLICY "Users can only read their own prayer_entries" ON prayer_entries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own prayer_entries" ON prayer_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own prayer_entries" ON prayer_entries FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own prayer_entries" ON prayer_entries FOR DELETE USING (auth.uid() = user_id);

-- Policies for adah_ledger
CREATE POLICY "Users can only read their own adah_ledger" ON adah_ledger FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own adah_ledger" ON adah_ledger FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own adah_ledger" ON adah_ledger FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own adah_ledger" ON adah_ledger FOR DELETE USING (auth.uid() = user_id);

-- Policies for istihadah_episodes
CREATE POLICY "Users can only read their own istihadah_episodes" ON istihadah_episodes FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own istihadah_episodes" ON istihadah_episodes FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own istihadah_episodes" ON istihadah_episodes FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own istihadah_episodes" ON istihadah_episodes FOR DELETE USING (auth.uid() = user_id);

-- Policies for nifas_records
CREATE POLICY "Users can only read their own nifas_records" ON nifas_records FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own nifas_records" ON nifas_records FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own nifas_records" ON nifas_records FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own nifas_records" ON nifas_records FOR DELETE USING (auth.uid() = user_id);

-- Policies for ramadan_records
CREATE POLICY "Users can only read their own ramadan_records" ON ramadan_records FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own ramadan_records" ON ramadan_records FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own ramadan_records" ON ramadan_records FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own ramadan_records" ON ramadan_records FOR DELETE USING (auth.uid() = user_id);

-- Policies for pregnancy_milestones
CREATE POLICY "Users can only read their own pregnancy_milestones" ON pregnancy_milestones FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own pregnancy_milestones" ON pregnancy_milestones FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own pregnancy_milestones" ON pregnancy_milestones FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own pregnancy_milestones" ON pregnancy_milestones FOR DELETE USING (auth.uid() = user_id);

-- Policies for pregnancy_profile
CREATE POLICY "Users can only read their own pregnancy_profile" ON pregnancy_profile FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own pregnancy_profile" ON pregnancy_profile FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own pregnancy_profile" ON pregnancy_profile FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own pregnancy_profile" ON pregnancy_profile FOR DELETE USING (auth.uid() = user_id);

-- Policies for secret_vault_entries
CREATE POLICY "Users can only read their own secret_vault_entries" ON secret_vault_entries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own secret_vault_entries" ON secret_vault_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own secret_vault_entries" ON secret_vault_entries FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own secret_vault_entries" ON secret_vault_entries FOR DELETE USING (auth.uid() = user_id);

-- Policies for educational_resources (public read, restricted writes)
CREATE POLICY "Public can read educational_resources" ON educational_resources FOR SELECT USING (true);

-- Policies for dream_entries
CREATE POLICY "Users can only read their own dream_entries" ON dream_entries FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can only insert their own dream_entries" ON dream_entries FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can only update their own dream_entries" ON dream_entries FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can only delete their own dream_entries" ON dream_entries FOR DELETE USING (auth.uid() = user_id);
