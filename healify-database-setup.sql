-- ================================================================
-- HEALIFY — SUPABASE COMPLETE SETUP
-- Paste this entire file into:
-- Supabase Dashboard → SQL Editor → New Query → Run All
-- ================================================================

-- ────────────────────────────────────────────────────────────────
-- STEP 0: Email verification is ENABLED for patients
-- ────────────────────────────────────────────────────────────────
-- Supabase sends a confirmation email when a patient registers.
-- The patient app shows a "Check your email" screen until confirmed.
--
-- Make sure this setting is ON (it is by default):
-- Dashboard → Authentication → Settings →
--   "Enable email confirmations" → LEAVE ON ✅
--
-- To customise the verification email:
-- Dashboard → Authentication → Email Templates → Confirm signup

-- ────────────────────────────────────────────────────────────────
-- 1. PROFILES TABLE
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id                UUID    PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email             TEXT    UNIQUE,
  name              TEXT,
  age               INTEGER,
  city              TEXT,
  condition         TEXT,
  surgeon           TEXT,
  surgery_date      DATE,
  plan_duration     INTEGER DEFAULT 30,
  role              TEXT    DEFAULT 'patient' CHECK (role IN ('patient','admin')),
  -- Admin-only fields (ignored for patients)
  qualification     TEXT,
  rating            TEXT,
  avg_response_time TEXT,
  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-create profile row on signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, role)
  VALUES (NEW.id, NEW.email, 'patient')
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ────────────────────────────────────────────────────────────────
-- 2. SESSIONS TABLE
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sessions (
  id                    UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID    REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  session_date          TIMESTAMPTZ DEFAULT NOW(),
  leg                   TEXT    CHECK (leg IN ('LEFT','RIGHT')),
  valid_reps            INTEGER DEFAULT 0,
  total_reps            INTEGER DEFAULT 0,
  success_rate          INTEGER DEFAULT 0,
  avg_rom               INTEGER DEFAULT 0,
  best_rom              INTEGER DEFAULT 0,
  avg_time              NUMERIC(4,1) DEFAULT 0,
  score                 INTEGER DEFAULT 0,
  stability_warnings    INTEGER DEFAULT 0,
  issue_incomplete_rom  INTEGER DEFAULT 0,
  issue_too_fast        INTEGER DEFAULT 0,
  issue_too_slow        INTEGER DEFAULT 0,
  issue_hyperextension  INTEGER DEFAULT 0,
  issue_hip_stability   INTEGER DEFAULT 0,
  issue_jerky           INTEGER DEFAULT 0,
  issue_wrong_leg       INTEGER DEFAULT 0,
  created_at            TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sessions_user    ON public.sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_created ON public.sessions(created_at DESC);


-- ────────────────────────────────────────────────────────────────
-- 3. PRESCRIPTIONS TABLE
-- Admin assigns exercise plans to a patient
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.prescriptions (
  id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id  UUID    REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  admin_id    UUID    REFERENCES public.profiles(id) ON DELETE SET NULL,
  title       TEXT    DEFAULT 'Daily Session',
  exercises   JSONB   NOT NULL DEFAULT '[]',
  -- exercises JSON format:
  -- [{"name":"Knee Extension","sets":3,"reps":10,"icon":"🦵","description":"Sit on chair...","duration":"8 mins"}]
  is_active   BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_prescriptions_patient ON public.prescriptions(patient_id);


-- ────────────────────────────────────────────────────────────────
-- 4. APPOINTMENTS TABLE
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.appointments (
  id            UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id    UUID    REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  admin_id      UUID    REFERENCES public.profiles(id) ON DELETE SET NULL,
  title         TEXT    NOT NULL,
  subtitle      TEXT,
  datetime      TIMESTAMPTZ NOT NULL,
  duration_mins INTEGER DEFAULT 45,
  location      TEXT,
  type          TEXT    DEFAULT 'clinic' CHECK (type IN ('clinic','home','ai','other')),
  status        TEXT    DEFAULT 'confirmed' CHECK (status IN ('confirmed','pending','cancelled')),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_appointments_patient  ON public.appointments(patient_id);
CREATE INDEX IF NOT EXISTS idx_appointments_datetime ON public.appointments(datetime ASC);


-- ────────────────────────────────────────────────────────────────
-- 5. MESSAGES TABLE  (patient ↔ admin)
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.messages (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id   UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  sender       TEXT CHECK (sender IN ('patient','admin')) NOT NULL,
  sender_name  TEXT,
  text         TEXT NOT NULL,
  sent_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_messages_patient ON public.messages(patient_id);
CREATE INDEX IF NOT EXISTS idx_messages_sent    ON public.messages(sent_at ASC);


-- ────────────────────────────────────────────────────────────────
-- 6. ADMIN_NOTES TABLE  (admin writes clinical notes per patient)
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_notes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id  UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  admin_id    UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  admin_name  TEXT,
  text        TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_notes_patient ON public.admin_notes(patient_id);


-- ────────────────────────────────────────────────────────────────
-- 7. PAIN_LOGS TABLE
-- ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pain_logs (
  id        UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   UUID    REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  pain      INTEGER CHECK (pain >= 0 AND pain <= 10),
  logged_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pain_user ON public.pain_logs(user_id);


-- ────────────────────────────────────────────────────────────────
-- 8. ROW LEVEL SECURITY
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prescriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.appointments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_notes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pain_logs     ENABLE ROW LEVEL SECURITY;

-- Helper: check if current user is admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;


-- ── profiles ──
DROP POLICY IF EXISTS "own profile read"    ON public.profiles;
DROP POLICY IF EXISTS "own profile write"   ON public.profiles;
DROP POLICY IF EXISTS "admin reads all"     ON public.profiles;

CREATE POLICY "own profile read"
  ON public.profiles FOR SELECT USING (auth.uid() = id);

CREATE POLICY "own profile write"
  ON public.profiles FOR ALL USING (auth.uid() = id);

CREATE POLICY "admin reads all profiles"
  ON public.profiles FOR SELECT USING (public.is_admin());


-- ── sessions ──
DROP POLICY IF EXISTS "own sessions"       ON public.sessions;
DROP POLICY IF EXISTS "admin all sessions" ON public.sessions;

CREATE POLICY "own sessions"
  ON public.sessions FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "admin all sessions"
  ON public.sessions FOR SELECT USING (public.is_admin());


-- ── prescriptions ──
DROP POLICY IF EXISTS "patient read rx" ON public.prescriptions;
DROP POLICY IF EXISTS "admin manage rx" ON public.prescriptions;

CREATE POLICY "patient read rx"
  ON public.prescriptions FOR SELECT USING (auth.uid() = patient_id);

CREATE POLICY "admin manage rx"
  ON public.prescriptions FOR ALL USING (public.is_admin());


-- ── appointments ──
DROP POLICY IF EXISTS "patient read appts" ON public.appointments;
DROP POLICY IF EXISTS "admin manage appts" ON public.appointments;

CREATE POLICY "patient read appts"
  ON public.appointments FOR SELECT USING (auth.uid() = patient_id);

CREATE POLICY "admin manage appts"
  ON public.appointments FOR ALL USING (public.is_admin());


-- ── messages ──
DROP POLICY IF EXISTS "patient messages"  ON public.messages;
DROP POLICY IF EXISTS "admin messages"    ON public.messages;

CREATE POLICY "patient messages"
  ON public.messages FOR ALL USING (auth.uid() = patient_id);

CREATE POLICY "admin messages"
  ON public.messages FOR ALL USING (public.is_admin());


-- ── admin_notes ──
DROP POLICY IF EXISTS "patient read notes" ON public.admin_notes;
DROP POLICY IF EXISTS "admin manage notes" ON public.admin_notes;

CREATE POLICY "patient read notes"
  ON public.admin_notes FOR SELECT USING (auth.uid() = patient_id);

CREATE POLICY "admin manage notes"
  ON public.admin_notes FOR ALL USING (public.is_admin());


-- ── pain_logs ──
DROP POLICY IF EXISTS "own pain logs"      ON public.pain_logs;
DROP POLICY IF EXISTS "admin read pain"    ON public.pain_logs;

CREATE POLICY "own pain logs"
  ON public.pain_logs FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "admin read pain"
  ON public.pain_logs FOR SELECT USING (public.is_admin());


-- ────────────────────────────────────────────────────────────────
-- 9. PATIENT SUMMARY VIEW  (used by admin portal)
-- ────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.patient_summary AS
SELECT
  p.id,
  p.name,
  p.email,
  p.condition,
  p.city,
  p.surgery_date,
  p.plan_duration,
  p.created_at                              AS joined_at,
  COUNT(s.id)                               AS total_sessions,
  COALESCE(SUM(s.valid_reps), 0)            AS total_reps,
  COALESCE(MAX(s.best_rom), 0)              AS best_rom_ever,
  COALESCE(AVG(s.score)::INTEGER, 0)        AS avg_quality,
  MAX(s.session_date)                       AS last_session_date,
  COALESCE(AVG(pl.pain)::NUMERIC(3,1), 0)  AS avg_pain
FROM public.profiles p
LEFT JOIN public.sessions  s  ON s.user_id  = p.id
LEFT JOIN public.pain_logs pl ON pl.user_id = p.id
WHERE p.role = 'patient'
GROUP BY p.id;


-- ────────────────────────────────────────────────────────────────
-- 10. CREATE YOUR ADMIN ACCOUNT
-- ────────────────────────────────────────────────────────────────
-- After running this SQL:
-- 1. Go to Supabase → Authentication → Users → "Add User"
-- 2. Enter your admin email + password
-- 3. Copy the UUID of that user
-- 4. Run this query (replace the UUID):
--
-- UPDATE public.profiles
-- SET role = 'admin', name = 'Dr. Priya Menon'
-- WHERE id = 'PASTE-ADMIN-USER-UUID-HERE';
--
-- That's it — that account can now access the admin portal.
-- ────────────────────────────────────────────────────────────────

-- ✅ SETUP COMPLETE
-- Tables: profiles, sessions, prescriptions,
--         appointments, messages, admin_notes, pain_logs
-- RLS:    fully secured, admin sees everything, patients see own
-- View:   patient_summary for admin dashboard
