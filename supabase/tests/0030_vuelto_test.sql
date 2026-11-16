-- Pruebas de la migración 0030 (el vuelto queda en la factura). Correr con:  supabase/tests/correr.sh
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

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
create function prueba.emitir(p_empresa uuid, p_cliente jsonb, p_lineas jsonb, p_pagos jsonb) returns documentos
language plpgsql security definer set search_path = public as $$ begin return emitir_documento(p_empresa, 'FAC', p_cliente, p_lineas, p_pagos); end $$;
grant execute on all functions in schema prueba to authenticated, anon, service_role;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'), ('00000000-0000-0000-0000-0000000000c1', 'cajero@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f, (select id from empresas where tipo = 'laboratorio') l;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000c1', (select f from ids), 'cajero');
update empresas set datos_confirmados = true;
update empresas set medio_factura = 'maquina', maquina_registro = 'Z7C0012345', maquina_marca = 'The Factory', maquina_modelo = 'HKA80' where id = (select f from ids);
insert into tasas_bcv (fecha, tasa) values (current_date, 100);

set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into productos (empresa_id, nombre, iva, costo, margen, precio) values ((select f from ids), 'Losartán 50 mg', 'E', 2, 50, 3);
select count(*) from recibir_compra((select f from ids), '[{"producto_id":1,"lote":"A1","vence":"2030-01-01","cantidad":100,"costo":2}]');
select prueba.como('00000000-0000-0000-0000-0000000000c1');

-- La venta de siempre: 4 cajas a $3 = $12 = Bs 1.200 (tasa 100)
\echo '--- Pago exacto: nada cambia'
create temp table v0 as select * from vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}', '[{"producto_id":1,"cantidad":4,"precio_usd":3}]',
  '[{"metodo":"Pago móvil","monto_bs":1200}]');
grant select on v0 to authenticated;
select prueba.igual('el pago exacto se factura como antes', (select total from v0), 1200.00::numeric);
select prueba.igual('y no deja renglones de vuelto', (select count(*) from documento_pagos where documento_id = (select id from v0) and vuelto), 0::bigint);
select prueba.igual('el redondeo entre monedas no pide vuelto (hasta un centavo de dólar)', (select total from vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Pago móvil","monto_bs":1200.90}]')), 1200.00::numeric);

\echo '--- El cliente paga de más'
select prueba.debe_fallar('pagó $20 por $12 y no se registró el vuelto: no se factura', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true}]') $$, 'entrega el vuelto o marca que queda en caja');
select prueba.igual('y esa venta que no salió no tocó el inventario', (select cantidad from lotes where lote = 'A1'), 92.000::numeric);
select prueba.debe_fallar('con el vuelto a medias tampoco', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-300}]') $$, 'pagó Bs 500.00 de más');
select prueba.debe_fallar('el vuelto no pasa de lo que pagó de más', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-900}]') $$, 'pasa de lo que el cliente pagó de más');
select prueba.debe_fallar('ni hay vuelto si pagó exacto', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Pago móvil","monto_bs":1200},{"metodo":"Efectivo Bs","monto_bs":-50}]') $$, 'No hay vuelto que entregar');
select prueba.debe_fallar('un pago en cero no entra', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Pago móvil","monto_bs":0}]') $$, 'pago sin monto');
select prueba.debe_fallar('ni un pago sin forma de pago', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":" ","monto_bs":1200}]') $$, 'sin forma de pago');

\echo '--- Vuelto registrado: $20 por $12, vuelto Bs 500 en efectivo y Bs 300 por pago móvil'
create temp table v1 as select * from vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}', '[{"producto_id":1,"cantidad":4,"precio_usd":3}]',
  '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-500},{"metodo":"Pago móvil","monto_bs":-300}]');
grant select on v1 to authenticated;
select prueba.igual('la factura sale por su total, no por lo que entregó el cliente', (select total from v1), 1200.00::numeric);
select prueba.igual('sin IGTF para el contribuyente ordinario', (select igtf from v1), 0.00::numeric);
select prueba.igual('quedan los tres renglones', (select count(*) from documento_pagos where documento_id = (select id from v1)), 3::bigint);
select prueba.igual('el vuelto queda marcado', (select string_agg(metodo || ' ' || monto_bs, ', ' order by id) from documento_pagos where documento_id = (select id from v1) and vuelto),
  'Efectivo Bs -500.00, Pago móvil -300.00');
select prueba.igual('lo cobrado menos el vuelto da el total de la factura', (select sum(monto_bs) from documento_pagos where documento_id = (select id from v1)), 1200.00::numeric);
select prueba.igual('la caja de dólares queda con lo que entró', (select sum(monto_bs) from documento_pagos where documento_id = (select id from v1) and metodo = 'Efectivo USD'), 2000.00::numeric);
select prueba.igual('y la de bolívares con lo que salió', (select sum(monto_bs) from documento_pagos p join documentos d on d.id = p.documento_id
  where d.empresa_id = (select f from ids) and p.metodo = 'Efectivo Bs'), -500.00::numeric);
select prueba.debe_fallar('el vuelto tampoco se edita después', $$ update documento_pagos set monto_bs = -1 where vuelto $$, '');
select prueba.igual('vuelto casi completo (redondeo del billete) se acepta', (select total from vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-799.50}]')), 1200.00::numeric);

\echo '--- IGTF: el vuelto no lo cambia'
reset role;
update empresas set igtf = 3 where id = (select f from ids);
set role authenticated;
select prueba.igual('el IGTF sale del total pagado en divisas, con tope en la factura', (select igtf from vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo USD","monto_bs":-800,"divisa":true}]')), 36.00::numeric);
reset role;
update empresas set igtf = 0 where id = (select f from ids);
set role authenticated;

\echo '--- Lo que ya imprimió la máquina sin internet sube como ocurrió'
create temp table off1 as select * from vender_impresa((select f from ids), '{"rif":"V-9","nombre":"Luis"}', '[{"producto_id":1,"cantidad":4,"precio_usd":3}]',
  '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-800}]', now() - interval '1 hour', 105, 'Z7C0012345', '{"hora":"09:00"}');
grant select on off1 to authenticated;
select prueba.igual('sube con su vuelto', (select sum(monto_bs) from documento_pagos where documento_id = (select id from off1)), 1200.00::numeric);
select prueba.igual('y una venta vieja en cola, sin vuelto registrado, no se queda atascada', (select estado::text from vender_impresa((select f from ids), '{"rif":"V-9","nombre":"Luis"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true}]', now() - interval '50 minutes', 106, 'Z7C0012345', '{}')), 'emitido');

\echo '--- Laboratorio y CrossFit: su cobro no cambia'
select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.igual('otro documento con pago exacto sigue igual', (select total from prueba.emitir((select l from ids), '{"rif":"V-2","nombre":"Eva"}',
  '[{"descripcion":"Hematología","cantidad":1,"precio_bs":500,"alicuota":"E"}]', '[{"metodo":"Pago móvil","monto_bs":500}]')), 500.00::numeric);
select prueba.igual('y fuera de la caja de la farmacia pagar de más no frena el documento', (select total from prueba.emitir((select l from ids), '{"rif":"V-2","nombre":"Eva"}',
  '[{"descripcion":"Hematología","cantidad":1,"precio_bs":500,"alicuota":"E"}]', '[{"metodo":"Pago móvil","monto_bs":600}]')), 500.00::numeric);
select prueba.debe_fallar('pero su vuelto tampoco pasa de lo pagado de más', $$ select prueba.emitir((select l from ids), '{"rif":"V-2","nombre":"Eva"}',
  '[{"descripcion":"Hematología","cantidad":1,"precio_bs":500,"alicuota":"E"}]', '[{"metodo":"Pago móvil","monto_bs":600},{"metodo":"Efectivo Bs","monto_bs":-300}]') $$, 'pasa de lo que el cliente pagó de más');

reset role;
\echo '--- Todas las pruebas pasaron'
