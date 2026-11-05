-- =====================================================================
-- Cuadre · Migración 0020: tasa BCV automática
--   1. «Hoy» en la base es el de Caracas (antes, desde las 8 p. m. la base
--      ya estaba en el día siguiente, porque usaba la hora de Londres).
--   2. La tasa de un día nunca es una con fecha futura: la que el BCV
--      publica a las 5 p. m. vale para el día hábil siguiente.
--   3. registrar_tasa_bcv(): guarda la tasa de dolarapi.com con su fecha
--      valor. Lo que escribió el dueño a mano manda sobre lo automático.
--   4. El reloj de la base (pg_cron + pg_net) la busca cada 5 minutos de
--      9:00 a 10:55 a. m. y de 5:00 a 6:55 p. m. (lunes a viernes), y una
--      vez por hora entre medio, sin que nadie entre al sistema.
-- =====================================================================

-- 1
do $$ begin execute format('alter database %I set timezone to %L', current_database(), 'America/Caracas'); end $$;
set timezone to 'America/Caracas';

-- 2
create or replace function tasa_del_dia(f date default current_date) returns numeric
language sql stable security definer set search_path = public as $$
  select tasa from tasas_bcv
  where fecha <= least(coalesce(f, (now() at time zone 'America/Caracas')::date), (now() at time zone 'America/Caracas')::date)
  order by fecha desc limit 1
$$;

-- 3
-- Fecha valor: lo publicado desde las 3 p. m. vale para el día hábil siguiente (viernes en la tarde → lunes)
create or replace function fecha_valor_bcv(publicada timestamptz) returns date
language plpgsql stable set search_path = public as $$
declare l timestamp := publicada at time zone 'America/Caracas'; d date := l::date;
begin
  if l::time >= time '15:00' then d := d + 1; end if;
  while extract(isodow from d) > 5 loop d := d + 1; end loop;
  return d;
end $$;

create or replace function registrar_tasa_bcv(j jsonb, p_fuente text default 'BCV vía dolarapi.com') returns date
language plpgsql security definer set search_path = public as $$
declare
  v numeric := coalesce(nullif(j->>'promedio', '')::numeric, nullif(j->>'venta', '')::numeric);
  pub timestamptz := nullif(j->>'fechaActualizacion', '')::timestamptz;
  f date; actual tasas_bcv; previa numeric;
begin
  -- Desde la pantalla solo el dueño; el reloj de la base (sin usuario) siempre puede
  if auth.uid() is not null and not exists (select 1 from miembros where user_id = auth.uid() and rol = 'dueno' and activo) then
    raise exception 'Solo el dueño carga la tasa';
  end if;
  if v is null or v <= 0 or pub is null or pub < now() - interval '4 days' or pub > now() + interval '4 days' then return null; end if;   -- dolarapi manda la fecha valor (00:00 de ese día): puede ser mañana o el lunes
  f := fecha_valor_bcv(pub);
  select * into actual from tasas_bcv where fecha = f;
  if found and (actual.fuente = 'Dueño' or actual.tasa = v) then return f; end if;
  -- Un salto de más de 25 % contra la tasa anterior es un dato malo de la fuente: no se toma
  select tasa into previa from tasas_bcv where fecha < f order by fecha desc limit 1;
  if previa is not null and abs(v - previa) / previa > 0.25 then return null; end if;
  insert into tasas_bcv (fecha, tasa, fuente) values (f, v, p_fuente)
  on conflict (fecha) do update set tasa = excluded.tasa, fuente = excluded.fuente, creado_en = now();
  return f;
end $$;
revoke execute on function registrar_tasa_bcv(jsonb, text) from public, anon;
grant execute on function registrar_tasa_bcv(jsonb, text) to authenticated;

-- 4 (solo donde existen pg_cron y pg_net, como en Supabase)
do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'Sin pg_cron o pg_net: la tasa automática no se programa aquí';
    return;
  end if;
  create extension if not exists pg_net with schema extensions;
  create extension if not exists pg_cron;
  execute $f$
    create or replace function pedir_tasa_bcv() returns void
    language sql security definer set search_path = public, extensions as $q$
      select net.http_get('https://ve.dolarapi.com/v1/dolares/oficial', timeout_milliseconds := 10000);
    $q$ $f$;
  execute $f$
    create or replace function procesar_tasa_bcv() returns void
    language plpgsql security definer set search_path = public, extensions as $q$
    declare r record;
    begin
      for r in select content from net._http_response
               where status_code = 200 and created > now() - interval '15 minutes' order by created desc limit 1 loop
        perform registrar_tasa_bcv(r.content::jsonb);
      end loop;
    end $q$ $f$;
  execute 'revoke execute on function pedir_tasa_bcv() from public, anon, authenticated';
  execute 'revoke execute on function procesar_tasa_bcv() from public, anon, authenticated';
  -- pg_cron trabaja en hora UTC: Caracas es UTC − 4
  perform cron.unschedule(jobname) from cron.job where jobname like 'tasa-bcv-%';
  perform cron.schedule('tasa-bcv-pedir',         '*/5 13,14,21,22 * * 1-5',  'select pedir_tasa_bcv()');      -- 9:00–10:55 y 17:00–18:55
  perform cron.schedule('tasa-bcv-guardar',       '2-59/5 13,14,21,22 * * 1-5', 'select procesar_tasa_bcv()');
  perform cron.schedule('tasa-bcv-pedir-hora',    '30 15-20 * * 1-5',          'select pedir_tasa_bcv()');      -- cada hora, 11:30 a 16:30
  perform cron.schedule('tasa-bcv-guardar-hora',  '32 15-20 * * 1-5',          'select procesar_tasa_bcv()');
end $$;
