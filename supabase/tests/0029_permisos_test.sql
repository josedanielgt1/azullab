-- Pruebas de la migración 0029 (permisos por rol que decide el dueño). Correr con:  supabase/tests/correr.sh
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

insert into auth.users (id, email) values ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com'),
  ('00000000-0000-0000-0000-0000000000a1', 'gerente@azullab.com'), ('00000000-0000-0000-0000-0000000000a2', 'regente@azullab.com'), ('00000000-0000-0000-0000-0000000000a3', 'cajero@azullab.com');
create temp table ids as select (select id from empresas where tipo = 'farmacia') f, (select id from empresas where tipo = 'laboratorio') l;
grant select on ids to authenticated;
insert into miembros (user_id, empresa_id, rol) values ('00000000-0000-0000-0000-0000000000a1', (select f from ids), 'gerente'),
  ('00000000-0000-0000-0000-0000000000a2', (select f from ids), 'regente'), ('00000000-0000-0000-0000-0000000000a3', (select f from ids), 'cajero');

set role authenticated;

\echo '--- El dueño decide los permisos'
select prueba.como('00000000-0000-0000-0000-00000000000d');
insert into colecciones (empresa_id, nombre, datos) values ((select f from ids), 'permisos', '{"regente": ["caja", "compras"], "cajero": ["caja", "fiscal"]}');
select prueba.igual('el dueño guarda los permisos por rol', (select datos->'cajero' from colecciones where nombre = 'permisos'), '["caja", "fiscal"]'::jsonb);
update colecciones set datos = '{"regente": ["caja"], "cajero": ["caja"]}' where nombre = 'permisos' and empresa_id = (select f from ids);
select prueba.igual('y los cambia cuando quiera', (select datos->'regente' from colecciones where nombre = 'permisos'), '["caja"]'::jsonb);
select prueba.debe_fallar('al dueño no se le quitan permisos', $$ update colecciones set datos = '{"dueno": ["caja"]}' where nombre = 'permisos' $$, 'El dueño tiene todos los permisos');
select prueba.debe_fallar('ni se inventan roles', $$ update colecciones set datos = '{"socio": ["caja"]}' where nombre = 'permisos' $$, 'Rol desconocido');
select prueba.debe_fallar('cada rol es una lista de nombres', $$ update colecciones set datos = '{"cajero": "caja"}' where nombre = 'permisos' $$, 'lista de nombres');
select prueba.debe_fallar('y la lista va por rol', $$ update colecciones set datos = '["caja"]' where nombre = 'permisos' $$, 'van por rol');

\echo '--- Los demás la leen, pero no la cambian'
select prueba.como('00000000-0000-0000-0000-0000000000a3');
select prueba.igual('el cajero lee sus permisos', (select datos->'cajero' from colecciones where nombre = 'permisos'), '["caja"]'::jsonb);
update colecciones set datos = '{"cajero": ["caja", "finanzas"]}' where nombre = 'permisos';
select prueba.como('00000000-0000-0000-0000-0000000000a2');
update colecciones set datos = '{"regente": ["caja", "finanzas"]}' where nombre = 'permisos';
select prueba.como('00000000-0000-0000-0000-0000000000a1');
update colecciones set datos = '{"gerente": ["caja"], "cajero": ["caja", "finanzas"]}' where nombre = 'permisos';
select prueba.debe_fallar('el gerente tampoco la crea ni la reemplaza', $$ insert into colecciones (empresa_id, nombre, datos) values ((select f from ids), 'permisos', '{}') on conflict (empresa_id, nombre) do update set datos = '{}' $$, 'row-level security');
select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.igual('ni el cajero, ni el regente, ni el gerente cambiaron los permisos', (select datos from colecciones where nombre = 'permisos'), '{"regente": ["caja"], "cajero": ["caja"]}'::jsonb);

\echo '--- El gerente sigue manejando las otras listas'
select prueba.como('00000000-0000-0000-0000-0000000000a1');
insert into colecciones (empresa_id, nombre, datos) values ((select f from ids), 'secciones', '["Medicamentos"]');
select prueba.igual('el gerente guarda las secciones', (select datos from colecciones where nombre = 'secciones'), '["Medicamentos"]'::jsonb);
select prueba.como('00000000-0000-0000-0000-0000000000a3');
insert into colecciones (empresa_id, nombre, datos) values ((select f from ids), 'equipo_fallas', '[]');
select prueba.igual('el cajero sigue anotando fallas', (select count(*) from colecciones where nombre = 'equipo_fallas'), 1::bigint);

reset role;
\echo '--- Fin'
