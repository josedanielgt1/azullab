-- Pruebas de la migración 0001. Correr con:  supabase/tests/correr.sh
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

-- ---------- Ayudas ----------
create schema prueba;
grant usage on schema prueba to authenticated, anon, service_role;

create function prueba.como(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, false), set_config('request.jwt.claim.role', 'authenticated', false)
$$;

-- Corre una sentencia y exige que falle con un texto dado
create function prueba.debe_fallar(caso text, sentencia text, texto text) returns void language plpgsql as $$
begin
  begin
    execute sentencia;
  exception when others then
    if sqlerrm ilike '%' || texto || '%' then raise notice 'ok   %', caso; return; end if;
    raise exception 'FALLA %: esperaba "%", salió "%"', caso, texto, sqlerrm;
  end;
  raise exception 'FALLA %: debía fallar y no falló', caso;
end $$;

create function prueba.igual(caso text, obtenido anyelement, esperado anyelement) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLA %: salió %, esperaba %', caso, obtenido, esperado; end if;
  raise notice 'ok   %', caso;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'coach@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'crossfit') x;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000c1', (select x from ids), 'coach');
update empresas set datos_confirmados = true;
insert into tasas_bcv (fecha, tasa) values (current_date - 1, 90), (current_date, 100);
update empresas set talonario_desde = 1, talonario_hasta = 50;

\echo '--- Planes y socios'
set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into planes (empresa_id, nombre, precio, dias) values ((select x from ids), 'Mensual ilimitado', 35, 30), ((select x from ids), 'Trimestral', 90, 90);
insert into productos_box (empresa_id, nombre, precio) values ((select x from ids), 'Agua 600 ml', 1);
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el coach no cambia precios', $$ insert into planes (empresa_id, nombre, precio, dias) values ((select x from ids), 'Gratis', 0, 30) $$, 'row-level security');
insert into socios (empresa_id, cedula, nombre, telefono) values ((select x from ids), 'V-24.511.802', 'Andrea Peña', '0414');
select prueba.debe_fallar('una cédula por socio', $$ insert into socios (empresa_id, cedula, nombre) values ((select x from ids), 'v24511802', 'Otra') $$, 'duplicate key');
select prueba.debe_fallar('el coach no cobra', $$ select cobrar_membresia((select x from ids), 1, 1, 'Pago móvil') $$, 'no cobra');
select prueba.debe_fallar('el coach no corre el vencimiento', $$ update socios set vence = current_date + 365 $$, 'cambia con un cobro');

\echo '--- Cobro'
select prueba.como('00000000-0000-0000-0000-00000000000d');
create temp table c1 as select cobrar_membresia((select x from ids), 1, 1, 'Efectivo $', true, '{"id":1,"cantidad":2}') r;
grant select on c1 to authenticated;
-- 3500 + 200 = 3700; IVA 16 % = 592; total 4292; IGTF 3 % de 4292 = 128,76
select prueba.igual('factura con IVA 16 %', (select (r->'documento'->>'iva_general')::numeric from c1), 592.00::numeric);
select prueba.igual('e IGTF por pagar en divisas', (select (r->'documento'->>'igtf')::numeric from c1), 128.76::numeric);
select prueba.igual('sin vencimiento previo, cuenta desde hoy', (select vence from socios), current_date + 30);
select prueba.igual('el renglón dice desde cuándo', (select descripcion from documento_lineas where renglon = 1), 'Mensual ilimitado · desde el ' || to_char(current_date, 'DD-MM-YYYY'));
select cobrar_membresia((select x from ids), 1, 2, 'Pago móvil');
select prueba.igual('renovando antes de vencer no pierde días (30 + 90)', (select vence from socios), current_date + 120);
select prueba.igual('dos membresías registradas', (select count(*) from membresias), 2::bigint);
reset role;
update socios set vence = current_date - 10;
set role authenticated;
select cobrar_membresia((select x from ids), 1, 1, 'Pago móvil');
select prueba.igual('vencida, la nueva cuenta desde hoy', (select vence from socios), current_date + 30);
select prueba.debe_fallar('las membresías no se insertan a mano', $$ insert into membresias (empresa_id, socio_id, plan_id, desde, hasta, precio_usd) values ((select x from ids), 1, 1, current_date, current_date + 999, 0) $$, 'permission denied');

select prueba.igual('cobro sin internet con el talonario', (select (cobrar_membresia((select x from ids), 1, 1, 'Pago móvil', false, null, 'contingencia', 5, now() - interval '2 hours')->'documento'->>'numero')::int), 5);

\echo '--- Clases, entrada y pizarra'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
insert into clases (empresa_id, hora, coach) values ((select x from ids), '06:00', 'Luis');
insert into asistencias (empresa_id, socio_id, clase, hora) values ((select x from ids), 1, '06:00', '05:52');
select prueba.debe_fallar('una entrada por clase y día', $$ insert into asistencias (empresa_id, socio_id, clase) values ((select x from ids), 1, '06:00') $$, 'duplicate key');
insert into pizarras (empresa_id, fecha, wod, publicada) values ((select x from ids), current_date, '{"titulo":"Fran"}', true);
select prueba.igual('el coach publica la pizarra', (select wod->>'titulo' from pizarras), 'Fran');
select prueba.debe_fallar('el coach no ve los cobros', $$ do $x$ begin if (select count(*) from membresias) = 0 then raise exception 'oculto'; end if; end $x$ $$, 'oculto');
select prueba.debe_fallar('ni borra socios', $$ delete from socios $$, 'permission denied');
\echo '--- Todas las pruebas pasaron'
