-- Pruebas de la migración 0023 (máquina fiscal). Correr con:  supabase/tests/correr.sh
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

-- ---------- Ayudas ----------
create schema prueba;
grant usage on schema prueba to authenticated, anon, service_role;
create function prueba.como(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, false), set_config('request.jwt.claim.role', 'authenticated', false)
$$;
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
create function prueba.emitir(p_empresa uuid, p_tipo tipo_doc, p_cliente jsonb, p_lineas jsonb) returns documentos
language plpgsql security definer set search_path = public as $$ begin return emitir_documento(p_empresa, p_tipo, p_cliente, p_lineas); end $$;
grant execute on all functions in schema prueba to authenticated, anon, service_role;

-- ---------- Datos ----------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'cajero@azullab.com'),
  ('00000000-0000-0000-0000-0000000000a1', 'almacen@azullab.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'lab@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f, (select id from empresas where tipo = 'laboratorio') l;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values
  ('00000000-0000-0000-0000-0000000000c1', (select f from ids), 'cajero'),
  ('00000000-0000-0000-0000-0000000000a1', (select f from ids), 'almacen'),
  ('00000000-0000-0000-0000-0000000000b1', (select l from ids), 'atencion');
update empresas set datos_confirmados = true, talonario_desde = 1, talonario_hasta = 50;
insert into tasas_bcv (fecha, tasa) values (current_date, 100);

set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into productos (empresa_id, nombre, iva, costo, margen, precio) values
  ((select f from ids), 'Losartán 50 mg', 'E', 2, 50, 3), ((select f from ids), 'Champú 400 ml', 'G', 4, 25, 5);
select count(*) from recibir_compra((select f from ids), '[{"producto_id":1,"lote":"A1","vence":"2030-01-01","cantidad":100,"costo":2},
  {"producto_id":2,"lote":"B1","vence":"2030-01-01","cantidad":100,"costo":4}]');

\echo '--- Antes de la máquina: imprenta digital'
select prueba.igual('sin configurar, la farmacia sigue con imprenta digital',
  (select medio from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]')), 'imprenta');

\echo '--- Configuración de la máquina'
select prueba.debe_fallar('máquina sin número de registro', $$ update empresas set medio_factura = 'maquina' where id = (select f from ids) $$, 'empresas_maquina_lista');
select prueba.debe_fallar('el registro va en mayúsculas', $$ update empresas set medio_factura = 'maquina', maquina_registro = 'z7c0012345' where id = (select f from ids) $$, 'empresas_maquina_registro');
select prueba.debe_fallar('el agente solo en la misma computadora', $$ update empresas set maquina_agente = 'http://ejemplo.com' where id = (select f from ids) $$, 'empresas_maquina_agente');
select prueba.debe_fallar('ni un medio inventado', $$ update empresas set medio_factura = 'papel', maquina_registro = 'Z7C0012345' where id = (select f from ids) $$, 'empresas_medio_factura');
update empresas set medio_factura = 'maquina', maquina_registro = 'Z7C0012345', maquina_marca = 'The Factory', maquina_modelo = 'HKA80'
  where id = (select f from ids);
select prueba.igual('el dueño la configura', (select medio_factura from empresas where id = (select f from ids)), 'maquina');

select prueba.como('00000000-0000-0000-0000-0000000000c1');
update empresas set medio_factura = 'imprenta' where id = (select f from ids);
select prueba.igual('el cajero no cambia el medio', (select medio_factura from empresas where id = (select f from ids)), 'maquina');

\echo '--- Venta por máquina'
create temp table v as select * from vender((select f from ids), '{"rif":"V-12345678","nombre":"María"}', '[{"producto_id":1,"cantidad":2,"precio_usd":3}]');
grant select on v to authenticated;
select prueba.igual('la factura queda pendiente de la impresora', (select medio || '/' || estado from v), 'maquina/pendiente_imprenta');
select prueba.igual('con el registro de la máquina', (select maquina_registro from v), 'Z7C0012345');
select prueba.igual('el inventario ya salió', (select cantidad from lotes where lote = 'A1'), 97.000::numeric);
select prueba.debe_fallar('otra máquina no vale', $$ select registrar_maquina((select id from v), 101, 'Z7C9999999') $$, 'usa la Z7C0012345');
select prueba.debe_fallar('ni un número en cero', $$ select registrar_maquina((select id from v), 0, 'Z7C0012345') $$, 'número válido');
select prueba.igual('la impresora devuelve su número', (select numero_fiscal || '/' || estado from registrar_maquina((select id from v), 101, 'z7c0012345 ', '{"hora":"10:01"}')), '101/emitido');
select prueba.debe_fallar('no se registra dos veces', $$ select registrar_maquina((select id from v), 102, 'Z7C0012345') $$, 'ya quedó impreso');
select prueba.debe_fallar('ni se edita a mano', $$ update documentos set numero_fiscal = 5 where id = (select id from v) $$, 'permission denied');

create temp table v2 as select * from vender((select f from ids), '{"rif":"J-41203398-5","nombre":"Unidad Educativa"}', '[{"producto_id":2,"cantidad":1,"precio_usd":5}]');
grant select on v2 to authenticated;
select prueba.debe_fallar('el mismo número no va en dos facturas', $$ select registrar_maquina((select id from v2), 101, 'Z7C0012345') $$, 'ya está en otra factura');
select registrar_maquina((select id from v2), 102, 'Z7C0012345');

select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.debe_fallar('almacén no registra impresiones', $$ select registrar_maquina((select id from v2), 103, 'Z7C0012345') $$, 'no encontrado');

\echo '--- Nota de crédito por la máquina'
select prueba.como('00000000-0000-0000-0000-00000000000d');
create temp table nc as select * from emitir_nota((select id from v), 'NC', '[{"descripcion":"Losartán","cantidad":1,"precio_bs":300,"alicuota":"E","ref":{"producto_id":1}}]', 'Devolución', true);
grant select on nc to authenticated;
select prueba.igual('la nota también espera a la impresora', (select medio || '/' || estado from nc), 'maquina/pendiente_imprenta');
select prueba.igual('la nota lleva su propio contador', (select numero_fiscal from registrar_maquina((select id from nc), 1, 'Z7C0012345')), 1::bigint);

\echo '--- Impresora dañada: talonario'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
create temp table v3 as select * from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]');
grant select on v3 to authenticated;
select prueba.debe_fallar('fuera del talonario no', $$ select registrar_falla_maquina((select id from v3), 99, 'Sin papel') $$, 'no está en el talonario');
select prueba.debe_fallar('hay que decir qué pasó', $$ select registrar_falla_maquina((select id from v3), 5, ' ') $$, 'qué le pasó');
select prueba.igual('pasa al talonario con su número de control', (select medio || ' ' || numero_control || ' ' || estado from registrar_falla_maquina((select id from v3), 5, 'Error de memoria fiscal')), 'talonario 01-00000005 emitido');
select prueba.igual('queda en el libro de control', (select count(*) from maquina_eventos where tipo = 'falla'), 1::bigint);
select prueba.debe_fallar('una factura del talonario no vuelve a la máquina', $$ select registrar_maquina((select id from v3), 103, 'Z7C0012345') $$, 'no se factura por máquina');
select prueba.debe_fallar('sin internet no se repite ese número', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]', '[]', 'contingencia', 5, now()) $$, 'ya se usó');
select prueba.igual('sin internet sale del talonario', (select medio from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]', '[]', 'contingencia', 6, now())), 'talonario');
create temp table v4 as select * from vender((select f from ids), '{"rif":"V-2","nombre":"Y"}', '[{"producto_id":2,"cantidad":2,"precio_usd":5}]');
grant select on v4 to authenticated;
select prueba.debe_fallar('ni la falla usa uno de sin internet', $$ select registrar_falla_maquina((select id from v4), 6, 'Tapa abierta') $$, 'ya se usó');

\echo '--- Reporte X y Reporte Z'
select prueba.igual('la jornada cuenta lo impreso', (select (j->>'cant_fac') || '/' || (j->>'cant_nc') || '/' || (j->>'pendientes') from jornada_maquina((select f from ids)) j), '2/1/1');
select registrar_maquina((select id from v4), 103, 'Z7C0012345');
select prueba.igual('total neto en Bs (facturas − notas)', (select (j->>'total')::numeric from jornada_maquina((select f from ids)) j), 2040.00::numeric);
select prueba.debe_fallar('el Z es de la máquina del negocio', $$ select registrar_reporte_z((select f from ids), 'OTRA123456', '{"numero":87,"total":1}') $$, 'usa la Z7C0012345');
select prueba.debe_fallar('el Z trae su número', $$ select registrar_reporte_z((select f from ids), 'Z7C0012345', '{"total":1}') $$, 'número del Reporte Z');
select prueba.igual('el Z cuadra con la base',
  (select cuadra from registrar_reporte_z((select f from ids), 'Z7C0012345',
     (select j || '{"numero":87}' from jornada_maquina((select f from ids)) j))), true);
select prueba.igual('las facturas quedan en el Z 87', (select count(*) from documentos where reporte_z = 87), 4::bigint);
select prueba.debe_fallar('un solo Z por día', $$ select registrar_reporte_z((select f from ids), 'Z7C0012345', '{"numero":88,"total":0}') $$, 'ya lo hizo');
select prueba.igual('después del Z la jornada empieza en cero', (select (j->>'cant_fac')::int from jornada_maquina((select f from ids)) j), 0);
select prueba.debe_fallar('nadie escribe un Z a mano', $$ insert into reportes_z (empresa_id, maquina_registro, numero, dia, total) values ((select f from ids), 'Z7C0012345', 99, current_date - 5, 0) $$, 'permission denied');

\echo '--- Libro de ventas'
select prueba.igual('consumidor final en un renglón por Z, del primer al último número',
  (select cliente_nombre || ' ' || desde || '-' || hasta from libro_ventas where reporte_z = 87 and cliente_rif = '—'), 'Consumidor final · Reporte Z N.° 0087 101-103');
select prueba.igual('ese renglón suma las dos facturas', (select total from libro_ventas where reporte_z = 87 and cliente_rif = '—'), 1760.00::numeric);
select prueba.igual('la factura con RIF va sola', (select numero_fiscal from libro_ventas where cliente_rif = 'J-41203398-5'), 102::bigint);
select prueba.igual('la nota de crédito va sola y resta', (select total from libro_ventas where tipo = 'NC'), -300.00::numeric);
select prueba.igual('las del talonario van solas', (select count(*) from libro_ventas where medio = 'talonario'), 2::bigint);

\echo '--- Libro de control de la máquina'
insert into maquina_eventos (empresa_id, maquina_registro, tipo, detalle) values ((select f from ids), 'Z7C0012345', 'falla', 'Atasco de papel');
select prueba.igual('el cajero anota una falla', (select count(*) from maquina_eventos), 2::bigint);
select prueba.debe_fallar('el libro no se edita', $$ update maquina_eventos set detalle = 'otra cosa' $$, 'permission denied');
select prueba.debe_fallar('ni se borra', $$ delete from maquina_eventos $$, 'permission denied');
select prueba.debe_fallar('ni lleva código', $$ insert into maquina_eventos (empresa_id, tipo, detalle) values ((select f from ids), 'otro', '<script>') $$, 'check');

\echo '--- Otro negocio'
select prueba.como('00000000-0000-0000-0000-0000000000b1');
select prueba.igual('el laboratorio no ve el libro de la máquina', (select count(*) from maquina_eventos), 0::bigint);
select prueba.igual('ni los Z de la farmacia', (select count(*) from reportes_z), 0::bigint);
select prueba.debe_fallar('ni hace el Z de la farmacia', $$ select registrar_reporte_z((select f from ids), 'Z7C0012345', '{"numero":90,"total":0}') $$, 'permiso');
select prueba.igual('y sigue con imprenta digital', (select medio from prueba.emitir((select l from ids), 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"Hematología","cantidad":1,"precio_usd":10,"alicuota":"E"}]')), 'imprenta');

\echo '--- Un Z que no cuadra'
reset role;
update reportes_z set dia = current_date - 1;    -- como si el 87 fuera de ayer
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000c1');
create temp table v5 as select * from vender((select f from ids), '{"rif":"V-3","nombre":"Z"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]');
grant select on v5 to authenticated;
select registrar_maquina((select id from v5), 104, 'Z7C0012345');
select prueba.igual('si a la base le falta una factura del Z, no cuadra',
  (select cuadra from registrar_reporte_z((select f from ids), 'Z7C0012345', '{"numero":88,"fac_desde":104,"fac_hasta":105,"cant_fac":2,"total":600}')), false);
select prueba.igual('y guarda lo de cada lado', (select total || ' / ' || sis_total from reportes_z where numero = 88), '600.00 / 300.00');
select prueba.igual('si se reintenta el mismo Z, devuelve el mismo', (select id from registrar_reporte_z((select f from ids), 'Z7C0012345', '{"numero":88,"total":600}')), (select id from reportes_z where numero = 88));

\echo '--- Sin internet, la máquina sigue facturando'
create temp table f1 as select now() - interval '1 hour' as f;
grant select on f1 to authenticated;
select prueba.debe_fallar('otra máquina no', $$ select vender_impresa((select f from ids), '{"rif":"V-9","nombre":"Ana"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]', '[]', (select f from f1), 105, 'OTRA123456') $$, 'usa la Z7C0012345');
select prueba.debe_fallar('ni a un precio inventado', $$ select vender_impresa((select f from ids), '{"rif":"V-9","nombre":"Ana"}', '[{"producto_id":1,"cantidad":1,"precio_usd":0.5}]', '[]', (select f from f1), 105, 'Z7C0012345') $$, 'precio de Losartán');
create temp table off1 as select * from vender_impresa((select f from ids), '{"rif":"V-9","nombre":"Ana"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]', '[]', (select f from f1), 105, 'Z7C0012345', '{"hora":"09:00"}');
grant select on off1 to authenticated;
select prueba.igual('sube con el número que imprimió la máquina', (select medio || ' ' || estado || ' ' || numero_fiscal from off1), 'maquina emitido 105');
select prueba.igual('y con la hora en que se vendió', (select fecha from off1), (select f from f1));
select prueba.igual('si se reintenta, no se repite', (select id from vender_impresa((select f from ids), '{"rif":"V-9","nombre":"Ana"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]', '[]', (select f from f1), 105, 'Z7C0012345')), (select id from off1));
reset role;
select prueba.igual('ni descuenta dos veces', (select count(*) from movimientos where documento_id = (select id from off1)), 1::bigint);
set role authenticated;
select prueba.debe_fallar('otra venta con ese número no', $$ select vender_impresa((select f from ids), '{"rif":"V-8","nombre":"Otro"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]', '[]', now(), 105, 'Z7C0012345') $$, 'ya está en otra factura');
select prueba.igual('entra sola en el Z que ya había subido', (select reporte_z from documentos where id = (select id from off1)), 88);
select prueba.igual('y ahora el Z cuadra', (select cuadra from reportes_z where numero = 88), true);
select prueba.debe_fallar('un Z de hace una semana no', $$ select registrar_reporte_z((select f from ids), 'Z7C0012345', jsonb_build_object('numero', 89, 'total', 0, 'fecha', now() - interval '7 days')) $$, 'Fecha del Reporte Z');
\echo '--- Todas las pruebas pasaron'
