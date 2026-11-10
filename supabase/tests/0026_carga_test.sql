-- Pruebas de la migración 0026 (carga inicial del inventario). Correr con:  supabase/tests/correr.sh
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
  ('00000000-0000-0000-0000-0000000000a1', 'almacen@azullab.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'gerente@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f, (select id from empresas where tipo = 'laboratorio') l;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values
  ('00000000-0000-0000-0000-0000000000c1', (select f from ids), 'cajero'),
  ('00000000-0000-0000-0000-0000000000a1', (select f from ids), 'almacen'),
  ('00000000-0000-0000-0000-0000000000b1', (select f from ids), 'gerente');
update empresas set datos_confirmados = true;
insert into tasas_bcv (fecha, tasa) values (current_date, 100);

set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into productos (empresa_id, codigo, codigos_alt, nombre, iva, costo, margen, precio) values
  ((select f from ids), '7591020311042', '{7591020311059}', 'Losartán 50 mg', 'E', 2, 50, 3);
insert into proveedores (empresa_id, nombre, rif) values ((select f from ids), 'Cobeca', 'J-12345678-9');

\echo '--- Carga inicial: productos nuevos y existentes, con sus lotes'
create temp table c1 as select carga_inicial((select f from ids), '[
  {"producto_id":1,"lote":"gv24","vence":"2030-01-31","cantidad":5,"costo":2},
  {"codigo":"7591020311059","lote":"GV25","vence":"2031-03-31","cantidad":10,"costo":2.10},
  {"codigo":"7591020300015","nombre":"Acetaminofén 500 mg","principio_activo":"Acetaminofén","laboratorio":"Calox","presentacion":"Caja x 20","costo":0.80,"margen":30,"lote":"CX11","vence":"2030-06-30","cantidad":20},
  {"nombre":"Protector solar FPS 50","presentacion":"Tubo 120 ml","iva":"g","costo":6,"cantidad":6,"vence":"2030-12-31"},
  {"nombre":"Protector solar FPS 50","presentacion":"tubo 120 ml","costo":6,"cantidad":4,"vence":"2031-12-31","lote":"PS02"},
  {"codigo":"7591020300039","nombre":"Vitamina C 500 mg","costo":1.5,"precio":2.5}
]') r;
grant select on c1 to authenticated;
select prueba.igual('resumen de la carga', (select (r->>'renglones') || '/' || (r->>'productos_nuevos') || '/' || (r->>'lotes') || '/' || (r->>'unidades') from c1), '6/3/5/45');
select prueba.igual('el producto existente recibe sus dos lotes (por número y por código alterno)', (select string_agg(lote || ':' || cantidad::int, ',' order by lote) from lotes where producto_id = 1), 'GV24:5,GV25:10');
select prueba.igual('y no se duplica', (select count(*) from productos where nombre = 'Losartán 50 mg'), 1::bigint);
select prueba.igual('el producto nuevo queda con su precio (costo + % de ganancia)', (select precio || ' ' || margen || ' ' || iva from productos where codigo = '7591020300015'), '1.04 30.00 E');
select prueba.igual('sin código, dos renglones del mismo producto van al mismo (por nombre y presentación)', (select count(*) from productos where nombre = 'Protector solar FPS 50'), 1::bigint);
select prueba.igual('con su IVA', (select iva::text from productos where nombre = 'Protector solar FPS 50'), 'G');
select prueba.igual('sin lote queda como S/L', (select string_agg(lote || ':' || cantidad::int, ',' order by lote) from lotes l join productos p on p.id = l.producto_id where p.nombre = 'Protector solar FPS 50'), 'PS02:4,S/L:6');
select prueba.igual('sin cantidad solo entra al catálogo, con el precio que trae', (select precio || ' ' || (select count(*) from lotes where producto_id = p.id) from productos p where codigo = '7591020300039'), '2.50 0');
select prueba.igual('cada lote deja un movimiento «inicial»', (select count(*) || ' ' || sum(cantidad)::int from movimientos where tipo = 'inicial'), '5 45');

\echo '--- No es una compra'
select prueba.igual('no entra al Libro de Compras', (select count(*) from compras), 0::bigint);
select prueba.igual('ni deja deuda con ninguna droguería', (select coalesce(sum(total_usd - pagado_usd), 0) from compras), 0::numeric);
create temp table r as select * from registro_inventario((select f from ids));
grant select on r to authenticated;
select prueba.igual('en el registro del art. 177 sale como inicial, no como compra', (select inicial || '/' || compras || '/' || final from r where producto_id = 1), '15.000/0/15.000');
select prueba.igual('con su valor inicial al costo de cada lote', (select valor_inicial_usd || '/' || valor_final_usd from r where producto_id = 1), '31.00/31.00');
select count(*) from recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"0048213","control":"00-1","fecha":"' || current_date || '"}')::jsonb,
  '[{"producto_id":1,"lote":"GV26","vence":"2031-06-30","cantidad":20,"costo":2}]');
create temp table v as select * from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":7,"precio_usd":3}]');
select prueba.igual('se vende lo de la carga inicial, primero lo que vence antes', (select string_agg(lote || ':' || cantidad::int, ',' order by lote) from lotes where producto_id = 1), 'GV24:0,GV25:8,GV26:20');
select prueba.igual('inicial + compras − ventas = final', (select inicial || '/' || compras || '/' || ventas || '/' || final from registro_inventario((select f from ids)) where producto_id = 1), '15.000/20.000/7.000/28.000');
select prueba.igual('y la compra con factura sí va al Libro de Compras', (select count(*) from compras), 1::bigint);

\echo '--- Renglones malos: no entra nada'
select prueba.debe_fallar('sin vencimiento', $$ select carga_inicial((select f from ids), '[{"nombre":"Bueno","costo":1},{"producto_id":1,"lote":"X","cantidad":3}]') $$, 'Renglón 2: falta la fecha de vencimiento');
select prueba.igual('y el renglón bueno de esa carga tampoco quedó', (select count(*) from productos where nombre = 'Bueno'), 0::bigint);
select prueba.debe_fallar('sin nombre', $$ select carga_inicial((select f from ids), '[{"codigo":"999000111","cantidad":1,"vence":"2030-01-01"}]') $$, 'Renglón 1: falta el nombre');
select prueba.debe_fallar('cantidad negativa', $$ select carga_inicial((select f from ids), '[{"producto_id":1,"lote":"X","vence":"2030-01-01","cantidad":-3}]') $$, 'negativos');
select prueba.debe_fallar('IVA inventado', $$ select carga_inicial((select f from ids), '[{"nombre":"Otro","iva":"X"}]') $$, 'el IVA debe ser');
select prueba.debe_fallar('fecha que no es fecha', $$ select carga_inicial((select f from ids), '[{"producto_id":1,"lote":"X","vence":"31/31/2030","cantidad":1}]') $$, 'Renglón 1');
select prueba.debe_fallar('producto de otro negocio o inexistente', $$ select carga_inicial((select f from ids), '[{"producto_id":999,"lote":"X","vence":"2030-01-01","cantidad":1}]') $$, 'producto no encontrado');
select prueba.debe_fallar('nombre con código HTML', $$ select carga_inicial((select f from ids), '[{"nombre":"<img src=x>"}]') $$, 'signos');
select prueba.debe_fallar('carga vacía', $$ select carga_inicial((select f from ids), '[]') $$, 'no trae renglones');
select prueba.debe_fallar('solo en la farmacia', $$ select carga_inicial((select l from ids), '[{"nombre":"X"}]') $$, 'es de la farmacia');
select prueba.igual('después de los intentos malos, los movimientos iniciales siguen iguales', (select count(*) from movimientos where tipo = 'inicial'), 5::bigint);

\echo '--- Controlados'
select prueba.debe_fallar('un controlado sin lote no entra', $$ select carga_inicial((select f from ids), '[{"nombre":"Clonazepam 2 mg","controlado":true,"costo":3,"cantidad":10,"vence":"2030-01-01"}]') $$, 'necesita su número de lote');
select carga_inicial((select f from ids), '[{"nombre":"Clonazepam 2 mg","controlado":true,"costo":3,"cantidad":10,"vence":"2030-01-01","lote":"RV1"}]');
select prueba.igual('el controlado queda con récipe obligatorio', (select rx and controlado from productos where nombre = 'Clonazepam 2 mg'), true);
select prueba.igual('y en el libro de controlados como inventario inicial', (select concepto || ' · ' || entrada::int from libro_controlados where producto = 'Clonazepam 2 mg'), 'Inventario inicial · 10');

\echo '--- Permisos'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero no hace la carga inicial', $$ select carga_inicial((select f from ids), '[{"nombre":"X"}]') $$, 'Solo el dueño o el gerente');
select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.debe_fallar('almacén tampoco (recibe compras con factura)', $$ select carga_inicial((select f from ids), '[{"nombre":"X"}]') $$, 'Solo el dueño o el gerente');
select prueba.debe_fallar('nadie mete un movimiento «inicial» a mano', $$ insert into movimientos (empresa_id, producto_id, tipo, cantidad) values ((select f from ids), 1, 'inicial', 100) $$, 'permission denied');
select prueba.como('00000000-0000-0000-0000-0000000000b1');
select prueba.igual('el gerente sí carga', (select (carga_inicial((select f from ids), '[{"producto_id":1,"lote":"GV27","vence":"2031-01-01","cantidad":2}]')->>'lotes')), '1');
select prueba.debe_fallar('pero no la cierra', $$ select cerrar_carga_inicial((select f from ids)) $$, 'Solo el dueño');
reset role;
select set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claim.role', '', false);
set role anon;
select prueba.debe_fallar('sin entrar no se llama', $$ select carga_inicial((select f from ids), '[{"nombre":"X"}]') $$, 'permission denied');
reset role;

\echo '--- Cerrar la carga inicial'
set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.debe_fallar('no se cierra editando la empresa a mano', $$ update empresas set carga_inicial_cerrada = now() where id = (select f from ids) $$, 'se cierra con su botón');
select prueba.igual('el dueño la cierra', (select cerrar_carga_inicial((select f from ids)) is not null), true);
select prueba.debe_fallar('cerrada, no entra más inventario sin factura', $$ select carga_inicial((select f from ids), '[{"producto_id":1,"lote":"Z","vence":"2031-01-01","cantidad":1}]') $$, 'ya se cerró');
select prueba.debe_fallar('ni el dueño la reabre', $$ update empresas set carga_inicial_cerrada = null where id = (select f from ids) $$, 'no se vuelve a abrir');
select prueba.igual('cerrarla otra vez no cambia la fecha', (select cerrar_carga_inicial((select f from ids))), (select carga_inicial_cerrada from empresas where id = (select f from ids)));
update empresas set contador = 'Lic. Prueba' where id = (select f from ids);
select prueba.igual('los demás datos de la empresa se siguen editando', (select contador from empresas where id = (select f from ids)), 'Lic. Prueba');
select count(*) from recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"0048214","control":"00-2","fecha":"' || current_date || '"}')::jsonb,
  '[{"producto_id":1,"lote":"GV28","vence":"2031-06-30","cantidad":1,"costo":2}]');
select prueba.igual('las compras con factura siguen entrando', (select count(*) from compras), 2::bigint);
reset role;
select set_config('request.jwt.claim.sub', '', false);   -- como en el SQL Editor: sin usuario
update empresas set carga_inicial_cerrada = null where tipo = 'farmacia';
select prueba.igual('Cuadre (sin usuario) sí puede reabrirla', (select carga_inicial_cerrada is null from empresas where tipo = 'farmacia'), true);
\echo '--- Todas las pruebas pasaron'
