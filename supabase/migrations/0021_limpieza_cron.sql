-- =====================================================================
-- Cuadre · Migración 0021: limpieza semanal del historial del reloj
--   pg_cron anota cada búsqueda de la tasa (unas 100 líneas al día).
--   Los domingos a las 3 a. m. (hora de Caracas) se borra lo de más de
--   7 días. Las respuestas de dolarapi (pg_net) ya se borran solas.
-- =====================================================================
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'Sin pg_cron: no hay historial que limpiar aquí';
    return;
  end if;
  perform cron.unschedule(jobname) from cron.job where jobname = 'limpiar-historial-reloj';
  perform cron.schedule('limpiar-historial-reloj', '0 7 * * 0',   -- 7:00 UTC = 3:00 a. m. en Caracas
    $q$delete from cron.job_run_details where end_time < now() - interval '7 days'$q$);
end $$;
