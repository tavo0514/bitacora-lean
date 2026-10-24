-- =====================================================================
--  Bitácora Lean · Convertir una cuenta en ADMINISTRADOR de la plataforma
--  El administrador activa las cuentas de profesor (las que pueden crear cursos).
--
--  Cómo usarlo (una sola vez):
--   1. Crea tu cuenta en la página, si no la tienes.
--   2. Más abajo, cambia el correo de ejemplo por el correo con que te registraste
--      (deja las comillas simples).
--   3. En Supabase → SQL Editor → New query, pega este archivo y presiona Run.
--   Debe aparecer una fila con tu correo. Si no aparece nada, el correo no
--   coincide con ninguna cuenta: revísalo.
-- =====================================================================
insert into public.app_admins (user_id)
select id from auth.users where lower(email) = lower('grioss5@estudiante.uc.cl')
on conflict (user_id) do nothing;

select u.email as administrador from public.app_admins a join auth.users u on u.id = a.user_id;
