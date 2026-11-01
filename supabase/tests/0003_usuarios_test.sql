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

\echo '--- Equipo y acceso'
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'kevin@azullab.com'),
  ('00000000-0000-0000-0000-0000000000c2', 'rosangela@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f, (select id from empresas where tipo = 'laboratorio') l;
grant select on ids to authenticated;

set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
select dar_acceso((select f from ids), 'Kevin@Azullab.com ', 'cajero', 'Caja 1');
select prueba.igual('el dueño da acceso por correo', (select rol::text from equipo((select f from ids)) where correo = 'kevin@azullab.com'), 'cajero');
select prueba.igual('el equipo trae la caja', (select caja from equipo((select f from ids)) where correo = 'kevin@azullab.com'), 'Caja 1');
select prueba.debe_fallar('correo que no existe', $$ select dar_acceso((select f from ids), 'nadie@x.com', 'cajero') $$, 'Créalo con');
select dar_acceso((select f from ids), 'kevin@azullab.com', 'almacen');
select prueba.igual('dar acceso otra vez cambia el rol', (select rol::text from equipo((select f from ids)) where correo = 'kevin@azullab.com'), 'almacen');
update perfiles set nombre = 'Kevin Albarrán' where user_id = '00000000-0000-0000-0000-0000000000c1';
select prueba.igual('el dueño corrige el nombre', (select nombre from equipo((select f from ids)) where correo = 'kevin@azullab.com'), 'Kevin Albarrán');
update miembros set activo = false where user_id = '00000000-0000-0000-0000-0000000000c1';
select prueba.igual('el dueño desactiva', (select activo from equipo((select f from ids)) where correo = 'kevin@azullab.com'), false);
select prueba.debe_fallar('el dueño no se quita su rol', $$ update miembros set rol = 'gerente' where user_id = '00000000-0000-0000-0000-00000000000d' and empresa_id = (select f from ids) $$, 'sin dueño');
select prueba.igual('puede crear usuarios', puedo_crear_usuarios((select f from ids), 'cajero'), true);

select dar_acceso((select f from ids), 'rosangela@azullab.com', 'gerente');
select prueba.como('00000000-0000-0000-0000-0000000000c2');
select prueba.igual('el gerente ve el equipo', (select count(*) from equipo((select f from ids))), 3::bigint);
select prueba.debe_fallar('el gerente no nombra dueños', $$ select dar_acceso((select f from ids), 'kevin@azullab.com', 'dueno') $$, 'Solo el dueño');
select prueba.igual('el gerente no puede crear dueños', puedo_crear_usuarios((select f from ids), 'dueno'), false);
select prueba.debe_fallar('el gerente no ve el equipo del laboratorio', $$ select * from equipo((select l from ids)) $$, 'Solo el dueño');
select prueba.debe_fallar('el gerente no edita nombres', $$ do $x$ begin update perfiles set nombre = 'X' where user_id = '00000000-0000-0000-0000-0000000000c1'; if not found then raise exception 'sin filas'; end if; end $x$ $$, 'sin filas');

select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.igual('desactivado no entra', (select count(*) from mi_acceso('farmacia')), 0::bigint);

\echo '--- Datos fiscales y tasa'
select prueba.como('00000000-0000-0000-0000-00000000000d');
update empresas set razon_social = 'Azullab Farmacia, C.A.', rif = 'J-41234567-8', domicilio = 'Av. Principal', datos_confirmados = true where id = (select f from ids);
select prueba.igual('el dueño guarda los datos fiscales', (select datos_confirmados from empresas where id = (select f from ids)), true);
insert into tasas_bcv (fecha, tasa, fuente) values (current_date, 500, 'Dueño') on conflict (fecha) do update set tasa = excluded.tasa, fuente = excluded.fuente;
select prueba.igual('el dueño carga la tasa', tasa_del_dia(), 500.0000::numeric);
insert into tasas_bcv (fecha, tasa, fuente) values (current_date, 501, 'Dueño') on conflict (fecha) do update set tasa = excluded.tasa;
select prueba.igual('y la corrige', tasa_del_dia(), 501.0000::numeric);
reset role;
select prueba.igual('queda en la auditoría', (select count(*) from auditoria where tabla = 'tasas_bcv') >= 2, true);
\echo '--- Todas las pruebas pasaron'
