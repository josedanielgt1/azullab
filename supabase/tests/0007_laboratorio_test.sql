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

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'),
  ('00000000-0000-0000-0000-0000000000a1', 'atencion@azullab.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'bio@azullab.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'toma@azullab.com'),
  ('00000000-0000-0000-0000-0000000000f1', 'cajero@farmacia.com');
create temp table ids as select (select id from empresas where tipo = 'laboratorio') l, (select id from empresas where tipo = 'farmacia') f;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values
  ('00000000-0000-0000-0000-0000000000a1', (select l from ids), 'atencion'),
  ('00000000-0000-0000-0000-0000000000b1', (select l from ids), 'bioanalista'),
  ('00000000-0000-0000-0000-0000000000c1', (select l from ids), 'toma_muestras'),
  ('00000000-0000-0000-0000-0000000000f1', (select f from ids), 'cajero');
update empresas set datos_confirmados = true;
insert into tasas_bcv (fecha, tasa) values (current_date - 1, 90), (current_date, 100);
update empresas set talonario_desde = 1, talonario_hasta = 50;

\echo '--- Catálogo'
set role authenticated;
select prueba.como('00000000-0000-0000-0000-0000000000b1');
insert into examenes (empresa_id, codigo, nombre, area, precio, parametros) values
  ((select l from ids), 'HEM', 'Hematología completa', 'Hematología', 5, '[{"k":"hb","n":"Hemoglobina"}]'),
  ((select l from ids), 'GLI', 'Glicemia', 'Química', 2, '[{"k":"gli","n":"Glucosa"}]');
select prueba.igual('el bioanalista arma el catálogo', (select count(*) from examenes), 2::bigint);
select prueba.debe_fallar('el bioanalista no pone perfiles con precio', $$ insert into perfiles_lab (empresa_id, codigo, nombre, examenes, precio) values ((select l from ids), 'P2', 'Perfil 2', '{HEM,GLI}', 6) $$, 'row-level security');
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into perfiles_lab (empresa_id, codigo, nombre, examenes, precio) values ((select l from ids), 'P2', 'Básico', '{HEM,GLI}', 6);

\echo '--- Paciente y orden'
select prueba.como('00000000-0000-0000-0000-0000000000a1');
insert into pacientes (empresa_id, cedula, nombre, sexo, nacimiento, telefono, datos) values ((select l from ids), 'V-9.876.543', 'María Rondón', 'F', '1968-04-12', '0414', '{"sangre":"O+"}');
select prueba.debe_fallar('no se repite la cédula (aunque se escriba distinto)', $$ insert into pacientes (empresa_id, cedula, nombre) values ((select l from ids), 'v9876543', 'Otra') $$, 'duplicate key');
insert into pacientes (empresa_id, cedula, nombre) values ((select l from ids), '', 'Bebé sin cédula'), ((select l from ids), '', 'Otro bebé');
select prueba.igual('los menores sin cédula sí entran', (select count(*) from pacientes), 3::bigint);
create temp table o1 as select crear_orden((select l from ids), (select id from pacientes where nombre = 'María Rondón'),
  '[{"k":"perf","c":"P2"},{"k":"ex","c":"GLI"}]', 'Dr. Albarrán', true, '{"ayuno":"12 h"}', '[{"metodo":"Pago móvil","monto_bs":800}]') r;
grant select on o1 to authenticated;
select prueba.igual('la orden toma el número L-0001', (select r->'orden'->>'numero' from o1), 'L-0001');
select prueba.igual('con el total del catálogo (6 + 2)', (select (r->'orden'->>'total_usd')::numeric from o1), 8.00::numeric);
select prueba.igual('y su factura exenta (800 Bs)', (select (r->'documento'->>'total')::numeric from o1), 800.00::numeric);
select prueba.igual('el perfil sale como «Perfil Básico»', (select descripcion from documento_lineas where renglon = 1), 'Perfil Básico');
select prueba.igual('la factura queda enlazada', (select documento_id::text from ordenes), (select r->'documento'->>'id' from o1));
select prueba.igual('la segunda es L-0002', (select crear_orden((select l from ids), (select id from pacientes where nombre = 'Bebé sin cédula'), '[{"k":"ex","c":"HEM"}]')->'orden'->>'numero'), 'L-0002');
select prueba.debe_fallar('examen que no está en el catálogo', $$ select crear_orden((select l from ids), 1, '[{"k":"ex","c":"XYZ"}]') $$, 'no está en el catálogo');
select prueba.debe_fallar('no se insertan órdenes a mano', $$ insert into ordenes (empresa_id, numero, paciente_id, items, total_usd) values ((select l from ids), 'L-9', 1, '[]', 0) $$, 'permission denied');
select prueba.debe_fallar('no se cambia lo cobrado', $$ update ordenes set total_usd = 1 where numero = 'L-0001' $$, 'no se cambia');
select prueba.debe_fallar('atención no carga resultados', $$ update ordenes set datos = '{"res":{"hb":13}}' where numero = 'L-0001' $$, 'Solo el bioanalista carga');

\echo '--- Toma, resultados y validación'
select prueba.como('00000000-0000-0000-0000-0000000000c1');
update ordenes set estado = 'En proceso', datos = datos || '{"toma":"07:05"}' where numero = 'L-0001';
select prueba.igual('toma de muestras marca la toma', (select estado from ordenes where numero = 'L-0001'), 'En proceso');
select prueba.debe_fallar('toma de muestras no crea órdenes', $$ select crear_orden((select l from ids), 1, '[{"k":"ex","c":"HEM"}]') $$, 'no crea órdenes');
select prueba.como('00000000-0000-0000-0000-0000000000b1');
update ordenes set estado = 'Por validar', datos = datos || '{"res":{"hb":13.1,"gli":95}}' where numero = 'L-0001';
select prueba.igual('el bioanalista carga resultados', (select datos->'res'->>'gli' from ordenes where numero = 'L-0001'), '95');
select prueba.como('00000000-0000-0000-0000-0000000000a1');
select prueba.debe_fallar('atención no valida', $$ update ordenes set estado = 'Validado' where numero = 'L-0001' $$, 'Solo el bioanalista valida');
select prueba.como('00000000-0000-0000-0000-0000000000b1');
update ordenes set estado = 'Validado', datos = datos || '{"val":{"by":"Lcda. Rivas","t":"10:12"}}' where numero = 'L-0001';
select prueba.debe_fallar('un resultado validado no se cambia', $$ update ordenes set datos = jsonb_set(datos, '{res,gli}', '110') where numero = 'L-0001' $$, 'validado ya no se cambia');
select prueba.como('00000000-0000-0000-0000-0000000000a1');
update ordenes set estado = 'Entregado', datos = datos || '{"ent":"10:40 · WhatsApp"}' where numero = 'L-0001';
select prueba.igual('atención entrega', (select estado from ordenes where numero = 'L-0001'), 'Entregado');
select prueba.debe_fallar('las órdenes no se borran', $$ delete from ordenes $$, 'permission denied');

\echo '--- Anulación'
select prueba.debe_fallar('no se anula sin nota de crédito', $$ update ordenes set estado = 'Anulada' where numero = 'L-0002' $$, 'nota de crédito');
select emitir_nota((select documento_id from ordenes where numero = 'L-0002'), 'NC', '[{"descripcion":"Hematología","cantidad":1,"precio_bs":500,"alicuota":"E"}]', 'Anulación de la orden', true);
update ordenes set estado = 'Anulada' where numero = 'L-0002';
select prueba.igual('con su nota de crédito, sí', (select estado from ordenes where numero = 'L-0002'), 'Anulada');
select prueba.debe_fallar('una anulada no se reabre', $$ update ordenes set estado = 'Por tomar' where numero = 'L-0002' $$, 'no se reabre');

\echo '--- Orden sin internet'
select prueba.como('00000000-0000-0000-0000-0000000000a1');
create temp table oc as select crear_orden((select l from ids), (select id from pacientes where nombre = 'María Rondón'), '[{"k":"ex","c":"GLI"}]', null, false, '{}', '[]', 'contingencia', 3, (current_date - 1 + time '08:00')::timestamptz) r;
grant select on oc to authenticated;
select prueba.igual('la factura queda con el número del talonario', (select (r->'documento'->>'numero')::int from oc), 3);
select prueba.igual('y la tasa del día en que se cobró', (select (r->'documento'->>'tasa')::numeric from oc), 90.0000::numeric);
select prueba.igual('la orden queda con esa fecha', (select (r->'orden'->>'creado_en')::timestamptz::date from oc), current_date - 1);

\echo '--- Privacidad'
select prueba.como('00000000-0000-0000-0000-0000000000f1');
select prueba.igual('la farmacia no ve pacientes del laboratorio', (select count(*) from pacientes), 0::bigint);
select prueba.igual('ni sus órdenes', (select count(*) from ordenes), 0::bigint);
\echo '--- Todas las pruebas pasaron'
