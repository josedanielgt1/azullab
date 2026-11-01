-- Cuadre · Para pegar en el SQL Editor de Supabase (proyecto azullab) y darle Run una vez.
-- Migraciones desde la 0017. Generado por supabase/armar_sql_editor.sh; no editar a mano.

-- >>>>> migrations/0017_seguridad.sql
-- =====================================================================
-- Cuadre · Migración 0017: limpieza de seguridad (avisos del asesor de Supabase)
--   * Las funciones de trigger no se llaman por la API: nadie las ejecuta
--     directo (los triggers siguen funcionando igual).
--   * Sin sesión no se ejecuta ninguna función, salvo las que usan las
--     reglas de acceso (es_miembro, tiene_rol, ...), que sin sesión dan
--     falso o vacío.
--   * Las funciones con sesión conservan el permiso que tenían.
--   * Toda función de public fija dónde busca las tablas (search_path).
-- No cambia cómo funcionan los sistemas.
-- =====================================================================
do $$
declare
  f record;
  firma text;
  en_reglas boolean;
  con_sesion boolean;
begin
  for f in
    select p.oid, p.proname, p.prorettype = 'trigger'::regtype as es_trigger, p.proconfig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')  -- no tocar extensiones
  loop
    firma := f.oid::regprocedure::text;

    -- Dónde busca las tablas
    if not exists (select 1 from unnest(coalesce(f.proconfig, '{}')) c where c like 'search_path=%') then
      execute format('alter function %s set search_path = public, extensions', firma);
    end if;

    if f.es_trigger then
      execute format('revoke execute on function %s from public, anon, authenticated', firma);
      continue;
    end if;

    -- ¿La usa alguna regla de acceso? Entonces debe poder evaluarse siempre.
    select exists (
      select 1 from pg_policies
      where schemaname = 'public'
        and (coalesce(qual, '') ~ ('\m' || f.proname || '\(') or coalesce(with_check, '') ~ ('\m' || f.proname || '\('))
    ) into en_reglas;
    if en_reglas then continue; end if;

    con_sesion := has_function_privilege('authenticated', f.oid, 'execute');
    execute format('revoke execute on function %s from public, anon', firma);
    if con_sesion then
      execute format('grant execute on function %s to authenticated', firma);
    end if;
  end loop;
end $$;

-- >>>>> Historial de migraciones
insert into supabase_migrations.schema_migrations (version, name) values
  ('0017', 'seguridad')
on conflict (version) do nothing;
select 'Listo: migraciones aplicadas' as resultado;
