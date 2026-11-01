-- =====================================================================
-- Cuadre · Migración 0012: alertas de pacientes (alergias e interacciones)
--   * Las registra y las ve completas el regente (o el dueño).
--   * La caja solo puede preguntar qué principios activos no se le deben
--     vender a una cédula, sin ver el motivo (datos de salud).
-- =====================================================================
create table alertas_pacientes (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  cedula     text not null,
  texto      text not null check (trim(texto) <> ''),
  principios text[] not null default '{}',
  activo     boolean not null default true,
  creado_por uuid default auth.uid(),
  creado_en  timestamptz not null default now()
);
create index on alertas_pacientes (empresa_id, cedula);

create or replace function alertas_normalizar() returns trigger
language plpgsql as $$
begin
  new.cedula := upper(regexp_replace(new.cedula, '[.\s]', '', 'g'));
  if new.cedula ~ '^[VEJGP][0-9]' then new.cedula := substr(new.cedula, 1, 1) || '-' || substr(new.cedula, 2); end if;
  new.principios := array(select distinct lower(trim(x)) from unnest(new.principios) x where trim(x) <> '');
  return new;
end $$;
create trigger alertas_normalizar before insert or update on alertas_pacientes for each row execute function alertas_normalizar();

create or replace function alerta_principios(p_empresa uuid, p_cedula text) returns text[]
language sql stable security definer set search_path = public as $$
  select case when es_miembro(p_empresa) then coalesce(array_agg(distinct x), '{}') else '{}' end
  from alertas_pacientes a, unnest(a.principios) x
  where a.empresa_id = p_empresa and a.activo
    and a.cedula = (select case when c ~ '^[VEJGP][0-9]' then substr(c, 1, 1) || '-' || substr(c, 2) else c end
                    from (select upper(regexp_replace(p_cedula, '[.\s]', '', 'g')) c) z)
$$;
revoke all on function alerta_principios(uuid, text) from public, anon;
grant execute on function alerta_principios(uuid, text) to authenticated;

alter table alertas_pacientes enable row level security;
create policy ver on alertas_pacientes for select using (tiene_rol(empresa_id, '{dueno,gerente,regente}'));
create policy crear on alertas_pacientes for insert with check (tiene_rol(empresa_id, '{dueno,gerente,regente}'));
create policy editar on alertas_pacientes for update using (tiene_rol(empresa_id, '{dueno,gerente,regente}')) with check (tiene_rol(empresa_id, '{dueno,gerente,regente}'));
revoke delete on alertas_pacientes from anon, authenticated;
create trigger auditar after insert or update on alertas_pacientes for each row execute function auditar();
