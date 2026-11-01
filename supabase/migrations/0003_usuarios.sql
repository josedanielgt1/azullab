-- =====================================================================
-- Cuadre · Migración 0003: el equipo de cada negocio
--   * equipo(): el dueño y el gerente ven quién tiene acceso, con su
--     correo y su última entrada.
--   * dar_acceso(): da acceso por correo a alguien que ya tiene usuario
--     (por ejemplo, el regente de la farmacia que también cubre el
--     laboratorio). Los usuarios nuevos los crea la función "usuarios"
--     (supabase/functions/usuarios), que necesita la clave secreta.
--   * Nadie se quita a sí mismo el rol de dueño ni deja un negocio sin dueño.
-- =====================================================================

create or replace function equipo(p_empresa uuid)
returns table (user_id uuid, nombre text, correo text, rol rol_usuario, caja text, activo boolean, ultima_entrada timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not tiene_rol(p_empresa, '{dueno,gerente}') then raise exception 'Solo el dueño o el gerente ven el equipo'; end if;
  return query
    select m.user_id, p.nombre, u.email::text, m.rol, m.caja, m.activo, u.last_sign_in_at
    from miembros m join perfiles p on p.user_id = m.user_id join auth.users u on u.id = m.user_id
    where m.empresa_id = p_empresa
    order by m.rol = 'dueno' desc, m.activo desc, p.nombre;
end $$;
revoke all on function equipo(uuid) from public, anon;
grant execute on function equipo(uuid) to authenticated;

create or replace function dar_acceso(p_empresa uuid, p_correo text, p_rol rol_usuario, p_caja text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente}') then raise exception 'Solo el dueño o el gerente dan acceso'; end if;
  if p_rol = 'dueno' and not tiene_rol(p_empresa, '{dueno}') then raise exception 'Solo el dueño nombra a otro dueño'; end if;
  select id into u from auth.users where lower(email) = lower(trim(p_correo));
  if u is null then raise exception 'No hay ningún usuario con el correo %. Créalo con «Nuevo usuario»', p_correo; end if;
  insert into perfiles (user_id, nombre) values (u, split_part(p_correo, '@', 1)) on conflict do nothing;
  insert into miembros (user_id, empresa_id, rol, caja, activo) values (u, p_empresa, p_rol, p_caja, true)
  on conflict (user_id, empresa_id) do update set rol = excluded.rol, caja = excluded.caja, activo = true;
end $$;
revoke all on function dar_acceso(uuid, text, rol_usuario, text) from public, anon;
grant execute on function dar_acceso(uuid, text, rol_usuario, text) to authenticated;

-- El nombre de cada persona lo puede corregir el dueño
create policy dueno_edita on perfiles for update
  using (exists (select 1 from miembros a join miembros b on a.empresa_id = b.empresa_id
                 where a.user_id = auth.uid() and a.rol = 'dueno' and a.activo and b.user_id = perfiles.user_id))
  with check (true);

-- Un negocio nunca se queda sin dueño activo
create or replace function cuidar_dueno() returns trigger
language plpgsql as $$
begin
  if old.rol = 'dueno' and old.activo and (tg_op = 'DELETE' or new.rol <> 'dueno' or not new.activo)
     and not exists (select 1 from miembros where empresa_id = old.empresa_id and rol = 'dueno' and activo and user_id <> old.user_id) then
    raise exception 'El negocio no puede quedarse sin dueño';
  end if;
  return coalesce(new, old);
end $$;
create trigger cuidar_dueno before update or delete on miembros
  for each row execute function cuidar_dueno();

-- Quién puede usar la función "usuarios" (la llama con el token de quien la usa)
create or replace function puedo_crear_usuarios(p_empresa uuid, p_rol rol_usuario) returns boolean
language sql stable as $$
  select tiene_rol(p_empresa, '{dueno,gerente}') and (p_rol <> 'dueno' or tiene_rol(p_empresa, '{dueno}'))
$$;
grant execute on function puedo_crear_usuarios(uuid, rol_usuario) to authenticated;

-- ---------- Datos fiscales que la pantalla Configuración también guarda ----------
alter table empresas add column if not exists talonario_num text;
alter table empresas add column if not exists contador text;
