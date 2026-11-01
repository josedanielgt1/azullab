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
update empresas set datos_confirmados = true;
insert into tasas_bcv (fecha, tasa) values (current_date, 100);

\echo '--- Catálogo'
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000a1');
insert into productos (empresa_id, codigo, codigos_alt, nombre, principio_activo, presentacion, iva, costo, margen, precio)
values ((select f from ids), '7591020311042', '{7591020311059}', 'Losartán 50 mg', 'Losartán', 'Caja x 30', 'E', 2, 50, 3),
       ((select f from ids), '7590001', '{}', 'Champú 400 ml', '—', 'Frasco', 'G', 4, 25, 5);
select prueba.igual('almacén crea productos', (select count(*) from productos), 2::bigint);
select prueba.debe_fallar('un código no va en dos productos',
  $$ insert into productos (empresa_id, codigo, nombre) values ((select f from ids), '7591020311059', 'Otro') $$, 'ya está en Losartán');
select prueba.debe_fallar('almacén no inventa existencia',
  $$ insert into lotes (empresa_id, producto_id, lote, vence, cantidad) values ((select f from ids), 1, 'X', current_date + 30, 99) $$, 'permission denied');
select prueba.debe_fallar('almacén no borra productos', $$ delete from productos $$, 'permission denied');

\echo '--- Compra'
select prueba.igual('recibir compra crea los lotes', (select count(*) from recibir_compra((select f from ids),
  '[{"producto_id":1,"lote":"gv25","vence":"2028-03-31","cantidad":10,"costo":2},
    {"producto_id":1,"lote":"GV24","vence":"2027-01-31","cantidad":5,"costo":2},
    {"producto_id":2,"lote":"CH1","vence":"2029-01-01","cantidad":3,"costo":4}]', 'Cobeca 001')), 3::bigint);
select prueba.igual('el lote queda en mayúsculas', (select count(*) from lotes where lote = 'GV25'), 1::bigint);
select recibir_compra((select f from ids), '[{"producto_id":1,"lote":"GV25","vence":"2028-03-31","cantidad":2,"costo":2}]');
select prueba.igual('el mismo lote suma', (select cantidad from lotes where lote = 'GV25'), 12.000::numeric);
select prueba.debe_fallar('compra sin vencimiento', $$ select recibir_compra((select f from ids), '[{"producto_id":1,"lote":"A","cantidad":1}]') $$, 'lote, vencimiento');
select prueba.debe_fallar('no se cambia la cantidad a mano', $$ update lotes set cantidad = 1000 $$, 'permission denied');
update lotes set precio = 3.5 where lote = 'GV25';
select prueba.igual('sí se cambia el precio del lote', (select precio from lotes where lote = 'GV25'), 3.50::numeric);
reset role;
-- un lote vencido (como si hubiera entrado hace tiempo)
select set_config('cuadre.inventario', 'si', false);
insert into lotes (empresa_id, producto_id, lote, vence, cantidad, costo) values ((select f from ids), 1, 'VIEJO', current_date - 1, 50, 2);
select set_config('cuadre.inventario', '', false);
set role authenticated;

\echo '--- Venta'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
create temp table v1 as select * from vender((select f from ids), '{"rif":"V-12345678","nombre":"María"}',
  '[{"producto_id":1,"cantidad":7,"precio_usd":3},{"producto_id":2,"cantidad":1,"precio_usd":5}]',
  '[{"metodo":"Efectivo USD","monto_bs":1000,"divisa":true}]');
select prueba.igual('vender emite la factura', (select numero from v1), 1::bigint);
-- 7 × 300 = 2100 exento; 500 + 16 % = 580; IGTF 3 % de 1000 = 30
select prueba.igual('con sus montos', (select total from v1), 2710.00::numeric);
select prueba.igual('primero sale el lote que vence antes (GV24 queda en 0)', (select cantidad from lotes where lote = 'GV24'), 0.000::numeric);
select prueba.igual('y el resto del siguiente (GV25 queda en 10)', (select cantidad from lotes where lote = 'GV25'), 10.000::numeric);
select prueba.igual('el vencido no se toca', (select cantidad from lotes where lote = 'VIEJO'), 50.000::numeric);
select prueba.igual('el champú baja a 2', (select cantidad from lotes where lote = 'CH1'), 2.000::numeric);
select prueba.igual('al precio del lote también se vende', (select numero from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3.5}]')), 2::bigint);
select prueba.debe_fallar('no se vende a otro precio', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":1,"precio_usd":0.5}]') $$, 'precio de Losartán');
select prueba.debe_fallar('no se vende lo que no hay', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":2,"cantidad":5,"precio_usd":5}]') $$, 'No hay existencia suficiente de Champú');
select prueba.igual('la venta fallida no gasta número ni existencia', (select numero from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":2,"cantidad":2,"precio_usd":5}]')), 3::bigint);
select prueba.debe_fallar('el cajero no ve los movimientos', $$ do $x$ begin if (select count(*) from movimientos) = 0 then raise exception 'oculto'; end if; end $x$ $$, 'oculto');
select prueba.debe_fallar('el cajero no recibe compras', $$ select recibir_compra((select f from ids), '[]') $$, 'no recibe compras');

select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.debe_fallar('almacén no vende', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]') $$, 'no vende');
select prueba.igual('cada venta deja su movimiento', (select count(*) from movimientos where tipo = 'venta'), 5::bigint);

\echo '--- Salidas y ajustes'
select prueba.igual('salida por vencimiento', (select cantidad from salida_inventario((select id from lotes where lote = 'VIEJO'), 50, 'Vencido')), 0.000::numeric);
select prueba.debe_fallar('no sale más de lo que hay', $$ select salida_inventario((select id from lotes where lote = 'GV25'), 99, 'Dañado') $$, 'entre 1 y');
select prueba.debe_fallar('la salida necesita motivo', $$ select salida_inventario((select id from lotes where lote = 'GV25'), 1, '') $$, 'motivo');
select prueba.debe_fallar('almacén no ajusta', $$ select salida_inventario((select id from lotes where lote = 'GV25'), 3, 'Conteo', 'ajuste') $$, 'Solo el dueño');
select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.igual('el dueño ajusta al conteo', (select cantidad from salida_inventario((select id from lotes where lote = 'GV25'), 8, 'Conteo físico', 'ajuste')), 8.000::numeric);
select prueba.igual('el ajuste queda como movimiento de −1', (select cantidad from movimientos where tipo = 'ajuste'), -1.000::numeric);
select prueba.debe_fallar('los movimientos no se borran', $$ delete from movimientos $$, 'permission denied');
reset role;
select prueba.debe_fallar('ni el superusuario edita un movimiento', $$ update movimientos set cantidad = 0 $$, 'no se editan');
set role authenticated;

\echo '--- Notas de crédito y devoluciones'
select prueba.como('00000000-0000-0000-0000-00000000000d');
create temp table f1 as select * from documentos where numero = 1 and tipo = 'FAC';
grant select on f1 to authenticated;
-- La factura 1 vendió 7 Losartán: 5 de GV24 y 2 de GV25
select prueba.igual('NC de devolución', (select tipo::text from emitir_nota((select id from f1), 'NC',
  '[{"descripcion":"Losartán","cantidad":3,"precio_bs":300,"alicuota":"E","ref":{"producto_id":1}}]', 'Devolución de mercancía', true)), 'NC');
select prueba.igual('vuelve al último lote que se tomó (GV25: 8 + 2 = 10)', (select cantidad from lotes where lote = 'GV25'), 10.000::numeric);
select prueba.igual('y el resto al anterior (GV24: 0 + 1 = 1)', (select cantidad from lotes where lote = 'GV24'), 1.000::numeric);
select prueba.debe_fallar('no se devuelve más de lo vendido', $$ select emitir_nota((select id from f1), 'NC',
  '[{"descripcion":"Losartán","cantidad":5,"precio_bs":300,"alicuota":"E","ref":{"producto_id":1}}]', 'Devolución', true) $$, 'quedan 4 por devolver');
select emitir_nota((select id from f1), 'NC', '[{"descripcion":"Descuento","cantidad":1,"precio_bs":100,"alicuota":"E","ref":{"producto_id":1}}]', 'Descuento posterior', false);
select prueba.igual('un descuento no mueve inventario', (select cantidad from lotes where lote = 'GV25'), 10.000::numeric);
select prueba.igual('ND con el cliente de la factura', (select cliente_nombre from emitir_nota((select id from f1), 'ND',
  '[{"descripcion":"Delivery","cantidad":1,"precio_bs":200,"alicuota":"G"}]', 'Cargo por entrega')), 'María');
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero no emite notas', $$ select emitir_nota((select id from f1), 'ND', '[{"descripcion":"x","cantidad":1,"precio_bs":1,"alicuota":"E"}]', 'x') $$, 'Solo');

\echo '--- Clientes'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
insert into clientes (empresa_id, cedula_rif, nombre) values ((select f from ids), 'v12.990.441', 'José Peña');
select prueba.igual('la cédula se guarda normalizada', (select cedula_rif from clientes), 'V-12990441');
select prueba.debe_fallar('no se repite la cédula', $$ insert into clientes (empresa_id, cedula_rif, nombre) values ((select f from ids), 'V-12990441', 'Otro') $$, 'duplicate key');
select prueba.debe_fallar('cédula inválida', $$ insert into clientes (empresa_id, cedula_rif, nombre) values ((select f from ids), 'hola', 'X') $$, 'inválido');
select vender((select f from ids), '{"rif":"V-12.990.441","nombre":"José Peña"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3.5}]');
select prueba.igual('la venta le suma una visita', (select visitas from clientes), 1);
select prueba.igual('y el total en dólares', (select total_usd from clientes), 3.50::numeric);
select prueba.debe_fallar('el cajero no borra clientes', $$ delete from clientes $$, 'permission denied');

\echo '--- Otro negocio'
select prueba.como('00000000-0000-0000-0000-0000000000b1');
select prueba.igual('el laboratorio no ve el catálogo de la farmacia', (select count(*) from productos), 0::bigint);
select prueba.igual('ni sus clientes', (select count(*) from clientes), 0::bigint);
select prueba.debe_fallar('ni vende en la farmacia', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":1,"precio_usd":3}]') $$, 'no vende');
\echo '--- Todas las pruebas pasaron'
