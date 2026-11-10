-- Pruebas de supabase/reiniciar_farmacia.sql (borrar la práctica de la farmacia). Correr con:  supabase/tests/correr.sh
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

create schema prueba;
grant usage on schema prueba to authenticated, anon, service_role;
create function prueba.como(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, false), set_config('request.jwt.claim.role', 'authenticated', false)
$$;
create function prueba.igual(caso text, obtenido anyelement, esperado anyelement) returns void language plpgsql as $$
begin
  if obtenido is distinct from esperado then raise exception 'FALLA %: salió %, esperaba %', caso, obtenido, esperado; end if;
  raise notice 'ok   %', caso;
end $$;
grant execute on all functions in schema prueba to authenticated, anon, service_role;

insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'), ('00000000-0000-0000-0000-0000000000c1', 'cajero@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f, (select id from empresas where tipo = 'laboratorio') l, (select id from empresas where tipo = 'crossfit') x;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000c1', (select f from ids), 'cajero');
update empresas set datos_confirmados = true;
insert into tasas_bcv (fecha, tasa) values (current_date, 100);

\echo '--- Una práctica completa en la farmacia, y datos en los otros dos negocios'
set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into productos (empresa_id, nombre, iva, costo, margen, precio) values ((select f from ids), 'Losartán 50 mg', 'E', 2, 50, 3);
insert into productos (empresa_id, nombre, iva, costo, margen, precio, rx, controlado) values ((select f from ids), 'Clonazepam 2 mg', 'E', 3, 0, 3, true, true);
insert into proveedores (empresa_id, nombre, rif) values ((select f from ids), 'Cobeca', 'J-12345678-9');
insert into clientes (empresa_id, cedula_rif, nombre) values ((select f from ids), 'V-12345678', 'Cliente de práctica'), ((select l from ids), 'V-87654321', 'Paciente del laboratorio');
insert into gastos (empresa_id, usd, datos) values ((select f from ids), 10, '{"c":"Luz"}');
insert into colecciones (empresa_id, nombre, datos) values ((select f from ids), 'fallas', '[]'), ((select x from ids), 'ajustes', '{}');
create temp table fac as select * from recibir_factura((select f from ids), ('{"proveedor_id":1,"numero":"0048213","control":"00-1","fecha":"' || current_date || '"}')::jsonb,
  '[{"producto_id":1,"lote":"A","vence":"2031-01-01","cantidad":20,"costo":2},{"producto_id":2,"lote":"B","vence":"2031-01-01","cantidad":5,"costo":3}]');
create temp table v as select * from vender((select f from ids), '{"rif":"V-12345678","nombre":"Cliente de práctica"}', '[{"producto_id":1,"cantidad":7,"precio_usd":3}]', '[{"metodo":"Efectivo Bs","monto_bs":2100}]');
grant select on v, fac to authenticated;
select emitir_nota((select id from v), 'NC', '[{"descripcion":"Losartán","cantidad":2,"precio_bs":300,"alicuota":"E","ref":{"producto_id":1}}]', 'Devolución de mercancía', true);
select salida_inventario((select id from lotes where lote = 'A'), 1, 'Merma o rotura');
select salida_inventario((select id from lotes where lote = 'B'), 1, 'Vencido');
reset role;
select set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claim.role', '', false);
insert into documentos (empresa_id, tipo, numero, serie, cliente_rif, cliente_nombre, tasa, total, total_usd, creado_por)
  values ((select l from ids), 'FAC', 1, '00', 'V-87654321', 'Paciente del laboratorio', 100, 500, 5, '00000000-0000-0000-0000-00000000000d');
select prueba.igual('la práctica dejó facturas, movimientos, compras y libro de controlados',
  (select (select count(*) from documentos where empresa_id = f) > 0 and (select count(*) from movimientos where empresa_id = f) > 0 and (select count(*) from compras where empresa_id = f) > 0
      and (select count(*) from libro_controlados where empresa_id = f) > 0 and (select count(*) from auditoria where empresa_id = f) > 0 from ids), true);
create temp table antes as select (select count(*) from documentos where empresa_id = (select l from ids)) docs_lab, (select count(*) from clientes where empresa_id = (select l from ids)) cli_lab,
  (select count(*) from colecciones where empresa_id = (select x from ids)) col_box, (select count(*) from miembros) miembros, (select count(*) from tasas_bcv) tasas, (select count(*) from auth.users) usuarios;

\echo '--- Sin escribir el RIF no hace nada'
-- Los intentos que deben fallar corren como en el SQL Editor: en una conexión aparte, sin usuario
\setenv PGDATABASE :DBNAME
\! psql -q -v ON_ERROR_STOP=1 -f reiniciar_farmacia.sql >/dev/null 2>&1
select prueba.igual('tal como viene el archivo, no borra nada', (select count(*) from documentos where empresa_id = (select f from ids)) > 0, true);
\! sed "s/ESCRIBE AQUI EL RIF DE LA FARMACIA/J-99999999-9/" reiniciar_farmacia.sql > /tmp/cuadre_reiniciar_mal.sql
\! psql -q -v ON_ERROR_STOP=1 -f /tmp/cuadre_reiniciar_mal.sql >/dev/null 2>&1
select prueba.igual('con el RIF de otro negocio, tampoco', (select count(*) from productos where empresa_id = (select f from ids)), 2::bigint);

\echo '--- Con una factura de máquina fiscal de verdad, se niega'
set session_replication_role = replica;
update documentos set medio = 'maquina', maquina_registro = 'Z7C0012345', numero_fiscal = 15 where id = (select id from v);
set session_replication_role = origin;
\! sed "s/ESCRIBE AQUI EL RIF DE LA FARMACIA/j-00000001-0/" reiniciar_farmacia.sql > /tmp/cuadre_reiniciar_bien.sql
\! psql -q -v ON_ERROR_STOP=1 -f /tmp/cuadre_reiniciar_bien.sql >/dev/null 2>&1
select prueba.igual('no borra si hay facturas fiscales reales', (select count(*) from documentos where empresa_id = (select f from ids)) > 0, true);
select prueba.igual('y los candados siguen puestos (un intento fallido no los deja apagados)', (select count(*) from pg_trigger where tgrelid = 'movimientos'::regclass and not tgisinternal and tgenabled = 'D'), 0::bigint);
-- vuelve a ser de la impresora simulada (números desde 900000001)
set session_replication_role = replica;
update documentos set numero_fiscal = 900000001 where id = (select id from v);
set session_replication_role = origin;

\echo '--- Con el RIF correcto, borra la práctica de la farmacia'
\o /dev/null
\i /tmp/cuadre_reiniciar_bien.sql
\o
select prueba.igual('la farmacia queda vacía', (select sum(n) from (
  select count(*) n from productos where empresa_id = (select f from ids) union all select count(*) from lotes where empresa_id = (select f from ids)
  union all select count(*) from movimientos where empresa_id = (select f from ids) union all select count(*) from documentos where empresa_id = (select f from ids)
  union all select count(*) from compras where empresa_id = (select f from ids) union all select count(*) from pagos_compras where empresa_id = (select f from ids)
  union all select count(*) from proveedores where empresa_id = (select f from ids) union all select count(*) from clientes where empresa_id = (select f from ids)
  union all select count(*) from gastos where empresa_id = (select f from ids) union all select count(*) from libro_controlados where empresa_id = (select f from ids)
  union all select count(*) from colecciones where empresa_id = (select f from ids) union all select count(*) from correlativos where empresa_id = (select f from ids)
  union all select count(*) from auditoria where empresa_id = (select f from ids)) q), 0::numeric);
select prueba.igual('sin renglones ni pagos de facturas huérfanos', (select (select count(*) from documento_lineas l where not exists (select 1 from documentos d where d.id = l.documento_id))
  + (select count(*) from documento_pagos p where not exists (select 1 from documentos d where d.id = p.documento_id))), 0::bigint);
select prueba.igual('el laboratorio y el CrossFit quedan intactos, igual que usuarios y tasas',
  (select row(a.*)::text from antes a),
  (select row((select count(*) from documentos where empresa_id = (select l from ids)), (select count(*) from clientes where empresa_id = (select l from ids)),
    (select count(*) from colecciones where empresa_id = (select x from ids)), (select count(*) from miembros), (select count(*) from tasas_bcv), (select count(*) from auth.users))::text));
select prueba.igual('las tres empresas siguen ahí', (select count(*) from empresas), 3::bigint);
select prueba.igual('la farmacia conserva su RIF pero queda sin confirmar', (select rif || ' ' || datos_confirmados from empresas where tipo = 'farmacia'), 'J-00000001-0 false');
select prueba.igual('los otros negocios siguen confirmados', (select bool_and(datos_confirmados) from empresas where tipo <> 'farmacia'), true);
select prueba.igual('todos los candados vuelven a quedar puestos', (select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relnamespace = 'public'::regnamespace and not t.tgisinternal and t.tgenabled = 'D'), 0::bigint);

\echo '--- Y la farmacia arranca de nuevo, desde la factura 1'
update empresas set datos_confirmados = true where tipo = 'farmacia';
set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into productos (empresa_id, nombre, iva, costo, margen, precio) values ((select f from ids), 'Acetaminofén 500 mg', 'E', 1, 30, 1.3);
insert into proveedores (empresa_id, nombre, rif) values ((select f from ids), 'Drolanca', 'J-12345678-9');
select count(*) from recibir_factura((select f from ids), ('{"proveedor_id":' || (select id from proveedores where nombre = 'Drolanca') || ',"numero":"0048213","control":"00-1","fecha":"' || current_date || '"}')::jsonb,
  ('[{"producto_id":' || (select id from productos where nombre = 'Acetaminofén 500 mg') || ',"lote":"A","vence":"2031-01-01","cantidad":10,"costo":1}]')::jsonb);
select prueba.igual('la primera factura real es la número 1', (select numero from vender((select f from ids), '{"rif":"V-9","nombre":"Primer cliente"}',
  ('[{"producto_id":' || (select id from productos where nombre = 'Acetaminofén 500 mg') || ',"cantidad":1,"precio_usd":1.3}]')::jsonb)), 1::bigint);
select prueba.igual('los documentos vuelven a estar protegidos', (select count(*) from (select 1 from documentos where empresa_id = (select f from ids)) q), 1::bigint);
reset role;
do $$ begin
  begin delete from movimientos where empresa_id = (select id from empresas where tipo = 'farmacia'); exception when others then raise notice 'ok   y los movimientos nuevos no se pueden borrar'; return; end;
  raise exception 'FALLA: los movimientos se pudieron borrar después del reinicio';
end $$;
\echo '--- Todas las pruebas pasaron'
