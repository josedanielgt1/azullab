-- =====================================================================
-- Cuadre · Migración 0005: clientes (farmacia; sirve a cualquier negocio)
--   * Un cliente por cédula o RIF en cada negocio.
--   * Cada venta le suma una visita, el total y los puntos (1 por dólar).
-- =====================================================================
create table clientes (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  cedula_rif text not null,
  nombre     text not null check (trim(nombre) <> ''),
  telefono   text,
  correo     text,
  direccion  text,
  visitas    int not null default 0,
  total_usd  numeric(14,2) not null default 0,
  puntos     int not null default 0,
  ultima     date,
  creado_en  timestamptz not null default now(),
  unique (empresa_id, cedula_rif)
);

-- Cédula o RIF siempre igual: V-12345678, J-12345678-9 (sin puntos)
create or replace function clientes_normalizar() returns trigger
language plpgsql as $$
begin
  new.cedula_rif := upper(regexp_replace(new.cedula_rif, '[.\s]', '', 'g'));
  if new.cedula_rif ~ '^[VEJGP][0-9]' then new.cedula_rif := substr(new.cedula_rif, 1, 1) || '-' || substr(new.cedula_rif, 2); end if;
  if new.cedula_rif !~ '^[VEJGP]-[0-9]{5,9}(-[0-9])?$' then raise exception 'Cédula o RIF inválido: %', new.cedula_rif; end if;
  return new;
end $$;
create trigger clientes_normalizar before insert or update of cedula_rif on clientes
  for each row execute function clientes_normalizar();

alter table clientes enable row level security;
create policy ver on clientes for select using (es_miembro(empresa_id));
create policy crear on clientes for insert with check (es_miembro(empresa_id));
create policy editar on clientes for update using (es_miembro(empresa_id)) with check (es_miembro(empresa_id));
revoke delete on clientes from anon, authenticated;

-- La venta le suma al cliente (si está registrado)
create or replace function clientes_por_venta() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.tipo = 'FAC' then
    update clientes set visitas = visitas + 1, total_usd = total_usd + new.total_usd,
                        puntos = puntos + floor(new.total_usd)::int, ultima = new.fecha::date
    where empresa_id = new.empresa_id
      and cedula_rif = upper(regexp_replace(regexp_replace(new.cliente_rif, '[.\s]', '', 'g'), '^([VEJGP])-?', '\1-'));
  end if;
  return new;
end $$;
create trigger clientes_por_venta after insert on documentos
  for each row execute function clientes_por_venta();
