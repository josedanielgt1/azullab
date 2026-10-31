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
create temp table f1 as select * from emitir_documento('10000000-0000-0000-0000-000000000001', 'FAC',
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
  $$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"Z"}]') $$, 'Alícuota inválida');
select prueba.debe_fallar('sin cliente', $$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'FAC', '{}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]') $$, 'Falta el RIF');
create temp table f2 as select * from emitir_documento('10000000-0000-0000-0000-000000000001', 'FAC',
  '{"rif":"V-1","nombre":"Contado"}', '[{"descripcion":"Agua","cantidad":1,"precio_usd":1,"alicuota":"G"}]');
select prueba.igual('una emisión fallida no gasta número (sigue el 2)', (select numero from f2), 2::bigint);

select prueba.debe_fallar('no se edita una factura', $$ update documentos set total = 1 $$, 'permission denied');
select prueba.debe_fallar('no se borra una factura', $$ delete from documentos $$, 'permission denied');
select prueba.debe_fallar('no se inserta una factura a mano',
  $$ insert into documentos (empresa_id, tipo, numero, serie, cliente_rif, cliente_nombre, tasa, total, total_usd) values ('10000000-0000-0000-0000-000000000001', 'FAC', 99, '00', 'V-1', 'X', 1, 1, 1) $$, 'permission denied');
select prueba.debe_fallar('no se toma un número a mano', $$ select tomar_numero('10000000-0000-0000-0000-000000000001', 'FAC', 'sistema') $$, 'permission denied');
select prueba.debe_fallar('el cajero no emite nota de crédito',
  format($$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'NC', '{"rif":"V-12345678","nombre":"María Pérez"}', '[{"descripcion":"Champú","cantidad":1,"precio_usd":5,"alicuota":"G"}]', '[]', %L, 'Devolución') $$, (select id from f1)), 'Solo dueno, gerente');
select prueba.debe_fallar('el cajero no factura en el laboratorio',
  $$ select emitir_documento('10000000-0000-0000-0000-000000000002', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]') $$, 'No tienes permiso');

reset role;
select prueba.debe_fallar('ni el superusuario borra un documento', $$ delete from documentos $$, 'no se borra');
select prueba.debe_fallar('ni el superusuario cambia un total', $$ update documentos set total = 1 $$, 'no se edita');
set role authenticated;

select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.debe_fallar('almacén no factura',
  $$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]') $$, 'No tienes permiso');

select prueba.como('00000000-0000-0000-0000-0000000000b1');
select prueba.igual('el laboratorio no ve las facturas de la farmacia', (select count(*) from documentos), 0::bigint);
select prueba.igual('el laboratorio no ve renglones de la farmacia', (select count(*) from documento_lineas), 0::bigint);

\echo '--- Notas de crédito y débito'
select prueba.como('00000000-0000-0000-0000-0000000000f1');
create temp table nc1 as select * from emitir_documento('10000000-0000-0000-0000-000000000001', 'NC',
  '{"rif":"V-12345678","nombre":"María Pérez"}', '[{"descripcion":"Champú 400 ml","cantidad":1,"precio_bs":4310.75,"alicuota":"G"}]',
  '[]', (select id from f1), 'Devolución de mercancía');
select prueba.igual('nota de crédito número 1', (select numero from nc1), 1::bigint);
select prueba.igual('la nota usa la tasa de su factura', (select tasa from nc1), (select tasa from f1));
select prueba.igual('nota de crédito con su IVA', (select total from nc1), 5000.47::numeric);
select prueba.debe_fallar('no se acredita más de lo que queda',
  format($$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'NC', '{"rif":"V-12345678","nombre":"María Pérez"}', '[{"descripcion":"Losartán","cantidad":3,"precio_bs":3017.53,"alicuota":"E"}]', '[]', %L, 'Devolución') $$, (select id from f1)), 'pasa de lo que queda');
select prueba.debe_fallar('una nota necesita motivo',
  format($$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'ND', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"Delivery","cantidad":1,"precio_usd":2,"alicuota":"G"}]', '[]', %L) $$, (select id from f1)), 'motivo');
select prueba.debe_fallar('la nota afecta una factura de la misma empresa',
  $$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'NC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]', '[]', gen_random_uuid(), 'x') $$, 'misma empresa');
create temp table nc2 as select * from emitir_documento('10000000-0000-0000-0000-000000000001', 'NC',
  '{"rif":"V-12345678","nombre":"María Pérez"}', '[{"descripcion":"Losartán 50 mg","cantidad":2,"precio_bs":3017.53,"alicuota":"E"}]',
  '[]', (select id from f1), 'Devolución de mercancía');
select prueba.igual('se puede acreditar justo lo que queda', (select total from nc2), 6035.06::numeric);

\echo '--- Contingencia e imprenta'
select prueba.debe_fallar('número fuera del talonario',
  $$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]', '[]', null, null, 'contingencia', 51) $$, 'talonario');
create temp table c1 as select * from emitir_documento('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}',
  '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]', '[]', null, null, 'contingencia', 7);
select prueba.igual('factura de contingencia con su número', (select numero from c1), 7::bigint);
select prueba.debe_fallar('no se repite un número del talonario',
  $$ select emitir_documento('10000000-0000-0000-0000-000000000001', 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]', '[]', null, null, 'contingencia', 7) $$, 'duplicate key');

select prueba.igual('la imprenta asigna el número de control',
  (select numero_control from registrar_imprenta((select id from f1), '00-00000001', 'emitido', '{"ok":true}')), '00-00000001');
select prueba.debe_fallar('la imprenta no procesa dos veces', format($$ select registrar_imprenta(%L, '00-2', 'emitido', null) $$, (select id from f1)), 'ya fue procesado');

\echo '--- Libro de ventas'
select prueba.igual('el libro resta las notas de crédito', (select sum(total) from libro_ventas where tipo = 'NC'), -11035.53::numeric);
select prueba.igual('total neto del libro', (select sum(total) from libro_ventas), 11185.53 + 1000.09 + 862.15 - 11035.53);

reset role;
select prueba.igual('la auditoría guarda las facturas', (select count(*) from auditoria where tabla = 'documentos'), 5::bigint);
\echo '--- Todas las pruebas pasaron'
