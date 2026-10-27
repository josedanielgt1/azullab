-- =====================================================================
-- Cuadre · Récipes, pacientes y libro de controlados
-- Migración para Supabase (Postgres 15 o superior)
-- Azullab Farmacia · 27-10-2026
--
-- Reglas que hace cumplir la base de datos (no solo la pantalla):
--   * Los datos de salud los ven solo el regente y el dueño.
--     El cajero no ve pacientes ni récipes; solo puede preguntar
--     "¿este cliente tiene una alerta con este principio activo?" (sí o no).
--   * Solo el regente registra récipes y despacha.
--   * No se despacha más de lo recetado y un récipe especial no se usa dos veces.
--   * El libro de controlados y los despachos no se editan ni se borran:
--     las correcciones son renglones nuevos de "ajuste" con su nota.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tipos ----------
do $$ begin
  create type rol_usuario as enum ('dueno','regente','cajero','almacen');
exception when duplicate_object then null; end $$;
create type tipo_recipe    as enum ('medico','antibiotico','especial');
create type estado_recipe  as enum ('abierto','parcial','completo','anulado','rechazado');
create type mov_controlado as enum ('existencia_inicial','compra','dispensacion','devolucion','vencido','ajuste');

-- ---------- Perfiles (si Cuadre ya la tiene, omitir este bloque) ----------
create table if not exists perfiles (
  user_id     uuid primary key references auth.users on delete cascade,
  farmacia_id uuid not null,
  nombre      text not null,
  rol         rol_usuario not null,
  activo      boolean not null default true
);
alter table perfiles enable row level security;
create policy perfiles_propio on perfiles for select using (user_id = auth.uid());

-- ---------- Funciones de permisos ----------
create or replace function mi_rol() returns rol_usuario
language sql stable security definer set search_path = public as $$
  select rol from perfiles where user_id = auth.uid() and activo
$$;

create or replace function mi_farmacia() returns uuid
language sql stable security definer set search_path = public as $$
  select farmacia_id from perfiles where user_id = auth.uid() and activo
$$;

-- Ve datos de salud: regente y dueño
create or replace function ve_salud() returns boolean
language sql stable as $$ select coalesce(mi_rol() in ('dueno','regente'), false) $$;

create or replace function es_regente() returns boolean
language sql stable as $$ select coalesce(mi_rol() = 'regente', false) $$;

-- ---------- Médicos ----------
create table medicos (
  id           uuid primary key default gen_random_uuid(),
  farmacia_id  uuid not null default mi_farmacia(),
  nombre       text not null,
  cedula       text,
  mpps         text not null,          -- matrícula sanitaria
  colegio      text,                   -- número del colegio de médicos
  especialidad text,
  telefono     text,
  direccion    text,                   -- la pide el récipe especial
  created_at   timestamptz not null default now(),
  unique (farmacia_id, mpps)
);

-- ---------- Pacientes ----------
create table pacientes (
  id                   uuid primary key default gen_random_uuid(),
  farmacia_id          uuid not null default mi_farmacia(),
  cedula               text not null,
  nombre               text not null,
  fecha_nacimiento     date,
  telefono             text,
  direccion            text,           -- la pide el récipe especial
  cliente_id           uuid,           -- enlace con clientes y Azul Puntos
  acepta_recordatorios boolean not null default false,  -- consentimiento para WhatsApp
  created_at           timestamptz not null default now(),
  unique (farmacia_id, cedula)
);

create table paciente_alertas (
  id                uuid primary key default gen_random_uuid(),
  paciente_id       uuid not null references pacientes on delete cascade,
  tipo              text not null check (tipo in ('alergia','interaccion','otra')),
  descripcion       text not null,
  principios_activos text[] not null default '{}',   -- p. ej. {amoxicilina,ampicilina,penicilina}
  registrado_por    uuid not null default auth.uid(),
  created_at        timestamptz not null default now()
);

create table tratamientos (
  id                 uuid primary key default gen_random_uuid(),
  paciente_id        uuid not null references pacientes on delete cascade,
  producto_id        uuid,
  descripcion        text not null,                  -- "Losartán 50 mg, 1 al día"
  unidades_por_dia   numeric(6,2) not null check (unidades_por_dia > 0),
  ultima_compra      date,
  unidades_compradas numeric(10,2),
  activo             boolean not null default true
);

-- ---------- Récipes ----------
create table recipes (
  id               uuid primary key default gen_random_uuid(),
  farmacia_id      uuid not null default mi_farmacia(),
  numero           bigint generated always as identity,   -- se muestra como RX-000214
  tipo             tipo_recipe not null,
  numero_especial  text,                -- número del récipe especial (talonario oficial)
  medico_id        uuid not null references medicos,
  paciente_id      uuid not null references pacientes,
  comprador_cedula text,                -- Ley de Drogas: identificación de quien compra
  comprador_nombre text,
  fecha_emision    date not null,
  foto_path        text,                -- Storage: recipes/<farmacia>/<id>.jpg
  original         text not null default 'archivado'
                   check (original in ('archivado','devuelto_sellado')),
  cronico          boolean not null default false,
  estado           estado_recipe not null default 'abierto',
  motivo           text,                -- por qué se rechazó o anuló
  registrado_por   uuid not null default auth.uid(),
  created_at       timestamptz not null default now(),
  check (tipo <> 'especial' or numero_especial is not null),
  check (estado not in ('anulado','rechazado') or motivo is not null)
);
-- Un récipe especial no se despacha dos veces
create unique index recipes_especial_unico
  on recipes (medico_id, numero_especial) where numero_especial is not null;
create index recipes_paciente on recipes (paciente_id, created_at desc);

create table recipe_items (
  id                uuid primary key default gen_random_uuid(),
  recipe_id         uuid not null references recipes on delete cascade,
  producto_id       uuid,                       -- productos.id de Cuadre
  descripcion       text not null,              -- principio activo, concentración y forma
  posologia         text,
  cantidad_recetada numeric(10,2) not null check (cantidad_recetada > 0),
  unidad            text not null default 'unidades',
  controlado        boolean not null default false,
  check (not controlado or producto_id is not null)
);

create table dispensaciones (
  id             uuid primary key default gen_random_uuid(),
  recipe_item_id uuid not null references recipe_items,
  venta_id       uuid,                          -- la factura con la que salió
  lote           text,
  cantidad       numeric(10,2) not null check (cantidad > 0),
  despachado_por uuid not null default auth.uid(),
  created_at     timestamptz not null default now()
);

-- ---------- Libro especial de controlados ----------
create table libro_controlados (
  id             bigint generated always as identity primary key,
  farmacia_id    uuid not null default mi_farmacia(),
  producto_id    uuid not null,
  fecha          timestamptz not null default now(),
  movimiento     mov_controlado not null,
  documento      text not null,                 -- factura de compra o récipe especial N°
  recipe_id      uuid references recipes,
  lote           text,
  entrada        numeric(10,2) not null default 0 check (entrada >= 0),
  salida         numeric(10,2) not null default 0 check (salida >= 0),
  nota           text,
  registrado_por uuid not null default auth.uid(),
  check ((entrada > 0) <> (salida > 0)),
  check (movimiento <> 'ajuste' or nota is not null)
);
create index libro_producto on libro_controlados (farmacia_id, producto_id, fecha, id);

-- Registro de quién abrió una ficha de paciente
create table accesos_salud (
  id          bigint generated always as identity primary key,
  user_id     uuid not null default auth.uid(),
  paciente_id uuid not null references pacientes,
  created_at  timestamptz not null default now()
);

-- ---------- Reglas de despacho ----------
create or replace function antes_de_despachar() returns trigger
language plpgsql security definer set search_path = public as $$
declare it recipe_items; r recipes; ya numeric;
begin
  -- bloquea el renglón para que dos cajas no despachen a la vez
  select * into it from recipe_items where id = new.recipe_item_id for update;
  select * into r  from recipes      where id = it.recipe_id;
  if r.farmacia_id <> mi_farmacia() then
    raise exception 'El récipe no es de esta farmacia';
  end if;
  if mi_rol() is distinct from 'regente' then
    raise exception 'Solo el farmacéutico regente despacha récipes';
  end if;
  if r.estado in ('completo','anulado','rechazado') then
    raise exception 'El récipe RX-% está %', lpad(r.numero::text, 6, '0'), r.estado;
  end if;
  select coalesce(sum(cantidad), 0) into ya from dispensaciones where recipe_item_id = it.id;
  if ya + new.cantidad > it.cantidad_recetada then
    raise exception 'No se puede despachar más de lo recetado: % de %', ya + new.cantidad, it.cantidad_recetada;
  end if;
  return new;
end $$;
create trigger t_antes_despachar before insert on dispensaciones
  for each row execute function antes_de_despachar();

create or replace function despues_de_despachar() returns trigger
language plpgsql security definer set search_path = public as $$
declare it recipe_items; r recipes; faltan int;
begin
  select * into it from recipe_items where id = new.recipe_item_id;
  select * into r  from recipes      where id = it.recipe_id;
  if it.controlado then
    insert into libro_controlados (farmacia_id, producto_id, movimiento, documento, recipe_id, lote, salida, registrado_por)
    values (r.farmacia_id, it.producto_id, 'dispensacion',
            'Récipe especial N° ' || coalesce(r.numero_especial, 'RX-' || lpad(r.numero::text, 6, '0')),
            r.id, new.lote, new.cantidad, new.despachado_por);
  end if;
  select count(*) into faltan from recipe_items i
   where i.recipe_id = r.id
     and i.cantidad_recetada > (select coalesce(sum(d.cantidad), 0) from dispensaciones d where d.recipe_item_id = i.id);
  update recipes set estado = case when faltan = 0 then 'completo' else 'parcial' end::estado_recipe
   where id = r.id;
  return new;
end $$;
create trigger t_despues_despachar after insert on dispensaciones
  for each row execute function despues_de_despachar();

-- El libro y los despachos solo crecen
create or replace function solo_agregar() returns trigger language plpgsql as $$
begin
  raise exception 'Este registro no se edita ni se borra: agrega un ajuste con su nota';
end $$;
create trigger t_libro_fijo before update or delete on libro_controlados
  for each row execute function solo_agregar();
create trigger t_despachos_fijos before update or delete on dispensaciones
  for each row execute function solo_agregar();

-- ---------- Vistas ----------
-- Existencia corrida, renglón por renglón, como en el libro sellado
create view libro_controlados_saldo with (security_invoker = true) as
select l.*,
       sum(l.entrada - l.salida) over (partition by l.farmacia_id, l.producto_id order by l.fecha, l.id) as existencia
from libro_controlados l;

-- Resumen del mes para el Ministerio (primeros 10 días del mes siguiente)
create view resumen_mensual_controlados with (security_invoker = true) as
select farmacia_id, producto_id, date_trunc('month', fecha)::date as mes,
       sum(entrada) as entradas, sum(salida) as salidas,
       count(*) filter (where movimiento = 'dispensacion') as recipes_despachados
from libro_controlados group by 1, 2, 3;

-- A quién avisar por WhatsApp (3 días antes de que se le acabe)
create view proximos_recordatorios with (security_invoker = true) as
select t.id, t.paciente_id, p.nombre, p.telefono, t.descripcion,
       t.ultima_compra + floor(t.unidades_compradas / t.unidades_por_dia)::int     as se_acaba,
       t.ultima_compra + floor(t.unidades_compradas / t.unidades_por_dia)::int - 3 as avisar_el
from tratamientos t join pacientes p on p.id = t.paciente_id
where t.activo and p.acepta_recordatorios and t.ultima_compra is not null;

-- ---------- Funciones para la caja y la ficha ----------
-- La caja pregunta si hay alerta; no ve cuál es
create or replace function alerta_venta(p_cedula text, p_principio text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from paciente_alertas a join pacientes p on p.id = a.paciente_id
     where p.farmacia_id = mi_farmacia()
       and p.cedula = p_cedula
       and lower(p_principio) = any (select lower(x) from unnest(a.principios_activos) x)
  )
$$;

-- Abrir la ficha deja constancia de quién la vio
create or replace function ver_ficha(p_paciente uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare res jsonb;
begin
  if not ve_salud() then
    raise exception 'Tu usuario no puede ver datos de salud';
  end if;
  select jsonb_build_object(
           'paciente',     to_jsonb(p),
           'alertas',      coalesce((select jsonb_agg(a) from paciente_alertas a where a.paciente_id = p.id), '[]'),
           'tratamientos', coalesce((select jsonb_agg(t) from tratamientos t where t.paciente_id = p.id and t.activo), '[]'),
           'recipes',      coalesce((select jsonb_agg(r order by r.created_at desc) from recipes r where r.paciente_id = p.id), '[]'))
    into res
    from pacientes p where p.id = p_paciente and p.farmacia_id = mi_farmacia();
  if res is not null then
    insert into accesos_salud (paciente_id) values (p_paciente);
  end if;
  return res;
end $$;

-- ---------- Seguridad por filas (RLS) ----------
alter table medicos            enable row level security;
alter table pacientes          enable row level security;
alter table paciente_alertas   enable row level security;
alter table tratamientos       enable row level security;
alter table recipes            enable row level security;
alter table recipe_items       enable row level security;
alter table dispensaciones     enable row level security;
alter table libro_controlados  enable row level security;
alter table accesos_salud      enable row level security;

-- Médicos y pacientes: ven regente y dueño; crea y edita el regente
create policy medicos_ver    on medicos   for select using (farmacia_id = mi_farmacia() and ve_salud());
create policy medicos_crear  on medicos   for insert with check (farmacia_id = mi_farmacia() and es_regente());
create policy medicos_editar on medicos   for update using (farmacia_id = mi_farmacia() and es_regente())
                                                   with check (farmacia_id = mi_farmacia());
create policy pacientes_ver    on pacientes for select using (farmacia_id = mi_farmacia() and ve_salud());
create policy pacientes_crear  on pacientes for insert with check (farmacia_id = mi_farmacia() and es_regente());
create policy pacientes_editar on pacientes for update using (farmacia_id = mi_farmacia() and es_regente())
                                                     with check (farmacia_id = mi_farmacia());

-- Alertas y tratamientos cuelgan del paciente
create policy alertas_ver on paciente_alertas for select using (ve_salud() and exists
  (select 1 from pacientes p where p.id = paciente_id and p.farmacia_id = mi_farmacia()));
create policy alertas_crear on paciente_alertas for insert with check (es_regente() and exists
  (select 1 from pacientes p where p.id = paciente_id and p.farmacia_id = mi_farmacia()));
create policy tratamientos_ver on tratamientos for select using (ve_salud() and exists
  (select 1 from pacientes p where p.id = paciente_id and p.farmacia_id = mi_farmacia()));
create policy tratamientos_crear on tratamientos for insert with check (es_regente() and exists
  (select 1 from pacientes p where p.id = paciente_id and p.farmacia_id = mi_farmacia()));
create policy tratamientos_editar on tratamientos for update using (es_regente() and exists
  (select 1 from pacientes p where p.id = paciente_id and p.farmacia_id = mi_farmacia()));

-- Récipes: ven regente y dueño; registra el regente; el estado lo cambia el regente
create policy recipes_ver    on recipes for select using (farmacia_id = mi_farmacia() and ve_salud());
create policy recipes_crear  on recipes for insert with check (farmacia_id = mi_farmacia() and es_regente());
create policy recipes_editar on recipes for update using (farmacia_id = mi_farmacia() and es_regente())
                                                 with check (farmacia_id = mi_farmacia());
create policy items_ver on recipe_items for select using (ve_salud() and exists
  (select 1 from recipes r where r.id = recipe_id and r.farmacia_id = mi_farmacia()));
create policy items_crear on recipe_items for insert with check (es_regente() and exists
  (select 1 from recipes r where r.id = recipe_id and r.farmacia_id = mi_farmacia() and r.estado = 'abierto'));
create policy despachos_ver on dispensaciones for select using (ve_salud() and exists
  (select 1 from recipe_items i join recipes r on r.id = i.recipe_id
    where i.id = recipe_item_id and r.farmacia_id = mi_farmacia()));
create policy despachos_crear on dispensaciones for insert with check (es_regente());

-- Libro de controlados: lo ven regente y dueño; escribe solo el regente (o el despacho)
create policy libro_ver   on libro_controlados for select using (farmacia_id = mi_farmacia() and ve_salud());
create policy libro_crear on libro_controlados for insert with check (farmacia_id = mi_farmacia() and es_regente());

-- Accesos: solo el dueño revisa quién abrió cada ficha
create policy accesos_ver on accesos_salud for select using (mi_rol() = 'dueno' and exists
  (select 1 from pacientes p where p.id = paciente_id and p.farmacia_id = mi_farmacia()));

-- La caja (cualquier usuario activo) puede preguntar por alertas
revoke all on function alerta_venta(text, text) from public;
grant execute on function alerta_venta(text, text) to authenticated;
revoke all on function ver_ficha(uuid) from public;
grant execute on function ver_ficha(uuid) to authenticated;

-- ---------- Fotos de los récipes (Storage privado) ----------
insert into storage.buckets (id, name, public) values ('recipes', 'recipes', false)
  on conflict (id) do nothing;
create policy "recipes: ver fotos" on storage.objects for select
  using (bucket_id = 'recipes' and ve_salud() and (storage.foldername(name))[1] = mi_farmacia()::text);
create policy "recipes: subir fotos" on storage.objects for insert
  with check (bucket_id = 'recipes' and es_regente() and (storage.foldername(name))[1] = mi_farmacia()::text);
