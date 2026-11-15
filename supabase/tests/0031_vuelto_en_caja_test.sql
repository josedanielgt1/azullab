-- Pruebas de la migración 0031 (vuelto que queda en caja y redondeo). Correr con:  supabase/tests/correr.sh
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

-- 4 cajas a $3 = $12 = Bs 1.200 (tasa 100). El cliente paga $20: el vuelto es Bs 800. Un dólar son Bs 100.
create function pg_temp.v(p_pagos jsonb) returns documentos language sql as $$
  select * from vender((select f from ids), '{"rif":"V-1","nombre":"Ana"}', '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', p_pagos) $$;

\echo '--- Vuelto exacto: sin ajuste'
select prueba.igual('con el vuelto exacto no queda ajuste', (select vuelto_ajuste from pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-800}]')), 0.00::numeric);
select prueba.igual('ni aunque venga declarado y la diferencia sea de céntimos se pierde la cuenta', (select vuelto_ajuste from pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-799.60},{"ajuste":"en_caja"}]')), 0.40::numeric);

\echo '--- Redondeo a favor del cliente: se entrega de más'
select prueba.debe_fallar('dar Bs 850 por un vuelto de Bs 800 sin marcarlo no pasa', $$ select pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-850}]') $$, 'márcalo como redondeo');
select prueba.debe_fallar('ni marcado como «en caja», que es lo contrario', $$ select pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-850},{"ajuste":"en_caja"}]') $$, 'márcalo como redondeo');
create temp table r1 as select * from pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-850},{"ajuste":"redondeo"}]');
grant select on r1 to authenticated;
select prueba.igual('marcado como redondeo, sale', (select total from r1), 1200.00::numeric);
select prueba.igual('y queda anotado en negativo: la caja entregó Bs 50 de más', (select vuelto_ajuste from r1), -50.00::numeric);
select prueba.igual('la declaración no se guarda como pago', (select count(*) from documento_pagos where documento_id = (select id from r1)), 2::bigint);
select prueba.igual('los pagos dicen lo que de verdad salió de la caja', (select sum(monto_bs) from documento_pagos where documento_id = (select id from r1)), 1150.00::numeric);
select prueba.igual('lo que quedó en caja = factura + ajuste', (select total + vuelto_ajuste from r1), 1150.00::numeric);
select prueba.debe_fallar('el redondeo no pasa de 1 dólar', $$ select pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-950},{"ajuste":"redondeo"}]') $$, 'no puede pasar de Bs 100.00');
select prueba.debe_fallar('si pagó exacto no hay vuelto ni redondeo', $$ select pg_temp.v('[{"metodo":"Pago móvil","monto_bs":1200},{"metodo":"Efectivo Bs","monto_bs":-50},{"ajuste":"redondeo"}]') $$, 'No hay vuelto que entregar');

\echo '--- Vuelto que queda en caja: se entrega de menos'
select prueba.debe_fallar('dar Bs 750 por un vuelto de Bs 800 sin marcarlo no pasa', $$ select pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-750}]') $$, 'marca que queda en caja');
select prueba.debe_fallar('ni marcado como redondeo', $$ select pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-750},{"ajuste":"redondeo"}]') $$, 'marca que queda en caja');
create temp table c1 as select * from pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-750},{"ajuste":"en_caja"}]');
grant select on c1 to authenticated;
select prueba.igual('hasta 1 dólar queda en caja sin nota', (select vuelto_ajuste from c1), 50.00::numeric);
select prueba.debe_fallar('más de 1 dólar en caja pide la nota', $$ select pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-300},{"ajuste":"en_caja","nota":"  "}]') $$, 'anota por qué');
create temp table c2 as select * from pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-300},{"ajuste":"en_caja","nota":"No había sencillo; vuelve mañana"}]');
grant select on c2 to authenticated;
select prueba.igual('con la nota, quedan Bs 500 en caja', (select vuelto_ajuste from c2), 500.00::numeric);
select prueba.igual('y la nota queda en la factura', (select vuelto_nota from c2), 'No había sencillo; vuelve mañana');
create temp table c3 as select * from pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"ajuste":"en_caja","nota":"El cliente dejó el vuelto"}]');
grant select on c3 to authenticated;
select prueba.igual('todo el vuelto puede quedar en caja', (select vuelto_ajuste from c3), 800.00::numeric);
select prueba.igual('y entonces no hay renglones de vuelto', (select count(*) from documento_pagos where documento_id = (select id from c3) and vuelto), 0::bigint);
select prueba.igual('la factura sigue saliendo por su total', (select total from c3), 1200.00::numeric);
select prueba.debe_fallar('un ajuste inventado no entra', $$ select pg_temp.v('[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"ajuste":"propina"}]') $$, 'Ajuste de vuelto desconocido');
select prueba.debe_fallar('el ajuste no se cambia después', $$ update documentos set vuelto_ajuste = 0 where id = (select id from c3) $$, '');

\echo '--- El cierre da exacto: lo que hay en caja = lo facturado + los ajustes'
select prueba.igual('pagos netos del día = total facturado + ajustes', (select sum(p.monto_bs) from documento_pagos p join documentos d on d.id = p.documento_id where d.empresa_id = (select f from ids)),
  (select sum(total + vuelto_ajuste) from documentos where empresa_id = (select f from ids)));

\echo '--- Sin internet: sube como ocurrió, con su ajuste'
select prueba.igual('una venta impresa sin vuelto registrado sube y deja el ajuste a la vista', (select vuelto_ajuste from vender_impresa((select f from ids), '{"rif":"V-9","nombre":"Luis"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true}]', now() - interval '50 minutes', 106, 'Z7C0012345', '{}')), 800.00::numeric);
select prueba.igual('y con redondeo declarado también', (select vuelto_ajuste from vender_impresa((select f from ids), '{"rif":"V-9","nombre":"Luis"}',
  '[{"producto_id":1,"cantidad":4,"precio_usd":3}]', '[{"metodo":"Efectivo USD","monto_bs":2000,"divisa":true},{"metodo":"Efectivo Bs","monto_bs":-840},{"ajuste":"redondeo"}]', now() - interval '40 minutes', 107, 'Z7C0012345', '{}')), -40.00::numeric);

select prueba.igual('un pago incompleto no es asunto del vuelto: no deja ajuste', (select vuelto_ajuste from pg_temp.v('[{"metodo":"Pago móvil","monto_bs":1000}]')), 0.00::numeric);

\echo '--- Laboratorio y CrossFit: no cambian'
select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.igual('fuera de la caja de la farmacia no se anota ajuste', (select vuelto_ajuste from prueba.emitir((select l from ids), '{"rif":"V-2","nombre":"Eva"}',
  '[{"descripcion":"Hematología","cantidad":1,"precio_bs":500,"alicuota":"E"}]', '[{"metodo":"Pago móvil","monto_bs":600}]')), 0.00::numeric);

reset role;
\echo '--- Todas las pruebas pasaron'
