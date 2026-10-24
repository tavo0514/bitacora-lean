-- =====================================================================
--  Bitácora Lean · Cierre semanal AUTOMÁTICO (opcional)
--  Cierra la semana de todos los equipos cada domingo a las 23:59
--  (hora de Chile en horario de verano; en invierno corre a las 22:59).
--  Si un equipo ya cerró su semana a mano, se respeta ese cierre.
--
--  Cómo usarlo: ejecuta antes schema.sql (versión 2). Luego, en Supabase,
--  abre "SQL Editor", pega este archivo y presiona "Run". Basta una vez.
--  Si da un error sobre "pg_cron", actívalo en Integrations → Cron
--  y vuelve a ejecutar este archivo.
-- =====================================================================
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

-- Lunes 02:59 UTC = domingo 23:59 en Chile (UTC-3). Si ya existía, se actualiza.
select cron.schedule('bitacora-cierre-semanal', '59 2 * * 1', 'select public.close_all_weeks()');

-- Para DESACTIVARLO más adelante, ejecuta solo esta línea:
-- select cron.unschedule('bitacora-cierre-semanal');
