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

insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'), ('00000000-0000-0000-0000-0000000000a1', 'almacen@azullab.com'), ('00000000-0000-0000-0000-0000000000c1', 'cajero@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000a1', (select f from ids), 'almacen'), ('00000000-0000-0000-0000-0000000000c1', (select f from ids), 'cajero');
insert into tasas_bcv (fecha, tasa) values (current_date, 100);

\echo '--- Proveedores y factura de compra'
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000a1');
insert into proveedores (empresa_id, nombre, rif, credito_dias) values ((select f from ids), 'Cobeca', 'J-12345678-9', 15);
select prueba.debe_fallar('no se repite el proveedor', $$ insert into proveedores (empresa_id, nombre) values ((select f from ids), 'COBECA') $$, 'duplicate key');
select prueba.debe_fallar('RIF de proveedor con formato', $$ insert into proveedores (empresa_id, nombre, rif) values ((select f from ids), 'X', 'J-1') $$, 'check constraint');
insert into productos (empresa_id, codigo, nombre, iva, costo, precio) values ((select f from ids), '1', 'Losartán', 'E', 2, 3), ((select f from ids), '2', 'Champú', 'G', 4, 5);
create temp table c1 as select * from recibir_factura((select f from ids), jsonb_build_object('proveedor_id', 1, 'numero', '0048213', 'control', '00-118204', 'fecha', current_date),
  '[{"producto_id":1,"lote":"A1","vence":"2028-01-01","cantidad":10,"costo":2},{"producto_id":2,"lote":"B1","vence":"2028-01-01","cantidad":5,"costo":4}]');
grant select on c1 to authenticated;
select prueba.igual('exento: 10 × 2', (select exento_usd from c1), 20.00::numeric);
select prueba.igual('gravable: 5 × 4 con IVA 3,20', (select iva_usd from c1), 3.20::numeric);
select prueba.igual('total 43,20', (select total_usd from c1), 43.20::numeric);
select prueba.igual('vence con el crédito del proveedor', (select vence from c1), current_date + 15);
select prueba.igual('los lotes entraron', (select sum(cantidad) from lotes), 15.000::numeric);
select prueba.igual('la referencia queda en el movimiento', (select referencia from movimientos limit 1), 'Cobeca · factura 0048213');
select prueba.debe_fallar('la misma factura no se registra dos veces', $$ select recibir_factura((select f from ids), '{"proveedor_id":1,"numero":"0048213"}', '[]') $$, 'duplicate key');
select prueba.debe_fallar('sin número de factura no', $$ select recibir_factura((select f from ids), '{"proveedor_id":1,"numero":" "}', '[]') $$, 'número de la factura');
select prueba.debe_fallar('almacén no paga facturas', $$ select pagar_compra((select id from c1), 10) $$, 'Solo el dueño');

\echo '--- Pagos, gastos y configuración'
select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.igual('abono de 20', (select pagado_usd from pagar_compra((select id from c1), 20, 'Transferencia')), 20.00::numeric);
select prueba.debe_fallar('no se paga más de lo que se debe', $$ select pagar_compra((select id from c1), 30) $$, 'entre 0,01 y 23.2');
insert into gastos (empresa_id, usd, datos) values ((select f from ids), 650, '{"cat":"Alquiler"}');
update gastos set anulado = true;
select prueba.debe_fallar('los gastos no se borran', $$ delete from gastos $$, 'permission denied');
insert into colecciones (empresa_id, nombre, datos) values ((select f from ids), 'config', '{"gan":30}'), ((select f from ids), 'privado_cuentas', '[{"b":"Banesco"}]');
-- Una venta: 4 Losartán (costo 2) a 3 = 1200 Bs exentos; una NC de 1 = 300 Bs y su devolución
update empresas set datos_confirmados = true;
create temp table v1 as select * from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":4,"precio_usd":3}]');
grant select on v1 to authenticated;
select emitir_nota((select id from v1), 'NC', '[{"descripcion":"Losartán","cantidad":1,"precio_bs":300,"alicuota":"E","ref":{"producto_id":1}}]', 'Devolución', true);
insert into gastos (empresa_id, usd, datos) values ((select f from ids), 100, '{"cat":"Servicios"}');
select prueba.igual('ventas del mes: 12 − 3', (select ventas_usd from resumen_mensual((select f from ids), 1)), 9.00::numeric);
select prueba.igual('costo de lo vendido: 4 × 2 − 1 × 2', (select costo_usd from resumen_mensual((select f from ids), 1)), 6.00::numeric);
select prueba.igual('gastos del mes (sin los anulados)', (select gastos_usd from resumen_mensual((select f from ids), 1)), 100.00::numeric);
select prueba.igual('tres meses', (select count(*) from resumen_mensual((select f from ids), 3)), 3::bigint);
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero no ve las ganancias', $$ select * from resumen_mensual((select f from ids)) $$, 'Solo el dueño');
select prueba.igual('el cajero ve la configuración', (select datos->>'gan' from colecciones where nombre = 'config'), '30');
select prueba.igual('pero no las cuentas del banco', (select count(*) from colecciones where nombre = 'privado_cuentas'), 0::bigint);
select prueba.igual('ni los gastos', (select count(*) from gastos), 0::bigint);
select prueba.igual('ni las compras', (select count(*) from compras), 0::bigint);
insert into colecciones (empresa_id, nombre, datos) values ((select f from ids), 'equipo_fallas', '[{"p":"Acetaminofén"}]');
select prueba.igual('pero sí anota fallas', (select count(*) from colecciones where nombre = 'equipo_fallas'), 1::bigint);
select prueba.debe_fallar('ni cambia la configuración', $$ insert into colecciones (empresa_id, nombre, datos) values ((select f from ids), 'otra', '{}') $$, 'row-level security');
\echo '--- Facturas de compra sin inventario (laboratorio, CrossFit)'
reset role;
insert into miembros (user_id, empresa_id, rol) select '00000000-0000-0000-0000-00000000000d', id, 'dueno' from empresas where tipo = 'laboratorio' on conflict do nothing;
set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
create temp table rc as select * from registrar_compra((select id from empresas where tipo = 'laboratorio'),
  jsonb_build_object('proveedor', 'Distribuidora de reactivos', 'rif', 'j123456789', 'numero', '0004521', 'control', '00-31877', 'fecha', current_date, 'exento_bs', 0, 'gravable_bs', 1000,
                     'retencion', jsonb_build_object('k', 'ser', 'pn', false)));
grant select on rc to authenticated;
select prueba.igual('compra de servicio: base 1000 Bs, IVA 160 Bs → 11,60 $', (select total_usd from rc), 11.60::numeric);
select prueba.igual('con el RIF normalizado', (select rif from rc), 'J-12345678-9');
select prueba.igual('y la retención anotada', (select datos->'retencion'->>'k' from rc), 'ser');
select prueba.debe_fallar('la misma factura no se registra dos veces', $$ select registrar_compra((select id from empresas where tipo = 'laboratorio'), '{"proveedor":"Distribuidora de reactivos","numero":"0004521","gravable_bs":5}') $$, 'duplicate key');
select prueba.debe_fallar('sin monto no', $$ select registrar_compra((select id from empresas where tipo = 'laboratorio'), '{"proveedor":"X","numero":"1"}') $$, 'monto');
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero no registra compras', $$ select registrar_compra((select f from ids), '{"proveedor":"X","numero":"2","exento_bs":5}') $$, 'Solo el dueño');
\echo '--- Todas las pruebas pasaron'
