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
grant execute on all functions in schema prueba to authenticated, anon, service_role;

-- Ayudantes de prueba: llaman a las funciones internas como lo hacen vender(), crear_orden()...
create function prueba.emitir(p_empresa uuid, p_tipo tipo_doc, p_cliente jsonb, p_lineas jsonb, p_pagos jsonb default '[]', p_afecta uuid default null,
  p_motivo text default null, p_origen origen_doc default 'sistema', p_numero_manual bigint default null) returns documentos
language plpgsql security definer set search_path = public as $$ begin return emitir_documento(p_empresa, p_tipo, p_cliente, p_lineas, p_pagos, p_afecta, p_motivo, p_origen, p_numero_manual); end $$;
create function prueba.imprenta(p_doc uuid, p_control text, p_estado estado_doc, p_resp jsonb) returns documentos
language plpgsql security definer set search_path = public as $$ begin return registrar_imprenta(p_doc, p_control, p_estado, p_resp); end $$;
grant execute on all functions in schema prueba to authenticated, anon, service_role;

-- ---------- Datos ----------
-- Se quitan las empresas que trae la instalación (0002): estas pruebas usan las suyas
delete from empresas;
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000d', 'dueno@azullab'),
  ('00000000-0000-0000-0000-0000000000c1', 'cajero@farmacia'),
  ('00000000-0000-0000-0000-0000000000a1', 'almacen@farmacia'),
  ('00000000-0000-0000-0000-0000000000b1', 'atencion@laboratorio'),
  ('00000000-0000-0000-0000-0000000000f1', 'gerente@farmacia');
insert into perfiles (user_id, nombre) values
  ('00000000-0000-0000-0000-00000000000d', 'Daniela Uzcátegui'),
  ('00000000-0000-0000-0000-0000000000c1', 'Kevin Albarrán'),
  ('00000000-0000-0000-0000-0000000000a1', 'Wilmer Rivas'),
  ('00000000-0000-0000-0000-0000000000b1', 'Atención Lab'),
  ('00000000-0000-0000-0000-0000000000f1', 'Gerente Farmacia')
on conflict (user_id) do update set nombre = excluded.nombre;

insert into empresas (id, tipo, nombre, razon_social, rif, domicilio, talonario_desde, talonario_hasta) values
  ('10000000-0000-0000-0000-000000000001', 'farmacia',    'Azullab Farmacia',    'Azullab Farmacia, C.A.',          'J-00000001-1', 'La Azulita', 1, 50),
  ('10000000-0000-0000-0000-000000000002', 'laboratorio', 'Azullab Laboratorio', 'Grupo Empresarial Azullab, C.A.', 'J-50134578-3', 'La Azulita', 1, 50),
  ('10000000-0000-0000-0000-000000000003', 'crossfit',    'Azullab CrossFit',    'Fitness Lab Evolution, C.A.',     'J-00000002-2', 'La Azulita', 1, 50);
update empresas set datos_confirmados = true;
-- La farmacia de prueba es contribuyente especial: cobra IGTF; el laboratorio es ordinario
update empresas set igtf = 3 where tipo = 'farmacia';

insert into miembros (user_id, empresa_id, rol) values
  ('00000000-0000-0000-0000-00000000000d', '10000000-0000-0000-0000-000000000001', 'dueno'),
  ('00000000-0000-0000-0000-00000000000d', '10000000-0000-0000-0000-000000000002', 'dueno'),
  ('00000000-0000-0000-0000-00000000000d', '10000000-0000-0000-0000-000000000003', 'dueno'),
  ('00000000-0000-0000-0000-0000000000c1', '10000000-0000-0000-0000-000000000001', 'cajero'),
  ('00000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-000000000001', 'almacen'),
  ('00000000-0000-0000-0000-0000000000f1', '10000000-0000-0000-0000-000000000001', 'gerente'),
  ('00000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-000000000002', 'atencion');

insert into tasas_bcv (fecha, tasa) values (current_date - 1, 860.00), (current_date, 862.15);

\echo '--- Empresas y permisos'
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.igual('el cajero ve solo su farmacia', (select count(*) from empresas), 1::bigint);
select prueba.igual('el cajero no ve la auditoría', (select count(*) from auditoria), 0::bigint);
select prueba.debe_fallar('el cajero no cambia el RIF',
  $$ do $x$ begin update empresas set rif = 'J-99999999-9'; if not found then raise exception 'sin filas'; end if; end $x$ $$, 'sin filas');
select prueba.debe_fallar('el cajero no carga la tasa', $$ insert into tasas_bcv (fecha, tasa) values (current_date + 1, 1) $$, 'row-level security');

select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.igual('el dueño ve las tres empresas', (select count(*) from empresas), 3::bigint);
select prueba.igual('tasa del día', tasa_del_dia(), 862.1500::numeric);
select prueba.igual('tasa de mañana = la última publicada', tasa_del_dia(current_date + 1), 862.1500::numeric);

select prueba.como('00000000-0000-0000-0000-0000000000f1');
select prueba.debe_fallar('el gerente no nombra a otro dueño',
  $$ insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-000000000001', 'dueno') $$, 'row-level security');

\echo '--- Factura'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
create temp table f1 as select * from prueba.emitir('10000000-0000-0000-0000-000000000001', 'FAC',
  '{"rif":"v-12345678","nombre":"María Pérez"}',
  '[{"descripcion":"Losartán 50 mg","cantidad":2,"precio_usd":3.50,"alicuota":"E"},
    {"descripcion":"Champú 400 ml","cantidad":1,"precio_usd":5,"alicuota":"G"}]',
  '[{"metodo":"Efectivo USD","monto_bs":5000,"divisa":true},{"metodo":"Pago móvil","monto_bs":2000}]');
-- Losartán: 3,50 × 862,15 = 3017,53 × 2 = 6035,06 · Champú: 4310,75 · IVA 16 % = 689,72
select prueba.igual('factura número 1', (select numero from f1), 1::bigint);
select prueba.igual('base exenta', (select base_exenta from f1), 6035.06::numeric);
select prueba.igual('base general', (select base_general from f1), 4310.75::numeric);
select prueba.igual('IVA 16 %', (select iva_general from f1), 689.72::numeric);
select prueba.igual('IGTF 3 % sobre lo pagado en divisas', (select igtf from f1), 150.00::numeric);
select prueba.igual('total', (select total from f1), 11185.53::numeric);
select prueba.igual('RIF del cliente en mayúsculas', (select cliente_rif from f1), 'V-12345678');
select prueba.igual('queda pendiente de la imprenta', (select estado::text from f1), 'pendiente_imprenta');
select prueba.igual('se guardan los renglones', (select count(*) from documento_lineas where documento_id = (select id from f1)), 2::bigint);

select prueba.debe_fallar('alícuota inválida',
  $$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"Z"}]') $$, 'Alícuota inválida');
select prueba.debe_fallar('sin cliente', $$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'FAC', '{}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]') $$, 'Falta el RIF');
create temp table f2 as select * from prueba.emitir('10000000-0000-0000-0000-000000000001', 'FAC',
  '{"rif":"V-1","nombre":"Contado"}', '[{"descripcion":"Agua","cantidad":1,"precio_usd":1,"alicuota":"G"}]');
select prueba.igual('una emisión fallida no gasta número (sigue el 2)', (select numero from f2), 2::bigint);

select prueba.debe_fallar('no se edita una factura', $$ update documentos set total = 1 $$, 'permission denied');
select prueba.debe_fallar('no se borra una factura', $$ delete from documentos $$, 'permission denied');
select prueba.debe_fallar('no se inserta una factura a mano',
  $$ insert into documentos (empresa_id, tipo, numero, serie, cliente_rif, cliente_nombre, tasa, total, total_usd) values ('10000000-0000-0000-0000-000000000001', 'FAC', 99, '00', 'V-1', 'X', 1, 1, 1) $$, 'permission denied');
select prueba.debe_fallar('no se toma un número a mano', $$ select tomar_numero('10000000-0000-0000-0000-000000000001', 'FAC', 'sistema') $$, 'permission denied');
select prueba.debe_fallar('el cajero no emite nota de crédito',
  format($$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'NC', '{"rif":"V-12345678","nombre":"María Pérez"}', '[{"descripcion":"Champú","cantidad":1,"precio_usd":5,"alicuota":"G"}]', '[]', %L, 'Devolución') $$, (select id from f1)), 'Solo dueno, gerente');
select prueba.debe_fallar('el cajero no factura en el laboratorio',
  $$ select prueba.emitir('10000000-0000-0000-0000-000000000002', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]') $$, 'No tienes permiso');

reset role;
select prueba.debe_fallar('ni el superusuario borra un documento', $$ delete from documentos $$, 'no se borra');
select prueba.debe_fallar('ni el superusuario cambia un total', $$ update documentos set total = 1 $$, 'no se edita');
set role authenticated;

select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.debe_fallar('almacén no factura',
  $$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]') $$, 'No tienes permiso');

select prueba.como('00000000-0000-0000-0000-0000000000b1');
select prueba.igual('el laboratorio no ve las facturas de la farmacia', (select count(*) from documentos), 0::bigint);
select prueba.igual('el laboratorio no ve renglones de la farmacia', (select count(*) from documento_lineas), 0::bigint);

\echo '--- Notas de crédito y débito'
select prueba.como('00000000-0000-0000-0000-0000000000f1');
create temp table nc1 as select * from prueba.emitir('10000000-0000-0000-0000-000000000001', 'NC',
  '{"rif":"V-12345678","nombre":"María Pérez"}', '[{"descripcion":"Champú 400 ml","cantidad":1,"precio_bs":4310.75,"alicuota":"G"}]',
  '[]', (select id from f1), 'Devolución de mercancía');
select prueba.igual('nota de crédito número 1', (select numero from nc1), 1::bigint);
select prueba.igual('la nota usa la tasa de su factura', (select tasa from nc1), (select tasa from f1));
select prueba.igual('nota de crédito con su IVA', (select total from nc1), 5000.47::numeric);
select prueba.debe_fallar('no se acredita más de lo que queda',
  format($$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'NC', '{"rif":"V-12345678","nombre":"María Pérez"}', '[{"descripcion":"Losartán","cantidad":3,"precio_bs":3017.53,"alicuota":"E"}]', '[]', %L, 'Devolución') $$, (select id from f1)), 'pasa de lo que queda');
select prueba.debe_fallar('una nota necesita motivo',
  format($$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'ND', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"Delivery","cantidad":1,"precio_usd":2,"alicuota":"G"}]', '[]', %L) $$, (select id from f1)), 'motivo');
select prueba.debe_fallar('la nota afecta una factura de la misma empresa',
  $$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'NC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]', '[]', gen_random_uuid(), 'x') $$, 'misma empresa');
create temp table nc2 as select * from prueba.emitir('10000000-0000-0000-0000-000000000001', 'NC',
  '{"rif":"V-12345678","nombre":"María Pérez"}', '[{"descripcion":"Losartán 50 mg","cantidad":2,"precio_bs":3017.53,"alicuota":"E"}]',
  '[]', (select id from f1), 'Devolución de mercancía');
select prueba.igual('se puede acreditar justo lo que queda', (select total from nc2), 6035.06::numeric);

\echo '--- Contingencia e imprenta'
select prueba.debe_fallar('número fuera del talonario',
  $$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]', '[]', null, null, 'contingencia', 51) $$, 'talonario');
create temp table c1 as select * from prueba.emitir('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}',
  '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]', '[]', null, null, 'contingencia', 7);
select prueba.igual('factura de contingencia con su número', (select numero from c1), 7::bigint);
select prueba.debe_fallar('no se repite un número del talonario',
  $$ select prueba.emitir('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]', '[]', null, null, 'contingencia', 7) $$, 'duplicate key');

select prueba.igual('la imprenta asigna el número de control',
  (select numero_control from prueba.imprenta((select id from f1), '00-00000001', 'emitido', '{"ok":true}')), '00-00000001');
select prueba.debe_fallar('la imprenta no procesa dos veces', format($$ select prueba.imprenta(%L, '00-2', 'emitido', null) $$, (select id from f1)), 'ya fue procesado');

\echo '--- Libro de ventas'
select prueba.igual('el libro resta las notas de crédito', (select sum(total) from libro_ventas where tipo = 'NC'), -11035.53::numeric);
select prueba.igual('total neto del libro', (select sum(total) from libro_ventas), 11185.53 + 1000.09 + 862.15 - 11035.53);

reset role;
select prueba.igual('la auditoría guarda las facturas', (select count(*) from auditoria where tabla = 'documentos'), 5::bigint);
\echo '--- Tasa BCV automática'
select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.igual('la base cuenta el día con la hora de Caracas', current_date, (now() at time zone 'America/Caracas')::date);
select prueba.igual('lo publicado a las 9:20 a. m. vale para ese día', fecha_valor_bcv('2026-11-05 09:20-04'), '2026-11-05'::date);
select prueba.igual('lo publicado a las 5:20 p. m. vale para el día siguiente', fecha_valor_bcv('2026-11-05 17:20-04'), '2026-11-06'::date);
select prueba.igual('lo del viernes en la tarde vale para el lunes', fecha_valor_bcv('2026-11-06 17:20-04'), '2026-11-09'::date);
create temp table pub as select ((current_date + time '00:05') at time zone 'America/Caracas') t;
select prueba.igual('el reloj guarda la tasa con su fecha valor',
  registrar_tasa_bcv(jsonb_build_object('promedio', 870, 'fechaActualizacion', (select t from pub))), fecha_valor_bcv((select t from pub)));
select prueba.igual('y queda guardada', (select tasa from tasas_bcv where fecha = fecha_valor_bcv((select t from pub))), 870.0000::numeric);
insert into tasas_bcv (fecha, tasa) values (current_date + 1, 999);
select prueba.igual('la tasa del día siguiente se usa apenas se publica', tasa_del_dia(), 999.0000::numeric);
select prueba.igual('una venta de ayer (sin internet) sigue con la tasa de ayer', tasa_del_dia(current_date - 1), 860.0000::numeric);
delete from tasas_bcv where fecha = current_date + 1;
update tasas_bcv set tasa = 865, fuente = 'Dueño' where fecha = fecha_valor_bcv((select t from pub));
select registrar_tasa_bcv(jsonb_build_object('promedio', 871, 'fechaActualizacion', (select t from pub)));
select prueba.igual('lo que escribió el dueño manda sobre lo automático', (select tasa from tasas_bcv where fecha = fecha_valor_bcv((select t from pub))), 865.0000::numeric);
select prueba.igual('un salto de más de 25 % no se toma',
  registrar_tasa_bcv(jsonb_build_object('promedio', 2000, 'fechaActualizacion', (select t from pub) + interval '15 hours 20 minutes')) is null, true);
select prueba.igual('lo que dolarapi publica a las 5 p. m. llega con la fecha de mañana y se guarda para mañana',
  registrar_tasa_bcv(jsonb_build_object('promedio', 872, 'fechaActualizacion', ((current_date + 1) + time '00:00') at time zone 'America/Caracas')), fecha_valor_bcv(((current_date + 1) + time '00:00') at time zone 'America/Caracas'));
select prueba.igual('y se usa desde ya, sin esperar a mañana', tasa_del_dia(), 872.0000::numeric);
select prueba.igual('un dato viejo no se toma', registrar_tasa_bcv(jsonb_build_object('promedio', 870, 'fechaActualizacion', now() - interval '6 days')) is null, true);
grant select on pub to authenticated;
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero no carga la tasa automática', $$ select registrar_tasa_bcv('{"promedio":1,"fechaActualizacion":"2026-11-05T09:20:00-04:00"}') $$, 'Solo el dueño');
reset role;
\echo '--- Todas las pruebas pasaron'
