-- Pruebas de la migración 0027 (vencimientos). Correr con:  supabase/tests/correr.sh
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
insert into tasas_bcv (fecha, tasa) values (current_date, 100);

set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into productos (empresa_id, nombre, iva, costo, margen, precio) values ((select f from ids), 'Losartán 50 mg', 'E', 2, 50, 3);
insert into productos (empresa_id, nombre, iva, costo, margen, precio, rx, controlado) values ((select f from ids), 'Clonazepam 2 mg', 'E', 3, 0, 3, true, true);

\echo '--- Recibir: ni vencido ni con el año mal escrito'
select prueba.debe_fallar('mercancía vencida no se recibe', $$ select recibir_compra((select f from ids), ('[{"producto_id":1,"lote":"V1","vence":"' || (current_date - 1) || '","cantidad":5,"costo":2}]')::jsonb) $$, 'ya está vencido');
select prueba.debe_fallar('un año de un dígito (0002) no entra', $$ select recibir_compra((select f from ids), '[{"producto_id":1,"lote":"V1","vence":"0002-01-31","cantidad":5,"costo":2}]') $$, 'ya está vencido');
select prueba.debe_fallar('ni un año imposible hacia adelante', $$ select recibir_compra((select f from ids), '[{"producto_id":1,"lote":"V1","vence":"2750-01-31","cantidad":5,"costo":2}]') $$, 'lotes_vence_razonable');
select prueba.igual('nada de eso dejó lotes', (select count(*) from lotes), 0::bigint);
select count(*) from recibir_compra((select f from ids), ('[{"producto_id":1,"lote":"hoy","vence":"' || current_date || '","cantidad":5,"costo":2},{"producto_id":1,"lote":"A","vence":"2031-01-31","cantidad":10,"costo":2},{"producto_id":2,"lote":"C","vence":"2031-01-31","cantidad":4,"costo":3}]')::jsonb);
select prueba.igual('lo que vence hoy o después sí entra', (select count(*) from lotes), 3::bigint);

\echo '--- Un lote que quedó mal escrito (como en la práctica del 10 nov)'
reset role;
-- como quedó antes de esta migración: sin la regla de fechas ni los candados
alter table lotes drop constraint lotes_vence_razonable;
set session_replication_role = replica;
update lotes set vence = '0002-01-31' where lote = 'A';
set session_replication_role = origin;
alter table lotes add constraint lotes_vence_razonable check (vence between date '2000-01-01' and date '2100-12-31') not valid;
set role authenticated;
select prueba.debe_fallar('con el año en 0002 está vencido: no se vende', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":8,"precio_usd":3}]') $$, 'No hay existencia suficiente');

\echo '--- Corregir el vencimiento'
select prueba.debe_fallar('sin motivo no', $$ select corregir_vencimiento((select id from lotes where lote = 'A'), '2027-01-31', ' ') $$, 'por qué se corrige');
select prueba.debe_fallar('otra vez con el año mal no', $$ select corregir_vencimiento((select id from lotes where lote = 'A'), '0027-01-31', 'Se escribió mal') $$, 'año de cuatro cifras');
select prueba.debe_fallar('motivo con código HTML no', $$ select corregir_vencimiento((select id from lotes where lote = 'A'), '2027-01-31', '<script>x</script>') $$, 'signos');
select prueba.debe_fallar('un lote que no existe', $$ select corregir_vencimiento(999, '2027-01-31', 'Se escribió mal') $$, 'Lote no encontrado');
select prueba.igual('el dueño lo corrige', (select vence from corregir_vencimiento((select id from lotes where lote = 'A'), '2027-01-31', 'Se escribió mal al recibir')), '2027-01-31'::date);
select prueba.debe_fallar('la misma fecha otra vez no', $$ select corregir_vencimiento((select id from lotes where lote = 'A'), '2027-01-31', 'Se escribió mal') $$, 'ya tiene ese vencimiento');
select prueba.igual('queda el rastro: fecha anterior, nueva, motivo y usuario',
  (select motivo || ' | ' || tipo || ' | ' || cantidad::int || ' | ' || (usuario = '00000000-0000-0000-0000-00000000000d') from movimientos where motivo like 'Vencimiento corregido%'),
  'Vencimiento corregido: 31/01/0002 → 31/01/2027 · Se escribió mal al recibir | ajuste | 0 | true');
select prueba.igual('la cantidad del lote no cambia', (select cantidad from lotes where lote = 'A'), 10.000::numeric);
select prueba.igual('ni el registro de inventario', (select compras || '/' || ajustes || '/' || final from registro_inventario((select f from ids)) where producto_id = 1), '15.000/0.000/15.000');
select prueba.igual('y ya se puede vender', (select numero from vender((select f from ids), '{"rif":"V-1","nombre":"X"}', '[{"producto_id":1,"cantidad":8,"precio_usd":3}]')), 1::bigint);
select prueba.igual('sale primero del que vence antes (el corregido)', (select string_agg(lote || ':' || cantidad::int, ',' order by lote) from lotes where producto_id = 1), 'A:7,HOY:0');
select count(*) from recibir_compra((select f from ids), '[{"producto_id":1,"lote":"A","vence":"2032-06-30","cantidad":1,"costo":2}]');
select prueba.debe_fallar('no puede chocar con otro lote igual', $$ select corregir_vencimiento((select id from lotes where lote = 'A' and vence = '2027-01-31'), '2032-06-30', 'Se escribió mal') $$, 'Ya hay otro lote');
select prueba.igual('en un controlado, la corrección pasa a su libro', (select vence from corregir_vencimiento((select id from lotes where lote = 'C'), '2030-12-31', 'Venía mal en la factura')), '2030-12-31'::date);
select prueba.igual('con entrada y salida en cero', (select concepto || ' | ' || entrada::int || '/' || salida::int from libro_controlados where concepto like 'Ajuste%'), 'Ajuste: Vencimiento corregido: 31/01/2031 → 31/12/2030 · Venía mal en la factura | 0/0');

\echo '--- Permisos'
select prueba.debe_fallar('nadie cambia el vencimiento por fuera de la función', $$ update lotes set vence = '2040-01-01' where lote = 'A' $$, 'permission denied');
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero no corrige vencimientos', $$ select corregir_vencimiento((select id from lotes where lote = 'C'), '2033-01-31', 'Se escribió mal') $$, 'Lote no encontrado');
select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.igual('almacén sí', (select vence from corregir_vencimiento((select id from lotes where lote = 'C'), '2031-01-31', 'Era la fecha de la factura')), '2031-01-31'::date);
reset role;
select set_config('request.jwt.claim.sub', '', false), set_config('request.jwt.claim.role', '', false);
set role anon;
select prueba.debe_fallar('sin entrar no se llama', $$ select corregir_vencimiento(1, '2033-01-31', 'Se escribió mal') $$, 'permission denied');
reset role;
\echo '--- Todas las pruebas pasaron'
