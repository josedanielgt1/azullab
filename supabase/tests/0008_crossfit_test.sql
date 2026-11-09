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

-- Ayudantes de prueba: llaman a las funciones internas como lo hacen vender(), crear_orden()...
create function prueba.emitir(p_empresa uuid, p_tipo tipo_doc, p_cliente jsonb, p_lineas jsonb, p_pagos jsonb default '[]', p_afecta uuid default null,
  p_motivo text default null, p_origen origen_doc default 'sistema', p_numero_manual bigint default null) returns documentos
language plpgsql security definer set search_path = public as $$ begin return emitir_documento(p_empresa, p_tipo, p_cliente, p_lineas, p_pagos, p_afecta, p_motivo, p_origen, p_numero_manual); end $$;
create function prueba.imprenta(p_doc uuid, p_control text, p_estado estado_doc, p_resp jsonb) returns documentos
language plpgsql security definer set search_path = public as $$ begin return registrar_imprenta(p_doc, p_control, p_estado, p_resp); end $$;
grant execute on all functions in schema prueba to authenticated, anon, service_role;

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
-- 3500 + 200 = 3700; IVA 16 % = 592; total 4292; contribuyente ordinario: sin IGTF
select prueba.igual('factura con IVA 16 %', (select (r->'documento'->>'iva_general')::numeric from c1), 592.00::numeric);
select prueba.igual('contribuyente ordinario: sin IGTF aunque pague en divisas', (select (r->'documento'->>'igtf')::numeric from c1), 0::numeric);
select prueba.igual('y el total es el que se cobró', (select (r->'documento'->>'total')::numeric from c1), 4292.00::numeric);
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
\echo '--- App del socio'
reset role;
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000e1', 'andrea@correo.com'), ('00000000-0000-0000-0000-0000000000e2', 'otro@correo.com');
insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000e1', (select x from ids), 'socio'), ('00000000-0000-0000-0000-0000000000e2', (select x from ids), 'socio');
insert into socios (empresa_id, cedula, nombre, vence) values ((select x from ids), 'V-2', 'Otro socio', current_date + 10);
update socios set user_id = '00000000-0000-0000-0000-0000000000e1' where nombre = 'Andrea Peña';
update socios set user_id = '00000000-0000-0000-0000-0000000000e2' where nombre = 'Otro socio';
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000e1');
select prueba.igual('el socio entra con su rol', (select rol::text from mi_acceso('crossfit')), 'socio');
select prueba.igual('ve solo su ficha', (select string_agg(nombre, ',') from socios), 'Andrea Peña');
select prueba.igual('ve la pizarra', (select wod->>'titulo' from pizarras), 'Fran');
select prueba.igual('no ve facturas', (select count(*) from documentos), 0::bigint);
select prueba.igual('ni los cobros', (select count(*) from membresias), 0::bigint);
select prueba.igual('ni al equipo', (select count(*) from miembros), 1::bigint);
select prueba.igual('ni la entrada de otros', (select count(*) from asistencias), 1::bigint);
select prueba.debe_fallar('no factura', $$ select prueba.emitir((select x from ids), 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"G"}]') $$, 'No tienes permiso');
select prueba.debe_fallar('no escribe en las listas internas del equipo', $$ insert into colecciones (empresa_id, nombre, datos) values ((select x from ids), 'equipo_basura', '[1]') $$, 'row-level security');
select prueba.debe_fallar('no cambia la pizarra', $$ do $x$ begin update pizarras set wod = '{}'; if not found then raise exception 'sin filas'; end if; end $x$ $$, 'sin filas');
select prueba.igual('reserva su clase', (select reservar_clase((select x from ids), '06:00')->>'reservado'), 'true');
select prueba.igual('queda en la lista de la clase', (select reservas->'06:00' @> to_jsonb((select id from socios where nombre = 'Andrea Peña')) from pizarras), true);
select prueba.igual('vuelve a tocar y suelta el cupo', (select reservar_clase((select x from ids), '06:00')->>'reservado'), 'false');
select anotar_resultado((select x from ids), '8:42', true);
select prueba.igual('anota su resultado', (select r->>'t' from pizarras, jsonb_array_elements(resultados) r), '8:42');
select anotar_resultado((select x from ids), '8:30', true);
select prueba.igual('corregirlo no lo duplica', (select jsonb_array_length(resultados) from pizarras), 1);
select prueba.debe_fallar('tiempo con formato', $$ select anotar_resultado((select x from ids), 'rápido', true) $$, 'Escribe el tiempo');
select prueba.como('00000000-0000-0000-0000-0000000000e2');
select prueba.igual('el otro socio no ve la ficha de Andrea', (select count(*) from socios where nombre = 'Andrea Peña'), 0::bigint);
\echo '--- El socio no ve clientes ni proveedores (0025)'
reset role;
insert into clientes (empresa_id, cedula_rif, nombre, telefono) values ((select x from ids), 'V-9.999.999', 'Cliente del box', '0416');
insert into proveedores (empresa_id, nombre) values ((select x from ids), 'Distribuidora de agua');
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000e1');
select prueba.igual('el socio no ve los clientes', (select count(*) from clientes), 0::bigint);
select prueba.debe_fallar('ni crea clientes', $$ insert into clientes (empresa_id, cedula_rif, nombre) values ((select x from ids), 'V-12345678', 'Falso') $$, 'row-level security');
select prueba.debe_fallar('ni los cambia', $$ do $x$ begin update clientes set telefono = '0'; if not found then raise exception 'sin filas'; end if; end $x$ $$, 'sin filas');
select prueba.igual('ni ve los proveedores', (select count(*) from proveedores), 0::bigint);
select prueba.igual('pero sí ve los planes', (select count(*) > 0 from planes), true);
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.igual('el coach sí ve los clientes', (select count(*) > 0 from clientes), true);
select prueba.igual('y los proveedores', (select count(*) from proveedores), 1::bigint);
\echo '--- Todas las pruebas pasaron'
