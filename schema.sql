-- =====================================================================
--  Bitácora Lean · Base de datos para Supabase
--  Cómo usarlo: en Supabase abre "SQL Editor", pega TODO este archivo
--  y presiona "Run". Se puede volver a ejecutar sin perder datos.
-- =====================================================================

-- ---------- Perfiles (nombre visible de cada persona) ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null default '',
  email       text,
  created_at  timestamptz not null default now()
);

-- Crea el perfil automáticamente cuando alguien se registra
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), new.email)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Código corto de 6 caracteres para unirse a un equipo
create or replace function public.gen_code()
returns text language sql volatile as $$
  select upper(substr(md5(gen_random_uuid()::text), 1, 6))
$$;

-- ---------- Cursos y equipos ----------
create table if not exists public.courses (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  owner_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table if not exists public.teams (
  id            uuid primary key default gen_random_uuid(),
  course_id     uuid not null references public.courses(id) on delete cascade,
  name          text not null,
  description   text not null default '',
  goal          int  not null default 10 check (goal between 1 and 200),
  student_code  text not null unique default public.gen_code(),
  mentor_code   text not null unique default public.gen_code(),
  created_at    timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id    uuid not null references public.teams(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  role       text not null check (role in ('estudiante', 'mentor')),
  joined_at  timestamptz not null default now(),
  primary key (team_id, user_id)
);

-- ---------- Trabajo de cada equipo ----------
create table if not exists public.hypotheses (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams(id) on delete cascade,
  block       text not null check (block in ('kp','ka','kr','vp','cr','ch','cs','cost','rev')),
  text        text not null,
  status      text not null default 'pending' check (status in ('pending','valid','invalid')),
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id) on delete set null,
  updated_at  timestamptz
);

create table if not exists public.interviews (
  id              uuid primary key default gen_random_uuid(),
  team_id         uuid not null references public.teams(id) on delete cascade,
  person          text not null,
  person_role     text not null default '',
  segment         text not null default '',
  interview_date  date not null default current_date,
  channel         text not null default 'Presencial',
  notes           text not null default '',
  insights        text not null default '',
  evidence        jsonb not null default '{}'::jsonb,
  created_by      uuid default auth.uid() references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz
);

create table if not exists public.logs (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams(id) on delete cascade,
  week        date not null,
  title       text not null default '',
  learned     text not null default '',
  changed     text not null default '',
  next_steps  text not null default '',
  pivot       boolean not null default false,
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);

create table if not exists public.feedback (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references public.teams(id) on delete cascade,
  block        text not null default 'general',
  text         text not null,
  resolved     boolean not null default false,
  created_by   uuid default auth.uid() references auth.users(id) on delete set null,
  created_at   timestamptz not null default now(),
  resolved_by  uuid references auth.users(id) on delete set null,
  resolved_at  timestamptz
);

create table if not exists public.snapshots (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams(id) on delete cascade,
  label       text not null,
  items       jsonb not null default '[]'::jsonb,
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);

create index if not exists teams_course_idx       on public.teams(course_id);
create index if not exists members_user_idx       on public.team_members(user_id);
create index if not exists hypotheses_team_idx    on public.hypotheses(team_id);
create index if not exists interviews_team_idx    on public.interviews(team_id);
create index if not exists logs_team_idx          on public.logs(team_id);
create index if not exists feedback_team_idx      on public.feedback(team_id);
create index if not exists snapshots_team_idx     on public.snapshots(team_id);

-- ---------- Funciones de permisos ----------
-- ¿Soy el profesor/a dueño de este curso?
create or replace function public.is_course_owner(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from courses where id = cid and owner_id = auth.uid())
$$;

-- ¿Soy el profesor/a del curso al que pertenece este equipo?
create or replace function public.is_team_teacher(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from teams t join courses c on c.id = t.course_id
    where t.id = tid and c.owner_id = auth.uid())
$$;

-- Mi rol dentro de un equipo: 'estudiante', 'mentor' o null
create or replace function public.team_role(tid uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from team_members where team_id = tid and user_id = auth.uid()
$$;

create or replace function public.can_read_team(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_team_teacher(tid) or public.team_role(tid) is not null
$$;

-- Editan el canvas, entrevistas, bitácora y versiones: estudiantes del equipo y el profesor/a
create or replace function public.can_edit_team(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_team_teacher(tid) or public.team_role(tid) = 'estudiante'
$$;

-- ¿Participo en algún equipo de este curso?
create or replace function public.in_course(cid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from teams t join team_members m on m.team_id = t.id
    where t.course_id = cid and m.user_id = auth.uid())
$$;

-- ¿Puedo ver el nombre de esta persona? (compartimos equipo, o una de las dos es profesor/a del otro)
create or replace function public.can_see_profile(pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select pid = auth.uid()
    or exists (select 1 from team_members a join team_members b on a.team_id = b.team_id
               where a.user_id = auth.uid() and b.user_id = pid)
    or exists (select 1 from team_members m join teams t on t.id = m.team_id
               join courses c on c.id = t.course_id
               where m.user_id = pid and c.owner_id = auth.uid())
    or exists (select 1 from team_members m join teams t on t.id = m.team_id
               join courses c on c.id = t.course_id
               where m.user_id = auth.uid() and c.owner_id = pid)
$$;

-- ---------- Acciones especiales ----------
-- Unirse a un equipo con su código (de estudiante o de mentor)
create or replace function public.join_team(code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare t record; r text;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  select * into t from teams
   where student_code = upper(trim(code)) or mentor_code = upper(trim(code)) limit 1;
  if not found then raise exception 'Código no válido'; end if;
  r := case when t.student_code = upper(trim(code)) then 'estudiante' else 'mentor' end;
  insert into team_members (team_id, user_id, role) values (t.id, auth.uid(), r)
  on conflict (team_id, user_id) do nothing;
  return t.id;
end $$;

-- Editar nombre, descripción y meta del equipo (estudiantes o profesor/a)
create or replace function public.update_team_info(tid uuid, p_name text, p_description text, p_goal int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_edit_team(tid) then raise exception 'Sin permiso para editar este equipo'; end if;
  update teams set name = coalesce(nullif(trim(p_name), ''), name),
                   description = coalesce(p_description, ''),
                   goal = greatest(1, least(200, coalesce(p_goal, goal)))
   where id = tid;
end $$;

-- Generar códigos nuevos (si un código se filtró)
create or replace function public.regenerate_codes(tid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_team_teacher(tid) then raise exception 'Solo el profesor/a puede cambiar los códigos'; end if;
  update teams set student_code = public.gen_code(), mentor_code = public.gen_code() where id = tid;
end $$;

-- ---------- Reglas de acceso (Row Level Security) ----------
alter table public.profiles     enable row level security;
alter table public.courses      enable row level security;
alter table public.teams        enable row level security;
alter table public.team_members enable row level security;
alter table public.hypotheses   enable row level security;
alter table public.interviews   enable row level security;
alter table public.logs         enable row level security;
alter table public.feedback     enable row level security;
alter table public.snapshots    enable row level security;

-- Perfiles
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (public.can_see_profile(id));
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Cursos
drop policy if exists courses_select on public.courses;
create policy courses_select on public.courses for select to authenticated
  using (owner_id = auth.uid() or public.in_course(id));
drop policy if exists courses_insert on public.courses;
create policy courses_insert on public.courses for insert to authenticated
  with check (owner_id = auth.uid());
drop policy if exists courses_update on public.courses;
create policy courses_update on public.courses for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());
drop policy if exists courses_delete on public.courses;
create policy courses_delete on public.courses for delete to authenticated
  using (owner_id = auth.uid());

-- Equipos
drop policy if exists teams_select on public.teams;
create policy teams_select on public.teams for select to authenticated
  using (public.is_course_owner(course_id) or public.team_role(id) is not null);
drop policy if exists teams_insert on public.teams;
create policy teams_insert on public.teams for insert to authenticated
  with check (public.is_course_owner(course_id));
drop policy if exists teams_update on public.teams;
create policy teams_update on public.teams for update to authenticated
  using (public.is_team_teacher(id)) with check (public.is_course_owner(course_id));
drop policy if exists teams_delete on public.teams;
create policy teams_delete on public.teams for delete to authenticated
  using (public.is_team_teacher(id));

-- Integrantes (para entrar se usa join_team)
drop policy if exists members_select on public.team_members;
create policy members_select on public.team_members for select to authenticated
  using (public.can_read_team(team_id));
drop policy if exists members_delete on public.team_members;
create policy members_delete on public.team_members for delete to authenticated
  using (user_id = auth.uid() or public.is_team_teacher(team_id));
drop policy if exists members_update on public.team_members;
create policy members_update on public.team_members for update to authenticated
  using (public.is_team_teacher(team_id)) with check (public.is_team_teacher(team_id));

-- Hipótesis, entrevistas, bitácora y versiones: leen todos los del equipo, editan estudiantes y profesor/a
do $$
declare tbl text;
begin
  foreach tbl in array array['hypotheses','interviews','logs','snapshots'] loop
    execute format('drop policy if exists %1$s_select on public.%1$s', tbl);
    execute format('create policy %1$s_select on public.%1$s for select to authenticated using (public.can_read_team(team_id))', tbl);
    execute format('drop policy if exists %1$s_insert on public.%1$s', tbl);
    execute format('create policy %1$s_insert on public.%1$s for insert to authenticated with check (public.can_edit_team(team_id))', tbl);
    execute format('drop policy if exists %1$s_update on public.%1$s', tbl);
    execute format('create policy %1$s_update on public.%1$s for update to authenticated using (public.can_edit_team(team_id)) with check (public.can_edit_team(team_id))', tbl);
    execute format('drop policy if exists %1$s_delete on public.%1$s', tbl);
    execute format('create policy %1$s_delete on public.%1$s for delete to authenticated using (public.can_edit_team(team_id))', tbl);
  end loop;
end $$;

-- Retroalimentación: todos los del equipo (también mentores) comentan y marcan como resuelto
drop policy if exists feedback_select on public.feedback;
create policy feedback_select on public.feedback for select to authenticated
  using (public.can_read_team(team_id));
drop policy if exists feedback_insert on public.feedback;
create policy feedback_insert on public.feedback for insert to authenticated
  with check (public.can_read_team(team_id) and created_by = auth.uid());
drop policy if exists feedback_update on public.feedback;
create policy feedback_update on public.feedback for update to authenticated
  using (public.can_read_team(team_id)) with check (public.can_read_team(team_id));
drop policy if exists feedback_delete on public.feedback;
create policy feedback_delete on public.feedback for delete to authenticated
  using (created_by = auth.uid() or public.is_team_teacher(team_id));

-- Nadie sin sesión puede leer ni escribir
revoke all on all tables in schema public from anon;
revoke execute on function public.join_team(text) from anon;
revoke execute on function public.update_team_info(uuid, text, text, int) from anon;
revoke execute on function public.regenerate_codes(uuid) from anon;

-- ---------- Actualización en vivo ----------
do $$
declare tbl text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach tbl in array array['team_members','hypotheses','interviews','logs','feedback','snapshots'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = tbl) then
        execute format('alter publication supabase_realtime add table public.%I', tbl);
      end if;
    end loop;
  end if;
end $$;

-- Listo. Si ves "Success. No rows returned", la base de datos quedó configurada.
