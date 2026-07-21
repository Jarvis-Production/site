# Jartix Website

## Бесплатный хостинг

### Вариант 1: Cloudflare Pages (рекомендую)
1. Загрузи код на GitHub
2. Зайди на https://dash.cloudflare.com → Pages → Create a project
3. Подключи GitHub репозиторий
4. Build command: оставь пустым
5. Output directory: `/` или `.` (корень)
6. Нажми Deploy

### Вариант 2: GitHub Pages
1. Загрузи код на GitHub
2. Settings → Pages → Source: Deploy from branch → main
3. Через 1-2 минуты сайт будет доступен по URL

### Вариант 3: Vercel
1. Зайди на https://vercel.com
2. Подключи GitHub репозиторий
3. Framework: Other
4. Build command: оставь пустым
5. Deploy

## Настройка базы данных (Supabase)

1. Зайди на https://supabase.com и создай проект (бесплатно)
2. В Dashboard → SQL Editor выполни содержимое `schema.sql`
3. В Settings → API скопируй:
   - `SUPABASE_URL` (например `https://xxxxx.supabase.co`)
   - `SUPABASE_ANON_KEY` (публиключный ключ)
4. Вставь их в `auth.html` в переменные:
   ```javascript
   const SUPABASE_URL = 'https://xxxxx.supabase.co';
   const SUPABASE_ANON_KEY = 'eyJhbGci...';
   ```

## Структура файлов

```
index.html      — Главная страница (лендинг)
auth.html       — Регистрация / Вход / Кабинет
schema.sql      — SQL-схема для Supabase
mc-bg.png       — Фоновое изображение
```
