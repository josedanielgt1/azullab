-- =====================================================================
-- Cuadre · Migración 0022: la tasa del BCV se usa apenas se publica
--   El BCV publica en días hábiles entre las 4:30 y las 7:00 p. m. la tasa
--   del día hábil siguiente (visto en las publicaciones de oct-nov 2026).
--   A pedido del cliente, la tasa vigente es siempre la última publicada:
--   la del jueves se usa desde que sale el miércoles en la tarde.
--   1. tasa_del_dia(): para hoy (o una fecha futura) da la última publicada;
--      para una fecha pasada (venta sin internet, factura de compra) sigue
--      dando la que valía ese día.
--   2. El reloj lee la página del BCV (función «tasa-bcv») cada 5 minutos de
--      3:00 a 7:55 p. m. y cada hora el resto del día, lunes a viernes.
--      dolarapi.com, que se entera horas después, queda como respaldo.
-- =====================================================================

-- 1
create or replace function tasa_del_dia(f date default current_date) returns numeric
language sql stable security definer set search_path = public as $$
  select tasa from tasas_bcv
  where coalesce(f, (now() at time zone 'America/Caracas')::date) >= (now() at time zone 'America/Caracas')::date or fecha <= f
  order by fecha desc limit 1
$$;

-- 2 (solo donde existen pg_cron y pg_net, como en Supabase)
do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') or not exists (select 1 from pg_extension where extname = 'pg_net') then
    raise notice 'Sin pg_cron o pg_net: la lectura del BCV no se programa aquí';
    return;
  end if;
  execute $f$
    create or replace function leer_tasa_bcv() returns void
    language sql security definer set search_path = public, extensions as $q$
      select net.http_get('https://sklqsvnyecyhqvmnulir.supabase.co/functions/v1/tasa-bcv', timeout_milliseconds := 60000);
    $q$ $f$;
  execute 'revoke execute on function leer_tasa_bcv() from public, anon, authenticated';
  perform cron.unschedule(jobname) from cron.job where jobname in ('tasa-bcv-pedir', 'tasa-bcv-guardar', 'tasa-bcv-directo', 'tasa-bcv-directo-dia', 'tasa-bcv-directo-noche');
  -- pg_cron va en hora UTC (Caracas = UTC − 4)
  perform cron.schedule('tasa-bcv-directo',       '*/5 19-23 * * 1-5', 'select leer_tasa_bcv()');   -- 3:00 a 7:55 p. m., cada 5 minutos
  perform cron.schedule('tasa-bcv-directo-dia',   '0 11-18 * * 1-5',   'select leer_tasa_bcv()');   -- 7:00 a. m. a 2:00 p. m., cada hora
  perform cron.schedule('tasa-bcv-directo-noche', '0 0-3 * * 2-6',     'select leer_tasa_bcv()');   -- 8:00 a 11:00 p. m., cada hora
end $$;
