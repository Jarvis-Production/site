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

-- 3. Автоматическое создание профиля при регистрации (БЕЗ ключа — ключ выдаёт админ)
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

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 4. Функция сброса HWID (только для админа)
CREATE OR REPLACE FUNCTION reset_hwid(target_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE profiles SET hwid = NULL, hwid_limit = hwid_limit WHERE id = target_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Функция генерации ключей (формат: JX-XXXXX-XXXXX-XXXXX-XXXXX)
CREATE OR REPLACE FUNCTION generate_key()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    result TEXT := 'JX-';
    i INT;
    j INT;
BEGIN
    FOR i IN 1..4 LOOP
        FOR j IN 1..5 LOOP
            result := result || substr(chars, 1 + (random() * length(chars))::int, 1);
        END LOOP;
        IF i < 4 THEN
            result := result || '-';
        END IF;
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- 6. Индексы
CREATE INDEX IF NOT EXISTS idx_profiles_license_key ON profiles(license_key);
CREATE INDEX IF NOT EXISTS idx_profiles_hwid ON profiles(hwid);
