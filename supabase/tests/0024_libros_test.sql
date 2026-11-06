-- Pruebas de la migración 0024 (registro de inventario y notas de crédito de droguería). Correr con:  supabase/tests/correr.sh
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

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'cajero@azullab.com'),
  ('00000000-0000-0000-0000-0000000000a1', 'almacen@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values
  ('00000000-0000-0000-0000-0000000000c1', (select f from ids), 'cajero'),
  ('00000000-0000-0000-0000-0000000000a1', (select f from ids), 'almacen');
update empresas set datos_confirmados = true;
insert into tasas_bcv (fecha, tasa) values (current_date - 60, 90), (current_date, 100);

set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into productos (empresa_id, nombre, iva, costo, margen, precio) values
  ((select f from ids), 'Losartán 50 mg', 'E', 2, 50, 3), ((select f from ids), 'Champú 400 ml', 'G', 4, 25, 5);
insert into proveedores (empresa_id, nombre, rif) values ((select f from ids), 'Cobeca', 'J-12345678-9');

\echo '--- El mes pasado: compra que queda de inventario inicial'
select count(*) from recibir_compra((select f from ids), '[{"producto_id":1,"lote":"A","vence":"2030-01-01","cantidad":10,"costo":2}]');
reset role;
-- como si esa compra hubiera sido el mes pasado (sin los disparadores que protegen los movimientos)
set session_replication_role = replica;
update movimientos set fecha = date_trunc('month', now()) - interval '10 days';
set session_replication_role = origin;
set role authenticated;

\echo '--- Este mes'
create temp table fac as select * from recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"0048213","control":"00-1","fecha":"' || current_date || '"}')::jsonb,
  '[{"producto_id":1,"lote":"B","vence":"2031-01-01","cantidad":20,"costo":2},{"producto_id":2,"lote":"C","vence":"2031-01-01","cantidad":5,"costo":4}]');
grant select on fac to authenticated;
create temp table v as select * from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":7,"precio_usd":3}]');
grant select on v to authenticated;
select emitir_nota((select id from v), 'NC', '[{"descripcion":"Losartán","cantidad":2,"precio_bs":300,"alicuota":"E","ref":{"producto_id":1}}]', 'Devolución de mercancía', true);
select emitir_nota((select id from v), 'NC', '[{"descripcion":"Losartán","cantidad":1,"precio_bs":50,"alicuota":"E","ref":{"producto_id":1}}]', 'Descuento posterior a la venta', false);
select salida_inventario((select id from lotes where lote = 'A'), 1, 'Merma o rotura');

create temp table r as select * from registro_inventario((select f from ids));
grant select on r to authenticated;
select prueba.igual('inicial: lo que quedó del mes pasado', (select inicial from r where producto_id = 1), 10.000::numeric);
select prueba.igual('compras del mes', (select compras from r where producto_id = 1), 20.000::numeric);
select prueba.igual('ventas del mes', (select ventas from r where producto_id = 1), 7.000::numeric);
select prueba.igual('devoluciones de clientes (solo la nota por devolución)', (select devoluciones from r where producto_id = 1), 2.000::numeric);
select prueba.igual('retiros con motivo', (select retiros from r where producto_id = 1), 1.000::numeric);
select prueba.igual('final = inicial + compras + devoluciones − ventas − retiros', (select final from r where producto_id = 1), 24.000::numeric);
select prueba.igual('y coincide con lo que hay en los lotes', (select final from r where producto_id = 1), (select sum(cantidad) from lotes where producto_id = 1));
select prueba.igual('valor final al costo de cada lote', (select valor_final_usd from r where producto_id = 1), 48.00::numeric);
select prueba.igual('en bolívares con la tasa del día', (select valor_final_bs from r where producto_id = 1), 4800.00::numeric);
select prueba.igual('el mes pasado: solo la compra de entonces',
  (select inicial || '/' || compras || '/' || final from registro_inventario((select f from ids), (date_trunc('month', current_date) - interval '1 day')::date) where producto_id = 1), '0/10.000/10.000');

\echo '--- Nota de crédito de la droguería'
select prueba.debe_fallar('sin número no', $$ select nota_compra((select id from fac), '{"numero":"","motivo":"x","exento_usd":1}') $$, 'número de la nota');
select prueba.debe_fallar('sin monto no', $$ select nota_compra((select id from fac), '{"numero":"NC-1","motivo":"x"}') $$, 'necesita un monto');
select prueba.debe_fallar('no más que la factura', $$ select nota_compra((select id from fac), '{"numero":"NC-1","motivo":"x","exento_usd":500}') $$, 'pasa de lo que queda');
create temp table nc as select * from nota_compra((select id from fac), '{"numero":"NC-1","control":"00-9","motivo":"Devolución de mercancía vencida","exento_usd":6,"gravable_usd":4}',
  ('[{"lote_id":' || (select id from lotes where lote = 'B') || ',"cantidad":3},{"lote_id":' || (select id from lotes where lote = 'C') || ',"cantidad":1}]')::jsonb);
grant select on nc to authenticated;
select prueba.igual('queda como NC que cita su factura', (select tipo::text || ' ' || (select numero from compras where id = nc.afecta_id) from nc), 'NC 0048213');
select prueba.igual('con su IVA', (select iva_usd || ' ' || total_usd from nc), '0.64 10.64');
select prueba.igual('lo que se debe de la factura baja', (select total_usd - pagado_usd from compras where id = (select id from fac)), 52.56::numeric);
select prueba.igual('la nota no aparece como deuda', (select total_usd - pagado_usd from nc), 0.00::numeric);
select prueba.igual('los productos devueltos salen de sus lotes', (select string_agg(lote || ':' || cantidad::int, ',' order by lote) from lotes where lote in ('B', 'C')), 'B:17,C:4');
select prueba.igual('y en el registro van como devolución a la droguería', (select devoluciones_proveedor from registro_inventario((select f from ids)) where producto_id = 1), 3.000::numeric);
select prueba.igual('no se mezclan con los retiros', (select retiros from registro_inventario((select f from ids)) where producto_id = 1), 1.000::numeric);
select prueba.debe_fallar('la misma nota dos veces no', $$ select nota_compra((select id from fac), '{"numero":"NC-1","motivo":"x","exento_usd":1}') $$, 'duplicate');
select prueba.debe_fallar('no más de lo que queda después de las notas', $$ select nota_compra((select id from fac), '{"numero":"NC-2","motivo":"x","exento_usd":60}') $$, 'pasa de lo que queda');
select prueba.debe_fallar('una nota no se hace sobre otra nota', $$ select nota_compra((select id from nc), '{"numero":"NC-3","motivo":"x","exento_usd":1}') $$, 'no encontrada');

\echo '--- Permisos'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero no ve el registro de inventario', $$ select * from registro_inventario((select f from ids)) $$, 'permiso');
select prueba.debe_fallar('ni registra notas de droguería', $$ select nota_compra((select id from fac), '{"numero":"NC-9","motivo":"x","exento_usd":1}') $$, 'no encontrada');
select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.igual('almacén sí ve el registro', (select count(*) from registro_inventario((select f from ids))), 2::bigint);
\echo '--- Todas las pruebas pasaron'
