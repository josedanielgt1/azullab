-- =====================================================================
-- Cuadre · Migración 0008: CrossFit (planes, socios, cobros, clases y pizarra)
--
-- Reglas que hace cumplir la base:
--   * El cobro de una membresía crea su factura (IVA 16 %) y corre la
--     fecha de vencimiento del socio en una sola operación.
--   * Si la membresía está vencida, la nueva cuenta desde hoy; si no,
--     desde su vencimiento (no se pierden días pagados).
--   * Una cédula por socio; la entrada a clase se marca una vez por clase y día.
-- =====================================================================

create table planes (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  nombre     text not null check (trim(nombre) <> ''),
  precio     numeric(12,2) not null check (precio >= 0),   -- en dólares, sin IVA
  dias       int not null check (dias > 0),
  activo     boolean not null default true
);

create table productos_box (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  nombre     text not null check (trim(nombre) <> ''),
  precio     numeric(12,2) not null check (precio >= 0),
  activo     boolean not null default true
);

create table socios (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references empresas,
  cedula      text not null,
  nombre      text not null check (trim(nombre) <> ''),
  telefono    text,
  plan_id     bigint references planes,
  vence       date,
  nacimiento  date,
  nivel       text,
  datos       jsonb not null default '{}',     -- emergencia, lesiones…
  creado_en   timestamptz not null default now()
);
create unique index socios_cedula on socios (empresa_id, upper(regexp_replace(cedula, '[.\s-]', '', 'g')));

create table membresias (
  id           bigint generated always as identity primary key,
  empresa_id   uuid not null references empresas,
  socio_id     bigint not null references socios,
  plan_id      bigint not null references planes,
  desde        date not null,
  hasta        date not null,
  vence_antes  date,
  precio_usd   numeric(12,2) not null,
  metodo       text,
  documento_id uuid references documentos,
  creado_por   uuid default auth.uid(),
  creado_en    timestamptz not null default now()
);
create index on membresias (empresa_id, creado_en);

create table clases (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  hora       text not null,
  coach      text,
  cupo       int not null default 14,
  activo     boolean not null default true,
  unique (empresa_id, hora)
);

create table asistencias (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  socio_id   bigint not null references socios,
  fecha      date not null default current_date,
  clase      text not null,
  hora       text,
  unique (socio_id, fecha, clase)
);

-- La pizarra del día: rutina, si está publicada, reservas y resultados
create table pizarras (
  empresa_id  uuid not null references empresas,
  fecha       date not null,
  wod         jsonb not null default '{}',
  publicada   boolean not null default false,
  reservas    jsonb not null default '{}',      -- {"06:00": [socio_id…]}
  resultados  jsonb not null default '[]',
  actualizado timestamptz not null default now(),
  primary key (empresa_id, fecha)
);

-- ---------- Cobrar una membresía ----------
-- p_producto: {"id", "cantidad"} opcional
create or replace function cobrar_membresia(p_empresa uuid, p_socio bigint, p_plan bigint, p_metodo text, p_divisa boolean default false,
                                            p_producto jsonb default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare so socios; pl planes; pr productos_box; desde date; lineas jsonb; d documentos; m membresias; t numeric; tot numeric;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,atencion}') then raise exception 'Tu usuario no cobra'; end if;
  select * into so from socios where id = p_socio and empresa_id = p_empresa for update;
  select * into pl from planes where id = p_plan and empresa_id = p_empresa and activo;
  if so.id is null or pl.id is null then raise exception 'Socio o plan no encontrado'; end if;
  desde := greatest(coalesce(so.vence, current_date), current_date);
  lineas := jsonb_build_array(jsonb_build_object('descripcion', pl.nombre || ' · desde el ' || to_char(desde, 'DD-MM-YYYY'),
                                                 'cantidad', 1, 'precio_usd', pl.precio, 'alicuota', 'G', 'ref', jsonb_build_object('plan_id', pl.id)));
  if p_producto is not null and p_producto->>'id' is not null then
    select * into pr from productos_box where id = (p_producto->>'id')::bigint and empresa_id = p_empresa and activo;
    if pr.id is null then raise exception 'Producto no encontrado'; end if;
    lineas := lineas || jsonb_build_object('descripcion', pr.nombre, 'cantidad', coalesce((p_producto->>'cantidad')::numeric, 1),
                                           'precio_usd', pr.precio, 'alicuota', 'G', 'ref', jsonb_build_object('producto_box_id', pr.id));
  end if;
  -- Para el pago: el total con IVA a la tasa del día
  t := tasa_del_dia(current_date);
  if t is null then raise exception 'No hay tasa BCV cargada'; end if;
  select sum(round(round((l->>'precio_usd')::numeric * t, 2) * (l->>'cantidad')::numeric, 2)) into tot from jsonb_array_elements(lineas) l;
  tot := tot + round(tot * (select iva_general from empresas where id = p_empresa) / 100, 2);
  d := emitir_documento(p_empresa, 'FAC', jsonb_build_object('rif', so.cedula, 'nombre', so.nombre, 'tel', so.telefono), lineas,
                        jsonb_build_array(jsonb_build_object('metodo', p_metodo, 'monto_bs', tot, 'divisa', coalesce(p_divisa, false))),
                        null, null, 'sistema', null, 'membresia', null);
  insert into membresias (empresa_id, socio_id, plan_id, desde, hasta, vence_antes, precio_usd, metodo, documento_id)
  values (p_empresa, so.id, pl.id, desde, desde + pl.dias, so.vence, pl.precio, p_metodo, d.id) returning * into m;
  update socios set plan_id = pl.id, vence = m.hasta where id = so.id returning * into so;
  return jsonb_build_object('membresia', to_jsonb(m), 'documento', to_jsonb(d), 'socio', to_jsonb(so));
end $$;
revoke all on function cobrar_membresia(uuid, bigint, bigint, text, boolean, jsonb) from public, anon;
grant execute on function cobrar_membresia(uuid, bigint, bigint, text, boolean, jsonb) to authenticated;

-- El vencimiento solo lo corre un cobro (o el dueño a mano, que queda en la auditoría)
create or replace function socios_vence() returns trigger
language plpgsql as $$
begin
  if new.vence is distinct from old.vence and pg_trigger_depth() = 1 and not tiene_rol(new.empresa_id, '{dueno,gerente}')
     and current_user not in ('postgres', 'supabase_admin') then
    raise exception 'El vencimiento cambia con un cobro';
  end if;
  return new;
end $$;
create trigger socios_vence before update on socios for each row execute function socios_vence();

-- ---------- Permisos ----------
alter table planes        enable row level security;
alter table productos_box enable row level security;
alter table socios        enable row level security;
alter table membresias    enable row level security;
alter table clases        enable row level security;
alter table asistencias   enable row level security;
alter table pizarras      enable row level security;

create policy ver on planes for select using (es_miembro(empresa_id));
create policy dueno on planes for all using (tiene_rol(empresa_id, '{dueno,gerente}')) with check (tiene_rol(empresa_id, '{dueno,gerente}'));
create policy ver on productos_box for select using (es_miembro(empresa_id));
create policy dueno on productos_box for all using (tiene_rol(empresa_id, '{dueno,gerente}')) with check (tiene_rol(empresa_id, '{dueno,gerente}'));
create policy ver on socios for select using (es_miembro(empresa_id));
create policy crear on socios for insert with check (tiene_rol(empresa_id, '{dueno,gerente,atencion,coach}'));
create policy editar on socios for update using (tiene_rol(empresa_id, '{dueno,gerente,atencion,coach}')) with check (tiene_rol(empresa_id, '{dueno,gerente,atencion,coach}'));
create policy ver on membresias for select using (tiene_rol(empresa_id, '{dueno,gerente,atencion}'));
create policy ver on clases for select using (es_miembro(empresa_id));
create policy dueno on clases for all using (tiene_rol(empresa_id, '{dueno,gerente,coach}')) with check (tiene_rol(empresa_id, '{dueno,gerente,coach}'));
create policy ver on asistencias for select using (es_miembro(empresa_id));
create policy marcar on asistencias for insert with check (es_miembro(empresa_id));
create policy ver on pizarras for select using (es_miembro(empresa_id));
create policy escribir on pizarras for insert with check (tiene_rol(empresa_id, '{dueno,gerente,coach}'));
create policy editar on pizarras for update using (es_miembro(empresa_id)) with check (es_miembro(empresa_id));

revoke delete on socios, membresias, asistencias from anon, authenticated;
revoke insert, update on membresias from anon, authenticated;

create trigger auditar after insert or update on socios     for each row execute function auditar();
create trigger auditar after insert                    on membresias for each row execute function auditar();
create trigger auditar after insert or update on planes     for each row execute function auditar();
