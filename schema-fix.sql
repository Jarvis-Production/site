-- ========================================
-- ИСПРАВЛЕНИЕ: Создание таблицы profiles + триггер
-- Выполни в Supabase Dashboard → SQL Editor
-- ========================================

-- 1. Создаём таблицу profiles (если не существует)
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT NOT NULL,
    license_key TEXT UNIQUE,
    hwid TEXT,
    hwid_limit INT DEFAULT 1,
    key_type TEXT DEFAULT 'client',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_login TIMESTAMPTZ DEFAULT now()
);

-- 2. Включаем RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 3. Политики (пересоздаём если существуют)
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Service role full access" ON profiles;

CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Service role full access" ON profiles FOR ALL USING (auth.role() = 'service_role');

-- 4. Триггер: создаёт профиль при регистрации (БЕЗ ключа)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.profiles (id, username, license_key)
    VALUES (
        new.id,
        COALESCE(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        NULL
    );
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Удаляем старый триггер и создаём новый
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 6. Убираем старые ключи у существующих юзеров (если нужно)
-- UPDATE profiles SET license_key = NULL WHERE license_key IS NOT NULL;

-- 7. Таблица телеметрии
CREATE TABLE IF NOT EXISTS telemetry_logs (
    id SERIAL PRIMARY KEY,
    hwid VARCHAR(128) NOT NULL,
    server VARCHAR(255) NOT NULL,
    ip VARCHAR(45) NOT NULL,
    brand VARCHAR(255) NOT NULL,
    version VARCHAR(32) NOT NULL,
    timestamp BIGINT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_telemetry_logs_hwid ON telemetry_logs (hwid);
CREATE INDEX IF NOT EXISTS idx_telemetry_logs_timestamp ON telemetry_logs (timestamp DESC);

-- 8. RLS для телеметрии (anon может писать, service role читает)
ALTER TABLE telemetry_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can insert telemetry" ON telemetry_logs;
DROP POLICY IF EXISTS "Service role reads telemetry" ON telemetry_logs;
CREATE POLICY "Anyone can insert telemetry" ON telemetry_logs FOR INSERT WITH CHECK (true);
CREATE POLICY "Service role reads telemetry" ON telemetry_logs FOR SELECT USING (auth.role() = 'service_role');
