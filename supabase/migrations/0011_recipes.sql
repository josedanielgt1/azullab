-- =====================================================================
-- Cuadre · Migración 0011: récipes y libro de controlados (farmacia)
--
-- Ley Orgánica de Drogas (arts. 62 a 69), según recipes/04:
--   * Los controlados solo salen con récipe especial, numerado y sin
--     repetir; solo el regente (o el dueño) registra récipes.
--   * La venta de un controlado exige un récipe especial registrado de ese
--     paciente, y no se vende más de lo que el récipe autoriza.
--   * El libro de controlados se llena solo con cada movimiento real del
--     inventario (compra, venta, salida, devolución, ajuste) y no se edita.
--   * El libro oficial sigue siendo el de papel sellado: este lo cuadra
--     con el inventario y deja listo lo que se copia.
-- =====================================================================

alter table medicos add column if not exists mpps text;
alter table medicos add column if not exists especialidad text;

create table recipes (
  id              bigint generated always as identity primary key,
  empresa_id      uuid not null references empresas,
  numero          bigint not null,                 -- número interno (RX-000215)
  fecha           timestamptz not null default now(),
  paciente_ci     text not null,
  paciente        text not null,
  medico          text,
  mpps            text,
  tipo            text not null check (tipo in ('medico', 'antibiotico', 'especial')),
  numero_especial text,
  producto_id     bigint references productos,
  producto        text not null,
  recetado        numeric(10,2) not null check (recetado > 0),
  despachado      numeric(10,2) not null default 0 check (despachado >= 0 and despachado <= recetado),
  vendido         numeric(10,2) not null default 0,
  unidad          text,
  cronico         boolean not null default false,
  original        text,
  datos           jsonb not null default '{}',
  creado_por      uuid default auth.uid(),
  unique (empresa_id, numero),
  check (tipo <> 'especial' or coalesce(numero_especial, '') <> '')
);
create unique index recipes_especial on recipes (empresa_id, numero_especial) where tipo = 'especial';

create table libro_controlados (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references empresas,
  fecha       timestamptz not null default now(),
  producto_id bigint not null references productos,
  producto    text not null,
  concepto    text not null,
  origen      text,          -- médico (con su MPPS) o droguería
  paciente_ci text,
  lote        text,
  entrada     numeric(12,3) not null default 0,
  salida      numeric(12,3) not null default 0,
  recipe_id   bigint references recipes,
  movimiento_id bigint references movimientos,
  usuario     uuid default auth.uid()
);
create index on libro_controlados (empresa_id, producto_id, fecha);

-- Número interno del récipe
create or replace function recipes_numero() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not tiene_rol(new.empresa_id, '{dueno,gerente,regente}') then raise exception 'Solo el regente registra récipes'; end if;
  new.numero := contar(new.empresa_id, 'recipe');
  new.paciente_ci := upper(regexp_replace(new.paciente_ci, '[.\s]', '', 'g'));
  if new.paciente_ci ~ '^[VEJGP][0-9]' then new.paciente_ci := substr(new.paciente_ci, 1, 1) || '-' || substr(new.paciente_ci, 2); end if;
  new.vendido := 0;
  return new;
end $$;
create trigger recipes_numero before insert on recipes for each row execute function recipes_numero();

-- Cada movimiento de un controlado va al libro; la venta exige récipe especial
create or replace function libro_por_movimiento() returns trigger
language plpgsql security definer set search_path = public as $$
declare pr productos; lt lotes; d documentos; rx recipes; ci text; concepto text; origen text;
begin
  select * into pr from productos where id = new.producto_id;
  if not pr.controlado then return new; end if;
  select * into lt from lotes where id = new.lote_id;
  if new.tipo = 'venta' then
    select * into d from documentos where id = new.documento_id;
    ci := upper(regexp_replace(regexp_replace(d.cliente_rif, '[.\s]', '', 'g'), '^([VEJGP])-?', '\1-'));
    select * into rx from recipes
      where empresa_id = new.empresa_id and tipo = 'especial' and producto_id = new.producto_id and paciente_ci = ci
        and vendido - new.cantidad <= despachado and fecha > now() - interval '30 days'
      order by fecha limit 1 for update;
    if rx.id is null then
      raise exception '% es controlado: registra primero el récipe especial de este paciente (cédula %), o no alcanza lo que autoriza', pr.nombre, ci;
    end if;
    update recipes set vendido = vendido - new.cantidad where id = rx.id;
    concepto := 'Récipe especial N° ' || rx.numero_especial || ' · factura ' || lpad(d.numero::text, 8, '0');
    origen := coalesce(rx.medico, '') || coalesce(' · MPPS ' || rx.mpps, '');
  elsif new.tipo = 'compra' then concepto := 'Compra' || coalesce(' · ' || new.referencia, ''); origen := 'Droguería';
  elsif new.tipo = 'devolucion' then concepto := 'Devolución' || coalesce(' · ' || new.motivo, '');
  else concepto := initcap(new.tipo) || coalesce(': ' || new.motivo, '');
  end if;
  insert into libro_controlados (empresa_id, fecha, producto_id, producto, concepto, origen, paciente_ci, lote, entrada, salida, recipe_id, movimiento_id, usuario)
  values (new.empresa_id, new.fecha, pr.id, pr.nombre, concepto, origen, ci, lt.lote,
          greatest(new.cantidad, 0), greatest(-new.cantidad, 0), rx.id, new.id, new.usuario);
  return new;
end $$;
create trigger libro_por_movimiento after insert on movimientos for each row execute function libro_por_movimiento();

create or replace function libro_fijo() returns trigger
language plpgsql as $$ begin raise exception 'El libro de controlados no se edita ni se borra'; end $$;
create trigger libro_fijo before update or delete on libro_controlados for each row execute function libro_fijo();

-- ---------- Permisos: datos de salud, solo regente y dueño ----------
alter table recipes           enable row level security;
alter table libro_controlados enable row level security;
create policy ver on recipes for select using (tiene_rol(empresa_id, '{dueno,gerente,regente}'));
create policy crear on recipes for insert with check (tiene_rol(empresa_id, '{dueno,gerente,regente}'));
create policy editar on recipes for update using (tiene_rol(empresa_id, '{dueno,gerente,regente}')) with check (tiene_rol(empresa_id, '{dueno,gerente,regente}'));
create policy ver on libro_controlados for select using (tiene_rol(empresa_id, '{dueno,gerente,regente}'));
revoke delete on recipes from anon, authenticated;
revoke insert, update, delete on libro_controlados from anon, authenticated;
-- el número, lo vendido y el producto de un récipe no se cambian a mano
revoke update on recipes from authenticated;
grant update (original, cronico, datos) on recipes to authenticated;
