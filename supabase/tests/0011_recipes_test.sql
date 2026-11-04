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

insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'), ('00000000-0000-0000-0000-0000000000a1', 'regente@azullab.com'), ('00000000-0000-0000-0000-0000000000c1', 'cajero@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000a1', (select f from ids), 'regente'), ('00000000-0000-0000-0000-0000000000c1', (select f from ids), 'cajero');
update empresas set datos_confirmados = true;
insert into tasas_bcv (fecha, tasa) values (current_date, 100);

\echo '--- Libro de controlados'
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000a1');
insert into productos (empresa_id, codigo, nombre, iva, costo, precio, controlado) values ((select f from ids), '1', 'Clonazepam 0,5 mg', 'E', 1, 2, true), ((select f from ids), '2', 'Losartán', 'E', 2, 3, false);
insert into proveedores (empresa_id, nombre) values ((select f from ids), 'Drolanca');
select recibir_factura((select f from ids), '{"proveedor_id":1,"numero":"0191544"}', '[{"producto_id":1,"lote":"RC25","vence":"2028-01-01","cantidad":30,"costo":1},{"producto_id":2,"lote":"L1","vence":"2028-01-01","cantidad":10,"costo":2}]');
select prueba.igual('la compra del controlado entra al libro', (select concepto from libro_controlados), 'Compra · Drolanca · factura 0191544');
select prueba.igual('con su entrada', (select entrada from libro_controlados), 30.000::numeric);
select prueba.igual('lo que no es controlado no va al libro', (select count(*) from libro_controlados), 1::bigint);

\echo '--- Récipe especial y venta'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('el cajero no registra récipes', $$ insert into recipes (empresa_id, paciente_ci, paciente, tipo, numero_especial, producto_id, producto, recetado, despachado) values ((select f from ids), 'V-1', 'X', 'especial', '1', 1, 'C', 1, 1) $$, 'Solo el regente');
select prueba.debe_fallar('sin récipe no se vende un controlado', $$ select vender((select f from ids), '{"rif":"V-18.456.123","nombre":"María"}', '[{"producto_id":1,"cantidad":10,"precio_usd":2}]') $$, 'registra primero el récipe especial');
select prueba.como('00000000-0000-0000-0000-0000000000a1');
insert into recipes (empresa_id, paciente_ci, paciente, medico, mpps, tipo, numero_especial, producto_id, producto, recetado, despachado)
values ((select f from ids), 'v18.456.123', 'María Rondón', 'Dr. Molina', '45.210', 'especial', '0012345', 1, 'Clonazepam 0,5 mg', 30, 20);
select prueba.igual('el récipe toma su número interno', (select numero from recipes), 1::bigint);
select prueba.igual('la cédula queda normalizada', (select paciente_ci from recipes), 'V-18456123');
select prueba.debe_fallar('el número de récipe especial no se repite', $$ insert into recipes (empresa_id, paciente_ci, paciente, tipo, numero_especial, producto_id, producto, recetado, despachado) values ((select f from ids), 'V-2', 'Otro', 'especial', '0012345', 1, 'C', 1, 1) $$, 'duplicate key');
select prueba.debe_fallar('no se despacha más de lo recetado', $$ insert into recipes (empresa_id, paciente_ci, paciente, tipo, numero_especial, producto_id, producto, recetado, despachado) values ((select f from ids), 'V-2', 'Otro', 'especial', '999', 1, 'C', 1, 5) $$, 'check constraint');
select prueba.debe_fallar('el especial lleva número', $$ insert into recipes (empresa_id, paciente_ci, paciente, tipo, producto_id, producto, recetado) values ((select f from ids), 'V-2', 'Otro', 'especial', 1, 'C', 1) $$, 'check constraint');
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.debe_fallar('a otro paciente no se le vende con ese récipe', $$ select vender((select f from ids), '{"rif":"V-1","nombre":"Otro"}', '[{"producto_id":1,"cantidad":10,"precio_usd":2}]') $$, 'registra primero');
select prueba.igual('con el récipe de la paciente sí', (select numero from vender((select f from ids), '{"rif":"V-18.456.123","nombre":"María Rondón"}', '[{"producto_id":1,"cantidad":15,"precio_usd":2}]')), 1::bigint);
select prueba.debe_fallar('no se vende más de lo que autoriza (20)', $$ select vender((select f from ids), '{"rif":"V-18456123","nombre":"María Rondón"}', '[{"producto_id":1,"cantidad":6,"precio_usd":2}]') $$, 'no alcanza');
select prueba.igual('lo que no es controlado se vende normal', (select numero from vender((select f from ids), '{"rif":"V-00000000","nombre":"Consumidor final"}', '[{"producto_id":2,"cantidad":1,"precio_usd":3}]')), 2::bigint);
select prueba.debe_fallar('el cajero no ve el libro', $$ do $x$ begin if (select count(*) from libro_controlados) = 0 then raise exception 'oculto'; end if; end $x$ $$, 'oculto');
select prueba.igual('ni los récipes', (select count(*) from recipes), 0::bigint);

select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.igual('la venta queda en el libro con el récipe y la factura', (select concepto from libro_controlados where salida > 0), 'Récipe especial N° 0012345 · factura 00000001');
select prueba.igual('con el médico y su MPPS', (select origen from libro_controlados where salida > 0), 'Dr. Molina · MPPS 45.210');
select prueba.igual('el récipe lleva lo vendido', (select vendido from recipes), 15.00::numeric);
select salida_inventario((select id from lotes where lote = 'RC25'), 2, 'Vencido');
select prueba.igual('la salida también va al libro', (select concepto from libro_controlados where concepto like 'Salida%'), 'Salida: Vencido');
select prueba.igual('el libro cuadra con el inventario (30 − 15 − 2)', (select sum(entrada - salida) from libro_controlados), (select sum(cantidad) from lotes where producto_id = 1));
select prueba.debe_fallar('el libro no se edita', $$ update libro_controlados set salida = 0 $$, 'permission denied');
select prueba.debe_fallar('el número del récipe no se cambia', $$ update recipes set numero = 9 $$, 'permission denied');
\echo '--- Alertas de pacientes'
insert into alertas_pacientes (empresa_id, cedula, texto, principios) values ((select f from ids), 'v18.456.123', 'Alergia a la penicilina', '{Amoxicilina, Penicilina}');
select prueba.igual('la cédula se normaliza', (select cedula from alertas_pacientes), 'V-18456123');
select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.igual('la caja ve qué principios frenar', alerta_principios((select f from ids), 'V-18.456.123'), '{amoxicilina,penicilina}'::text[]);
select prueba.igual('pero no el motivo', (select count(*) from alertas_pacientes), 0::bigint);
select prueba.igual('sin alerta, lista vacía', alerta_principios((select f from ids), 'V-1'), '{}'::text[]);
select prueba.debe_fallar('la caja no registra alertas', $$ insert into alertas_pacientes (empresa_id, cedula, texto) values ((select f from ids), 'V-1', 'x') $$, 'row-level security');
\echo '--- Todas las pruebas pasaron'
