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
  block       text not null check (block in ('kp','ka','kr','vp','cr','ch','cs','cost','rev','vl_orth','vl_belief','vl_problem','vl_sub','vl_ifthen','vl_exp','vl_res','vl_sol')),
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
  select public.is_team_teacher(tid) or coalesce(public.team_role(tid) = 'estudiante', false)
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
  if r = 'estudiante' and exists (
       select 1 from teams t2 join team_members m on m.team_id = t2.id
       where t2.course_id = t.course_id and t2.id <> t.id
         and m.user_id = auth.uid() and m.role = 'estudiante') then
    raise exception 'Ya perteneces a otro equipo de este curso. Sal de él primero (pestaña Equipo).';
  end if;
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

-- =====================================================================
--  VERSIÓN 2 · Código del curso (los estudiantes crean o eligen su equipo)
-- =====================================================================
alter table public.courses add column if not exists join_code text unique default public.gen_code();
alter table public.courses add column if not exists allow_team_creation boolean not null default true;
alter table public.teams   add column if not exists created_by uuid default auth.uid() references auth.users(id) on delete set null;

-- El equipo (como estudiante) que tengo en un curso
create or replace function public.my_team_in_course(cid uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select t.id from teams t join team_members m on m.team_id = t.id
  where t.course_id = cid and m.user_id = auth.uid() and m.role = 'estudiante' limit 1
$$;

-- Ver un curso y sus equipos a partir del código del curso
create or replace function public.course_preview(code text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  select * into c from courses where join_code = upper(trim(code));
  if not found then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'name', c.name, 'allow_team_creation', c.allow_team_creation,
    'is_owner', c.owner_id = auth.uid(),
    'my_team', public.my_team_in_course(c.id),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'description', t.description,
        'members', (select coalesce(jsonb_agg(p.full_name order by p.full_name), '[]'::jsonb)
                    from team_members m join profiles p on p.id = m.user_id
                    where m.team_id = t.id and m.role = 'estudiante'))
        order by t.name)
      from teams t where t.course_id = c.id), '[]'::jsonb));
end $$;

-- Unirse a un equipo existente del curso
create or replace function public.join_course_team(code text, tid uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare c record; mine uuid;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  select * into c from courses where join_code = upper(trim(code));
  if not found then raise exception 'Código no válido'; end if;
  if not exists (select 1 from teams where id = tid and course_id = c.id) then
    raise exception 'Ese equipo no pertenece a este curso';
  end if;
  mine := public.my_team_in_course(c.id);
  if mine = tid then return tid; end if;
  if mine is not null then
    raise exception 'Ya perteneces a otro equipo de este curso. Sal de él primero (pestaña Equipo).';
  end if;
  insert into team_members (team_id, user_id, role) values (tid, auth.uid(), 'estudiante')
  on conflict (team_id, user_id) do update set role = 'estudiante';
  return tid;
end $$;

-- Crear un equipo nuevo en el curso (queda como integrante)
create or replace function public.create_course_team(code text, p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare c record; nm text := trim(coalesce(p_name, '')); tid uuid;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  select * into c from courses where join_code = upper(trim(code));
  if not found then raise exception 'Código no válido'; end if;
  if c.owner_id = auth.uid() then
    raise exception 'Como profesor/a, crea los equipos desde el panel del curso';
  end if;
  if not c.allow_team_creation then
    raise exception 'En este curso los equipos los crea el profesor/a. Elige uno de la lista.';
  end if;
  if nm = '' or length(nm) > 80 then raise exception 'El nombre del equipo debe tener entre 1 y 80 caracteres'; end if;
  if public.my_team_in_course(c.id) is not null then
    raise exception 'Ya perteneces a otro equipo de este curso. Sal de él primero (pestaña Equipo).';
  end if;
  if exists (select 1 from teams where course_id = c.id and lower(name) = lower(nm)) then
    raise exception 'Ya existe un equipo con ese nombre en el curso. Únete a él o elige otro nombre.';
  end if;
  insert into teams (course_id, name, created_by) values (c.id, nm, auth.uid()) returning id into tid;
  insert into team_members (team_id, user_id, role) values (tid, auth.uid(), 'estudiante');
  return tid;
end $$;

-- Cambiar el código del curso
create or replace function public.regenerate_course_code(cid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_course_owner(cid) then raise exception 'Solo el profesor/a puede cambiar el código'; end if;
  update courses set join_code = public.gen_code() where id = cid;
end $$;

-- =====================================================================
--  VERSIÓN 2 · Cierres semanales del canvas
-- =====================================================================
create table if not exists public.weekly_closures (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams(id) on delete cascade,
  week        date not null,                      -- lunes de la semana cerrada
  stats       jsonb not null default '{}'::jsonb, -- conteos por componente y totales
  items       jsonb not null default '[]'::jsonb, -- foto del canvas al cerrar
  note        text not null default '',
  closed_by   uuid references auth.users(id) on delete set null,  -- vacío = cierre automático
  auto        boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz,
  unique (team_id, week)
);
create index if not exists closures_team_idx on public.weekly_closures(team_id);

-- Lunes de la semana actual, en hora de Chile
create or replace function public.current_week()
returns date language sql stable as $$
  select date_trunc('week', (now() at time zone 'America/Santiago'))::date
$$;

-- Cálculo del cierre (uso interno; no se puede llamar desde la página)
create or replace function public._close_week(tid uuid, p_note text, p_by uuid, p_auto boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  wk date := public.current_week();
  cur jsonb; prev jsonb; prev_week date;
  bstats jsonb; tot jsonb; ivw int; ivt int; has_log boolean; st jsonb; rid uuid;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'block', block, 'text', text, 'status', status)
                            order by created_at), '[]'::jsonb)
    into cur from hypotheses where team_id = tid;
  select items, week into prev, prev_week from weekly_closures
   where team_id = tid and week < wk order by week desc limit 1;
  prev := coalesce(prev, '[]'::jsonb);

  with c as (select e->>'id' id, e->>'block' block, e->>'text' txt, e->>'status' status from jsonb_array_elements(cur) e),
       p as (select e->>'id' id, e->>'block' block, e->>'text' txt, e->>'status' status from jsonb_array_elements(prev) e),
       j as (select c.block cb, p.block pb, c.status cs, p.status ps, c.txt ct, p.txt pt
               from c full join p on c.id = p.id),
       bl as (select unnest(array['kp','ka','kr','vp','cr','ch','cs','cost','rev','vl_orth','vl_belief','vl_problem','vl_sub','vl_ifthen','vl_exp','vl_res','vl_sol']) b),
       per as (
         select bl.b,
           count(*) filter (where cb = bl.b)                                         as total,
           count(*) filter (where cb = bl.b and cs = 'valid')                        as valid,
           count(*) filter (where cb = bl.b and cs = 'invalid')                      as invalid,
           count(*) filter (where cb = bl.b and cs = 'pending')                      as pending,
           count(*) filter (where cb = bl.b and pb is null)                          as added,
           count(*) filter (where pb = bl.b and cb is null)                          as removed,
           count(*) filter (where cb = bl.b and pb is not null and pb <> cb)         as moved_in,
           count(*) filter (where cb = bl.b and pb is not null and ct <> pt)         as edited,
           count(*) filter (where cb = bl.b and cs = 'valid' and coalesce(ps,'') <> 'valid')     as validated,
           count(*) filter (where cb = bl.b and cs = 'invalid' and coalesce(ps,'') <> 'invalid') as invalidated,
           count(*) filter (where cb = bl.b and pb is not null and cs = 'pending' and ps <> 'pending') as reopened,
           count(*) filter (where cb = bl.b and pb is not null and cs <> ps)         as status_changed
         from bl left join j on (j.cb = bl.b or j.pb = bl.b)
         group by bl.b),
       per2 as (select *, added + removed + moved_in + edited + status_changed as changes from per)
  select jsonb_object_agg(b, to_jsonb(per2) - 'b'),
         jsonb_build_object(
           'total', sum(total), 'valid', sum(valid), 'invalid', sum(invalid), 'pending', sum(pending),
           'added', sum(added), 'removed', sum(removed), 'moved_in', sum(moved_in), 'edited', sum(edited),
           'validated', sum(validated), 'invalidated', sum(invalidated), 'reopened', sum(reopened),
           'status_changed', sum(status_changed), 'changes', sum(changes))
    into bstats, tot from per2;

  select count(*) filter (where interview_date >= wk and interview_date < wk + 7), count(*)
    into ivw, ivt from interviews where team_id = tid;
  select exists (select 1 from logs where team_id = tid and week = wk) into has_log;

  st := jsonb_build_object('blocks', bstats, 'totals', tot,
          'interviews_week', ivw, 'interviews_total', ivt, 'log_written', has_log,
          'baseline_week', prev_week);

  if p_auto then
    insert into weekly_closures (team_id, week, stats, items, note, closed_by, auto)
    values (tid, wk, st, cur, '', null, true)
    on conflict (team_id, week) do nothing
    returning id into rid;
  else
    insert into weekly_closures (team_id, week, stats, items, note, closed_by, auto)
    values (tid, wk, st, cur, coalesce(p_note, ''), p_by, false)
    on conflict (team_id, week) do update
      set stats = excluded.stats, items = excluded.items,
          note = case when excluded.note <> '' then excluded.note else weekly_closures.note end,
          closed_by = excluded.closed_by, auto = false, updated_at = now()
    returning id into rid;
  end if;
  return rid;
end $$;

-- Cerrar la semana de un equipo (estudiantes del equipo o profesor/a)
create or replace function public.close_week(tid uuid, p_note text default '')
returns uuid language plpgsql security definer set search_path = public as $$
begin
  if not public.can_edit_team(tid) then raise exception 'Sin permiso para cerrar la semana de este equipo'; end if;
  return public._close_week(tid, p_note, auth.uid(), false);
end $$;

-- Cerrar la semana de todos los equipos de un curso (profesor/a)
create or replace function public.close_course_week(cid uuid)
returns int language plpgsql security definer set search_path = public as $$
declare t record; n int := 0;
begin
  if not public.is_course_owner(cid) then raise exception 'Solo el profesor/a puede cerrar la semana del curso'; end if;
  for t in select id from teams where course_id = cid loop
    perform public._close_week(t.id, '', auth.uid(), false); n := n + 1;
  end loop;
  return n;
end $$;

-- Cierre automático de todos los equipos (lo usa la tarea programada)
create or replace function public.close_all_weeks()
returns int language plpgsql security definer set search_path = public as $$
declare t record; n int := 0;
begin
  for t in select id from teams loop
    if public._close_week(t.id, '', null, true) is not null then n := n + 1; end if;
  end loop;
  return n;
end $$;

revoke execute on function public._close_week(uuid, text, uuid, boolean) from public, anon, authenticated;
revoke execute on function public.close_all_weeks() from public, anon, authenticated;

alter table public.weekly_closures enable row level security;
drop policy if exists closures_select on public.weekly_closures;
create policy closures_select on public.weekly_closures for select to authenticated
  using (public.can_read_team(team_id));
drop policy if exists closures_delete on public.weekly_closures;
create policy closures_delete on public.weekly_closures for delete to authenticated
  using (public.is_team_teacher(team_id));
-- (no hay permiso directo para crear o editar cierres: solo mediante close_week)

-- =====================================================================
--  VERSIÓN 3 · Herramienta por equipo (BMC o Value Lab), RCT e investigación
-- =====================================================================
-- Herramienta de cada equipo: 'bmc', 'valuelab' o vacío (sin asignar)
alter table public.teams add column if not exists tool text default 'bmc';
alter table public.teams drop constraint if exists teams_tool_check;
alter table public.teams add constraint teams_tool_check check (tool is null or tool in ('bmc', 'valuelab'));

alter table public.courses add column if not exists rct_mode boolean not null default false;
alter table public.courses add column if not exists research_enabled boolean not null default false;
alter table public.courses add column if not exists consent_text text not null default '';

-- Elementos del Value Lab en la misma tabla que las hipótesis del BMC
alter table public.hypotheses drop constraint if exists hypotheses_block_check;
alter table public.hypotheses add constraint hypotheses_block_check check (block in ('kp','ka','kr','vp','cr','ch','cs','cost','rev','vl_orth','vl_belief','vl_problem','vl_sub','vl_ifthen','vl_exp','vl_res','vl_sol'));
alter table public.hypotheses add column if not exists parent_id uuid references public.hypotheses(id) on delete set null;

-- En modo RCT, los equipos nuevos quedan sin herramienta hasta que el profesor/a la asigne
create or replace function public.teams_default_tool()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from courses where id = new.course_id and rct_mode) then new.tool := null; end if;
  return new;
end $$;
drop trigger if exists teams_default_tool on public.teams;
create trigger teams_default_tool before insert on public.teams
  for each row execute function public.teams_default_tool();

-- Registro de asignaciones (para reportar el RCT)
create table if not exists public.assignment_log (
  id          uuid primary key default gen_random_uuid(),
  course_id   uuid not null,
  team_id     uuid not null,
  team_name   text,
  old_tool    text,
  new_tool    text,
  method      text not null default 'manual',     -- 'manual' o 'aleatoria'
  batch_id    uuid,
  seed        double precision,
  changed_by  uuid,
  changed_at  timestamptz not null default now()
);
create index if not exists assignment_course_idx on public.assignment_log(course_id);

create or replace function public.log_tool_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' or new.tool is distinct from old.tool then
    insert into assignment_log (course_id, team_id, team_name, old_tool, new_tool, method, batch_id, seed, changed_by)
    values (new.course_id, new.id, new.name,
            case when tg_op = 'UPDATE' then old.tool end, new.tool,
            coalesce(nullif(current_setting('bitacora.assign_method', true), ''),
                     case when tg_op = 'INSERT' then 'creación' else 'manual' end),
            nullif(current_setting('bitacora.assign_batch', true), '')::uuid,
            nullif(current_setting('bitacora.assign_seed', true), '')::double precision,
            auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists teams_log_tool on public.teams;
create trigger teams_log_tool after insert or update of tool on public.teams
  for each row execute function public.log_tool_change();

-- Asignación aleatoria balanceada de los equipos sin herramienta
create or replace function public.randomize_course_tools(cid uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  s double precision := random();
  b uuid := gen_random_uuid();
  nb int; nv int; t record; arm text; n int := 0;
begin
  if not public.is_course_owner(cid) then raise exception 'Solo el profesor/a puede asignar herramientas'; end if;
  perform setseed(s * 2 - 1);
  select count(*) filter (where tool = 'bmc'), count(*) filter (where tool = 'valuelab')
    into nb, nv from teams where course_id = cid;
  perform set_config('bitacora.assign_method', 'aleatoria', true);
  perform set_config('bitacora.assign_batch', b::text, true);
  perform set_config('bitacora.assign_seed', s::text, true);
  for t in select id from teams where course_id = cid and tool is null order by random() loop
    if nb < nv then arm := 'bmc';
    elsif nv < nb then arm := 'valuelab';
    else arm := case when random() < 0.5 then 'bmc' else 'valuelab' end;
    end if;
    update teams set tool = arm where id = t.id;
    if arm = 'bmc' then nb := nb + 1; else nv := nv + 1; end if;
    n := n + 1;
  end loop;
  perform set_config('bitacora.assign_method', '', true);
  perform set_config('bitacora.assign_batch', '', true);
  perform set_config('bitacora.assign_seed', '', true);
  return jsonb_build_object('assigned', n, 'bmc', nb, 'valuelab', nv, 'seed', s, 'batch', b);
end $$;

alter table public.assignment_log enable row level security;
drop policy if exists assignment_select on public.assignment_log;
create policy assignment_select on public.assignment_log for select to authenticated
  using (public.is_course_owner(course_id));

-- Registro de eventos: cada creación, cambio o eliminación, con fecha, autor y valores
create table if not exists public.events (
  id         bigint generated always as identity primary key,
  course_id  uuid,
  team_id    uuid,
  entity     text not null,      -- tabla: hypotheses, interviews, logs, ...
  entity_id  text,
  action     text not null,      -- INSERT, UPDATE, DELETE
  actor      uuid,
  at         timestamptz not null default now(),
  data       jsonb not null default '{}'::jsonb
);
create index if not exists events_course_idx on public.events(course_id);
create index if not exists events_team_idx on public.events(team_id);

create or replace function public.log_event()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  rn jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  ro jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  r  jsonb := coalesce(rn, ro);
  tid uuid; cid uuid; d jsonb; eid text;
begin
  if tg_table_name = 'teams' then tid := (r->>'id')::uuid; cid := (r->>'course_id')::uuid;
  else tid := (r->>'team_id')::uuid; select course_id into cid from teams where id = tid;
  end if;
  eid := coalesce(r->>'id', r->>'user_id');
  if tg_op = 'UPDATE' then
    select jsonb_object_agg(n.key, jsonb_build_object('old', o.value, 'new', n.value)) into d
      from jsonb_each(rn) n join jsonb_each(ro) o using (key)
     where n.value is distinct from o.value and n.key not in ('updated_at', 'updated_by');
    if d is null then return new; end if;
  elsif tg_op = 'INSERT' then d := jsonb_build_object('new', rn);
  else d := jsonb_build_object('old', ro);
  end if;
  insert into events (course_id, team_id, entity, entity_id, action, actor, data)
  values (cid, tid, tg_table_name, eid, tg_op, auth.uid(), d);
  return coalesce(new, old);
end $$;

do $$
declare tbl text;
begin
  foreach tbl in array array['teams','team_members','hypotheses','interviews','logs','feedback','snapshots','weekly_closures'] loop
    execute format('drop trigger if exists %1$s_events on public.%1$s', tbl);
    execute format('create trigger %1$s_events after insert or update or delete on public.%1$s for each row execute function public.log_event()', tbl);
  end loop;
end $$;

alter table public.events enable row level security;
drop policy if exists events_select on public.events;
create policy events_select on public.events for select to authenticated
  using (public.is_course_owner(course_id));

-- Consentimiento informado (por estudiante y curso)
create table if not exists public.research_consents (
  course_id    uuid not null references public.courses(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade default auth.uid(),
  consent      boolean not null,
  answered_at  timestamptz not null default now(),
  primary key (course_id, user_id)
);
alter table public.research_consents enable row level security;
drop policy if exists consents_select on public.research_consents;
create policy consents_select on public.research_consents for select to authenticated
  using (user_id = auth.uid() or public.is_course_owner(course_id));
drop policy if exists consents_insert on public.research_consents;
create policy consents_insert on public.research_consents for insert to authenticated
  with check (user_id = auth.uid() and public.in_course(course_id));
drop policy if exists consents_update on public.research_consents;
create policy consents_update on public.research_consents for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

revoke execute on function public.randomize_course_tools(uuid) from anon;

-- Nadie sin sesión puede leer ni escribir
revoke all on all tables in schema public from anon;
revoke execute on function public.join_team(text) from anon;
revoke execute on function public.update_team_info(uuid, text, text, int) from anon;
revoke execute on function public.regenerate_codes(uuid) from anon;
revoke execute on function public.course_preview(text) from anon;
revoke execute on function public.join_course_team(text, uuid) from anon;
revoke execute on function public.create_course_team(text, text) from anon;
revoke execute on function public.regenerate_course_code(uuid) from anon;
revoke execute on function public.close_week(uuid, text) from anon;
revoke execute on function public.close_course_week(uuid) from anon;

-- ---------- Actualización en vivo ----------
do $$
declare tbl text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach tbl in array array['team_members','hypotheses','interviews','logs','feedback','snapshots','weekly_closures'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = tbl) then
        execute format('alter publication supabase_realtime add table public.%I', tbl);
      end if;
    end loop;
  end if;
end $$;

-- Versión 3 (herramienta por equipo: BMC o Value Lab; datos de investigación).
-- Listo. Si ves "Success. No rows returned", la base de datos quedó configurada.
