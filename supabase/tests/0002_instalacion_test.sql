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

\echo '--- Instalación'
select prueba.igual('vienen las tres empresas', (select count(*) from empresas), 3::bigint);
select prueba.igual('ninguna factura sin confirmar sus datos', (select count(*) from empresas where datos_confirmados), 0::bigint);
insert into tasas_bcv (fecha, tasa) values (current_date, 862.15);

-- Se crea el primer usuario (como en Authentication → Add user)
insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-00000000000d', 'jose@azullab.com', '{"nombre":"José Guerrero"}');
select prueba.igual('el primero es dueño de los tres negocios', (select count(*) from miembros where rol = 'dueno'), 3::bigint);
select prueba.igual('se le crea su perfil', (select nombre from perfiles where user_id = '00000000-0000-0000-0000-00000000000d'), 'José Guerrero');

insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000c1', 'cajero@azullab.com');
select prueba.igual('el segundo entra sin rol', (select count(*) from miembros where user_id = '00000000-0000-0000-0000-0000000000c1'), 0::bigint);
select prueba.igual('con perfil a partir del correo', (select nombre from perfiles where user_id = '00000000-0000-0000-0000-0000000000c1'), 'cajero');

set role authenticated;
select prueba.como('00000000-0000-0000-0000-00000000000d');
select prueba.igual('mi_acceso: el dueño en la farmacia', (select rol::text from mi_acceso('farmacia')), 'dueno');
select prueba.igual('mi_acceso: con su nombre', (select nombre from mi_acceso('laboratorio')), 'José Guerrero');
select prueba.debe_fallar('no factura sin datos fiscales confirmados',
  $$ select emitir_documento((select id from empresas where tipo = 'farmacia'), 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]') $$, 'Faltan los datos fiscales');
update empresas set rif = 'J-41234567-8', datos_confirmados = true where tipo = 'farmacia';
select prueba.igual('el dueño edita el RIF', (select rif from empresas where tipo = 'farmacia'), 'J-41234567-8');
select prueba.igual('ya factura', (select numero from emitir_documento((select id from empresas where tipo = 'farmacia'), 'FAC', '{"rif":"V-1","nombre":"X"}', '[{"descripcion":"x","cantidad":1,"precio_usd":1,"alicuota":"E"}]')), 1::bigint);
select prueba.debe_fallar('RIF con formato malo', $$ update empresas set rif = 'J-123' where tipo = 'crossfit' $$, 'check constraint');

select prueba.como('00000000-0000-0000-0000-0000000000c1');
select prueba.igual('sin rol no entra a ningún negocio', (select count(*) from mi_acceso('farmacia')), 0::bigint);
select prueba.igual('sin rol no ve empresas', (select count(*) from empresas), 0::bigint);
\echo '--- Todas las pruebas pasaron'
