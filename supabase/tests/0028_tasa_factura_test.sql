-- Pruebas de la migración 0028 (la tasa de la factura de compra). Correr con:  supabase/tests/correr.sh
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
grant execute on all functions in schema prueba to authenticated, anon, service_role;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'), ('00000000-0000-0000-0000-0000000000c1', 'cajero@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f, (select id from empresas where tipo = 'laboratorio') l;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000c1', (select f from ids), 'cajero');
update empresas set datos_confirmados = true;
insert into tasas_bcv (fecha, tasa) values (current_date - 1, 360), (current_date, 365);

set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into productos (empresa_id, nombre, iva, costo, margen, precio) values ((select f from ids), 'Losartán 50 mg', 'E', 2, 50, 3), ((select f from ids), 'Protector solar', 'G', 6, 30, 7.8);
insert into proveedores (empresa_id, nombre, rif) values ((select f from ids), 'Cobeca', 'J-12345678-9');
create temp table hoy as select current_date::text d;
grant select on hoy to authenticated;

\echo '--- Sin escribir tasa: la BCV del día de la factura (como antes)'
select prueba.igual('factura de hoy', (select tasa from recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"001","control":"00-1","fecha":"' || current_date || '"}')::jsonb,
  '[{"producto_id":1,"lote":"A","vence":"2031-01-31","cantidad":10,"costo":2}]')), 365.0000::numeric);
select prueba.igual('factura de ayer', (select tasa from recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"002","control":"00-2","fecha":"' || (current_date - 1) || '","tasa":""}')::jsonb,
  '[{"producto_id":1,"lote":"B","vence":"2031-01-31","cantidad":10,"costo":2}]')), 360.0000::numeric);
select prueba.igual('sin tasa propia no se anota la BCV aparte', (select datos from compras where numero = '001'), '{}'::jsonb);

\echo '--- Con la tasa que trae la factura'
create temp table c3 as select * from recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"003","control":"00-3","fecha":"' || current_date || '","tasa":"360"}')::jsonb,
  '[{"producto_id":1,"lote":"C","vence":"2031-01-31","cantidad":10,"costo":2},{"producto_id":2,"lote":"P","vence":"2031-01-31","cantidad":5,"costo":6}]');
grant select on c3 to authenticated;
select prueba.igual('fechada hoy pero impresa con la tasa de ayer: queda la del papel', (select tasa from c3), 360.0000::numeric);
select prueba.igual('y la BCV de ese día queda anotada al lado', (select (datos->>'tasa_bcv')::numeric from c3), 365::numeric);
select prueba.igual('los dólares de la factura no cambian', (select exento_usd || '/' || gravable_usd || '/' || iva_usd || '/' || total_usd from c3), '20.00/30.00/4.80/54.80');
select prueba.igual('en el Libro de Compras los bolívares salen a la tasa de la factura', (select round(exento_usd * tasa, 2) || '/' || round(gravable_usd * tasa, 2) || '/' || round(iva_usd * tasa, 2) from c3), '7200.00/10800.00/1728.00');
select prueba.igual('facturada a tasa del euro (más alta que la BCV)', (select tasa from recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"004","control":"00-4","fecha":"' || current_date || '","tasa":423.5678}')::jsonb,
  '[{"producto_id":1,"lote":"D","vence":"2031-01-31","cantidad":1,"costo":2}]')), 423.5678::numeric);
select prueba.igual('la mercancía entra igual a su lote', (select sum(cantidad)::int from lotes where producto_id = 1), 31);

\echo '--- Errores de dedo'
select prueba.debe_fallar('un cero de más', $$ select recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"005","fecha":"' || (select d from hoy) || '","tasa":3650}')::jsonb, '[{"producto_id":1,"lote":"E","vence":"2031-01-31","cantidad":1,"costo":2}]') $$, 'muy lejos de la BCV');
select prueba.debe_fallar('una cifra de menos', $$ select recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"005","fecha":"' || (select d from hoy) || '","tasa":36.5}')::jsonb, '[{"producto_id":1,"lote":"E","vence":"2031-01-31","cantidad":1,"costo":2}]') $$, 'muy lejos de la BCV');
select prueba.debe_fallar('cero', $$ select recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"005","fecha":"' || (select d from hoy) || '","tasa":0}')::jsonb, '[{"producto_id":1,"lote":"E","vence":"2031-01-31","cantidad":1,"costo":2}]') $$, 'mayor que cero');
select prueba.debe_fallar('texto que no es número', $$ select recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"005","fecha":"' || (select d from hoy) || '","tasa":"abc"}')::jsonb, '[{"producto_id":1,"lote":"E","vence":"2031-01-31","cantidad":1,"costo":2}]') $$, 'invalid input syntax');
select prueba.igual('nada de eso entró', (select count(*) from compras where numero = '005') + (select count(*) from lotes where lote = 'E'), 0::bigint);

\echo '--- Un día sin tasa BCV cargada'
select prueba.debe_fallar('sin BCV y sin tasa en la factura, no entra', $$ select recibir_factura((select f from ids), '{"proveedor_id":1,"numero":"006","fecha":"2020-01-15"}', '[{"producto_id":1,"lote":"F","vence":"2031-01-31","cantidad":1,"costo":2}]') $$, 'No hay tasa BCV cargada');

select prueba.igual('sin BCV pero con la tasa del papel, sí entra', (select tasa from recibir_factura((select f from ids), '{"proveedor_id":1,"numero":"006","fecha":"2020-01-15","tasa":0.0742}', '[{"producto_id":1,"lote":"F","vence":"2031-01-31","cantidad":1,"costo":2}]')), 0.0742::numeric);

\echo '--- Nota de crédito de la droguería'
select prueba.igual('con la tasa que trae la nota', (select tasa from nota_compra((select id from c3), ('{"numero":"NC-1","fecha":"' || current_date || '","exento_usd":2,"motivo":"Descuento","tasa":361.5}')::jsonb)), 361.5000::numeric);
select prueba.igual('sin tasa, la BCV del día de la nota', (select tasa from nota_compra((select id from c3), ('{"numero":"NC-2","fecha":"' || current_date || '","exento_usd":1,"motivo":"Descuento"}')::jsonb)), 365.0000::numeric);
select prueba.debe_fallar('una tasa disparatada en la nota no pasa', $$ select nota_compra((select id from c3), ('{"numero":"NC-3","fecha":"' || (select d from hoy) || '","exento_usd":1,"motivo":"Descuento","tasa":9999}')::jsonb) $$, 'muy lejos de la BCV');

\echo '--- Facturas de servicios y gastos (laboratorio y CrossFit)'
create temp table s1 as select * from registrar_compra((select l from ids), ('{"proveedor":"Internet C.A.","rif":"J-11111111-1","numero":"A-1","fecha":"' || current_date || '","exento_bs":0,"gravable_bs":3600,"tasa":360}')::jsonb);
grant select on s1 to authenticated;
select prueba.igual('los bolívares son los del papel y el dólar sale a la tasa de la factura', (select tasa || ' ' || gravable_usd || ' ' || (datos->>'gravable_bs') from s1), '360.0000 10.00 3600');
select prueba.igual('sin tasa, sigue con la BCV', (select tasa from registrar_compra((select l from ids), ('{"proveedor":"Internet C.A.","numero":"A-2","fecha":"' || current_date || '","exento_bs":365}')::jsonb)), 365.0000::numeric);

\echo '--- Permisos'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero sigue sin recibir compras, con o sin tasa', $$ select recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"009","fecha":"' || (select d from hoy) || '","tasa":360}')::jsonb, '[{"producto_id":1,"lote":"Z","vence":"2031-01-31","cantidad":1,"costo":2}]') $$, 'no recibe compras');
reset role;
select set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claim.role', '', false);
set role anon;
select prueba.debe_fallar('sin entrar no se consulta', $$ select tasa_de_factura(current_date, 360) $$, 'permission denied');
reset role;
\echo '--- Todas las pruebas pasaron'
