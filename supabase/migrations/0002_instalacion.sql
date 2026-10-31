-- =====================================================================
-- Cuadre · Migración 0002: instalación del Grupo Azullab
--   * Las tres empresas, con datos fiscales que el dueño edita en
--     Configuración. Hasta que los confirme, ese negocio no factura.
--   * El primer usuario que se crea en Authentication queda como dueño
--     de los tres negocios. Los demás entran sin rol hasta que el dueño
--     se lo asigne.
--   * mi_acceso(): con el correo y la clave, el sistema sabe quién entra
--     y con qué rol, sin escogerlo en la pantalla.
-- =====================================================================

alter type rol_usuario add value if not exists 'toma_muestras';   -- laboratorio

alter table empresas add column if not exists datos_confirmados boolean not null default false;

-- RIF provisionales (los de la farmacia y el CrossFit están por confirmar)
insert into empresas (tipo, nombre, razon_social, rif, domicilio, telefono) values
  ('farmacia',    'Azullab Farmacia',    'Azullab Farmacia, C.A.',          'J-00000001-0', 'La Azulita, municipio Andrés Bello, estado Mérida', null),
  ('laboratorio', 'Azullab Laboratorio', 'Grupo Empresarial Azullab, C.A.', 'J-50134578-3', 'La Azulita, municipio Andrés Bello, estado Mérida', '0424-7535017 / 0424-7723883'),
  ('crossfit',    'Azullab CrossFit',    'Fitness Lab Evolution, C.A.',     'J-00000002-0', 'La Azulita, municipio Andrés Bello, estado Mérida', null)
on conflict (rif) do nothing;

-- ---------- Usuario nuevo: su perfil, y el primero es el dueño ----------
create or replace function nuevo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into perfiles (user_id, nombre)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'nombre', ''), split_part(new.email, '@', 1)))
  on conflict (user_id) do nothing;
  if not exists (select 1 from miembros where rol = 'dueno') then
    insert into miembros (user_id, empresa_id, rol)
    select new.id, id, 'dueno' from empresas on conflict do nothing;
  end if;
  return new;
end $$;

drop trigger if exists nuevo_usuario on auth.users;
create trigger nuevo_usuario after insert on auth.users
  for each row execute function nuevo_usuario();

-- Si el usuario se creó antes de correr esta migración
insert into perfiles (user_id, nombre)
select id, split_part(email, '@', 1) from auth.users on conflict (user_id) do nothing;
insert into miembros (user_id, empresa_id, rol)
select u.id, e.id, 'dueno'
from (select id from auth.users order by created_at limit 1) u cross join empresas e
where not exists (select 1 from miembros where rol = 'dueno')
on conflict do nothing;

-- ---------- Quién soy en este negocio ----------
create or replace function mi_acceso(p_tipo tipo_negocio)
returns table (empresa_id uuid, empresa text, rol rol_usuario, nombre text, caja text, datos_confirmados boolean)
language sql stable security definer set search_path = public as $$
  select e.id, e.nombre, m.rol, p.nombre, m.caja, e.datos_confirmados
  from miembros m
  join empresas e on e.id = m.empresa_id
  join perfiles p on p.user_id = m.user_id
  where m.user_id = auth.uid() and m.activo and e.activo and e.tipo = p_tipo
  limit 1
$$;
revoke all on function mi_acceso(tipo_negocio) from public, anon;
grant execute on function mi_acceso(tipo_negocio) to authenticated;

-- ---------- Sin datos fiscales confirmados no se factura ----------
create or replace function exigir_datos_fiscales() returns trigger
language plpgsql security definer set search_path = public as $$
declare e empresas;
begin
  select * into e from empresas where id = new.empresa_id;
  if not e.datos_confirmados then
    raise exception 'Faltan los datos fiscales de %: el dueño debe confirmarlos en Configuración antes de facturar', e.nombre;
  end if;
  return new;
end $$;

drop trigger if exists exigir_datos_fiscales on documentos;
create trigger exigir_datos_fiscales before insert on documentos
  for each row execute function exigir_datos_fiscales();
