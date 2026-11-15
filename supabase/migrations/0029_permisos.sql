-- =====================================================================
-- Cuadre · Migración 0029: permisos por rol que decide el dueño
--
-- En «Usuarios» el dueño marca, rol por rol, qué partes del sistema abre
-- cada persona (caja, compras, libros, ganancias...). Se guarda en la
-- lista «permisos» de colecciones, una por negocio:
--     {"regente": ["caja", "compras", ...], "cajero": ["caja"], ...}
-- El rol que no aparece usa lo de siempre.
--
--   1. Solo el dueño cambia «permisos» (el gerente sigue cambiando las
--      demás listas de configuración). Todos los del negocio la leen.
--   2. El dueño tiene el control total: «permisos» no lleva al dueño y
--      cada rol es una lista de nombres.
--
-- La base sigue poniendo su propio límite por rol (un cajero nunca recibe
-- compras ni ve ganancias aunque se marque): la pantalla solo ofrece lo
-- que la base deja hacer a cada rol.
-- =====================================================================

-- ---------- 1. Quién escribe la lista «permisos» ----------
drop policy if exists escribir on colecciones;
drop policy if exists editar on colecciones;
create policy escribir on colecciones for insert with check (
  (nombre <> 'permisos' and tiene_rol(empresa_id, '{dueno,gerente}'))
  or (nombre = 'permisos' and tiene_rol(empresa_id, '{dueno}'))
  or (nombre like 'equipo\_%' and es_miembro(empresa_id) and not es_socio(empresa_id)));
create policy editar on colecciones for update using (
  (nombre <> 'permisos' and tiene_rol(empresa_id, '{dueno,gerente}'))
  or (nombre = 'permisos' and tiene_rol(empresa_id, '{dueno}'))
  or (nombre like 'equipo\_%' and es_miembro(empresa_id) and not es_socio(empresa_id)))
  with check (
  (nombre <> 'permisos' and tiene_rol(empresa_id, '{dueno,gerente}'))
  or (nombre = 'permisos' and tiene_rol(empresa_id, '{dueno}'))
  or (nombre like 'equipo\_%' and es_miembro(empresa_id) and not es_socio(empresa_id)));

-- ---------- 2. Forma de la lista ----------
create or replace function colecciones_permisos() returns trigger
language plpgsql set search_path = public as $$
declare k text; v jsonb;
begin
  if new.nombre <> 'permisos' then return new; end if;
  if jsonb_typeof(new.datos) <> 'object' then raise exception 'Los permisos van por rol'; end if;
  for k, v in select * from jsonb_each(new.datos) loop
    if k = 'dueno' then raise exception 'El dueño tiene todos los permisos: no se le quitan'; end if;
    if k not in ('gerente', 'regente', 'cajero', 'almacen', 'atencion', 'bioanalista', 'toma_muestras', 'coach') then
      raise exception 'Rol desconocido en los permisos: %', k; end if;
    if jsonb_typeof(v) <> 'array' or exists (select 1 from jsonb_array_elements(v) x where jsonb_typeof(x) <> 'string') then
      raise exception 'Los permisos de % van como una lista de nombres', k; end if;
  end loop;
  return new;
end $$;
drop trigger if exists permisos_forma on colecciones;
create trigger permisos_forma before insert or update on colecciones for each row execute function colecciones_permisos();
