-- Supabase SQL Schema для Jartix
-- Выполни в Supabase Dashboard → SQL Editor

-- 1. Таблица профилей пользователей
CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    username TEXT NOT NULL,
    license_key TEXT UNIQUE,
    hwid TEXT,
    hwid_limit INT DEFAULT 1,
    key_type TEXT DEFAULT 'client',
    active BOOLEAN DEFAULT true,
    license_active BOOLEAN DEFAULT false,
    banned BOOLEAN DEFAULT false,
    expires_at TIMESTAMPTZ,
    last_ip TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    last_login TIMESTAMPTZ DEFAULT now()
);

-- 2. RLS (Row Level Security) — пользователи видят только свой профиль
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
    ON profiles FOR SELECT
    USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (auth.uid() = id);

-- 3. Функция генерации ключей (формат: JX-XXXXX-XXXXX-XXXXX-XXXXX)
CREATE OR REPLACE FUNCTION generate_key()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result TEXT := 'JX-';
    i INT;
BEGIN
    FOR i IN 1..20 LOOP
        IF i > 1 AND (i - 1) % 5 = 0 THEN
            result := result || '-';
        END IF;
        result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- 4. Автоматическое создание профиля при регистрации + генерация ключа
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
    new_key TEXT;
    i INT;
BEGIN
    FOR i IN 1..5 LOOP
        BEGIN
            new_key := generate_key();
            INSERT INTO public.profiles (id, username, license_key)
            VALUES (
                new.id,
                COALESCE(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
                new_key
            );
            RETURN new;
        EXCEPTION WHEN unique_violation THEN
            CONTINUE;
        END;
    END LOOP;
    INSERT INTO public.profiles (id, username, license_key)
    VALUES (
        new.id,
        COALESCE(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
        'JX-' || replace(gen_random_uuid()::text, '-', '')
    )
    ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username;
    RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 5. Функция сброса HWID (только для админа)
CREATE OR REPLACE FUNCTION reset_hwid(target_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE profiles SET hwid = NULL, hwid_limit = hwid_limit WHERE id = target_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Индексы
CREATE INDEX IF NOT EXISTS idx_profiles_license_key ON profiles(license_key);
CREATE INDEX IF NOT EXISTS idx_profiles_hwid ON profiles(hwid);
