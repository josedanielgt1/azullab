-- =====================================================================
-- Cuadre · Migración 0004: farmacia (catálogo, lotes, inventario y venta)
--
-- Reglas que hace cumplir la base:
--   * Un código de barras no puede estar en dos productos del mismo negocio.
--   * La existencia vive en los lotes y solo cambia con vender(),
--     recibir_compra() o salida_inventario(): nadie la escribe a mano.
--   * Cada cambio de existencia deja un movimiento que no se edita ni se borra.
--   * No se vende lo que no hay, ni de lotes vencidos, ni a otro precio
--     que el del producto o el de su lote.
--   * La venta, la factura y el descuento de los lotes ocurren juntos:
--     si algo falla, no queda nada a medias.
-- =====================================================================

create table productos (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references empresas,
  codigo           text,
  codigos_alt      text[] not null default '{}',
  nombre           text not null check (trim(nombre) <> ''),
  principio_activo text,
  laboratorio      text,
  presentacion     text,
  seccion          text,
  iva              alicuota_iva not null default 'E',
  costo            numeric(14,4) not null default 0 check (costo >= 0),
  margen           numeric(7,2)  not null default 30,
  precio           numeric(14,2) not null default 0 check (precio >= 0),   -- en dólares
  pmvp             numeric(14,2),
  por_lote         boolean not null default false,   -- lotes con precios distintos
  minimo           int not null default 5,
  rx               boolean not null default false,
  controlado       boolean not null default false,
  activo           boolean not null default true,
  historial        jsonb not null default '[]',
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);
create index on productos (empresa_id, nombre);

create table lotes (
  id          bigint generated always as identity primary key,
  empresa_id  uuid not null references empresas,
  producto_id bigint not null references productos on delete cascade,
  lote        text not null,
  vence       date not null,
  cantidad    numeric(12,3) not null default 0 check (cantidad >= 0),
  costo       numeric(14,4) not null default 0,
  precio      numeric(14,2),                      -- precio propio del lote (si difiere)
  creado_en   timestamptz not null default now(),
  unique (producto_id, lote, vence)
);
create index on lotes (producto_id, vence);

create table movimientos (
  id           bigint generated always as identity primary key,
  empresa_id   uuid not null references empresas,
  producto_id  bigint not null references productos,
  lote_id      bigint references lotes,
  tipo         text not null check (tipo in ('compra','venta','devolucion','salida','ajuste')),
  cantidad     numeric(12,3) not null,            -- + entra, − sale
  costo        numeric(14,4),
  documento_id uuid references documentos,
  motivo       text,
  referencia   text,                              -- proveedor y factura, etc.
  usuario      uuid default auth.uid(),
  fecha        timestamptz not null default now()
);
create index on movimientos (empresa_id, fecha);
create index on movimientos (producto_id, fecha);

-- ---------- Códigos únicos por negocio ----------
create or replace function productos_codigos() returns trigger
language plpgsql as $$
declare c text[]; otro text;
begin
  new.codigo := nullif(nullif(trim(new.codigo), ''), '—');
  new.codigos_alt := array(select distinct trim(x) from unnest(new.codigos_alt) x where trim(x) not in ('', '—'));
  c := array_remove(array[new.codigo] || new.codigos_alt, null);
  if array_length(c, 1) is not null then
    select nombre into otro from productos
    where empresa_id = new.empresa_id and id <> coalesce(new.id, -1)
      and array_remove(array[codigo] || codigos_alt, null) && c limit 1;
    if otro is not null then raise exception 'Uno de los códigos ya está en %. Un código no puede quedar en dos productos', otro; end if;
  end if;
  new.actualizado_en := now();
  return new;
end $$;
create trigger productos_codigos before insert or update on productos
  for each row execute function productos_codigos();

-- Los lotes solo se crean o cambian de cantidad por las funciones de abajo
create or replace function lotes_cantidad() returns trigger
language plpgsql as $$
begin
  if current_setting('cuadre.inventario', true) is distinct from 'si'
     and (tg_op = 'INSERT' or new.cantidad <> old.cantidad or new.producto_id <> old.producto_id) then
    raise exception 'La existencia solo cambia con una venta, una compra o una salida de inventario';
  end if;
  return new;
end $$;
create trigger lotes_cantidad before insert or update on lotes
  for each row execute function lotes_cantidad();

create or replace function movimientos_fijos() returns trigger
language plpgsql as $$
begin raise exception 'Los movimientos de inventario no se editan ni se borran: haz un ajuste'; end $$;
create trigger movimientos_fijos before update or delete on movimientos
  for each row execute function movimientos_fijos();

-- ---------- Vender: factura + descuento de lotes (primero el que vence antes) ----------
-- p_items: [{"producto_id", "cantidad", "precio_usd"}]   (un renglón por precio)
create or replace function vender(p_empresa uuid, p_cliente jsonb, p_items jsonb, p_pagos jsonb default '[]')
returns documentos
language plpgsql security definer set search_path = public as $$
declare
  it jsonb; pr productos; lt lotes; d documentos;
  lineas jsonb := '[]'; resta numeric; toma numeric; pu numeric; ok boolean;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,regente,cajero}') then raise exception 'Tu usuario no vende'; end if;
  if jsonb_array_length(coalesce(p_items, '[]')) = 0 then raise exception 'La venta no tiene productos'; end if;

  for it in select * from jsonb_array_elements(p_items) loop
    select * into pr from productos where id = (it->>'producto_id')::bigint and empresa_id = p_empresa and activo;
    if pr.id is null then raise exception 'Producto no encontrado'; end if;
    pu := (it->>'precio_usd')::numeric;
    select abs(pu - pr.precio) < 0.005 or exists (
             select 1 from lotes where producto_id = pr.id and cantidad > 0 and precio is not null and abs(pu - precio) < 0.005)
      into ok;
    if not ok then raise exception 'El precio de % cambió. Actualiza la caja', pr.nombre; end if;
    lineas := lineas || jsonb_build_object('descripcion', pr.nombre || coalesce(' · ' || nullif(pr.presentacion, '—'), ''),
                                           'cantidad', (it->>'cantidad')::numeric, 'precio_usd', pu, 'alicuota', pr.iva,
                                           'ref', jsonb_build_object('producto_id', pr.id));
  end loop;

  d := emitir_documento(p_empresa, 'FAC', p_cliente, lineas, p_pagos, null, null, 'sistema', null, 'venta', null);

  perform set_config('cuadre.inventario', 'si', true);
  for it in select * from jsonb_array_elements(p_items) loop
    resta := (it->>'cantidad')::numeric;
    for lt in select * from lotes where producto_id = (it->>'producto_id')::bigint and cantidad > 0 and vence >= current_date
              order by vence, id for update loop
      exit when resta <= 0;
      toma := least(lt.cantidad, resta);
      update lotes set cantidad = cantidad - toma where id = lt.id;
      insert into movimientos (empresa_id, producto_id, lote_id, tipo, cantidad, costo, documento_id)
      values (p_empresa, lt.producto_id, lt.id, 'venta', -toma, lt.costo, d.id);
      resta := resta - toma;
    end loop;
    if resta > 0 then
      raise exception 'No hay existencia suficiente de % (faltan %)',
        (select nombre from productos where id = (it->>'producto_id')::bigint), resta;
    end if;
  end loop;
  perform set_config('cuadre.inventario', '', true);
  return d;
end $$;

-- ---------- Recibir compra: entran los lotes ----------
-- p_items: [{"producto_id", "lote", "vence", "cantidad", "costo"}]
create or replace function recibir_compra(p_empresa uuid, p_items jsonb, p_referencia text default null)
returns setof lotes
language plpgsql security definer set search_path = public as $$
declare it jsonb; lt lotes;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,regente,almacen}') then raise exception 'Tu usuario no recibe compras'; end if;
  perform set_config('cuadre.inventario', 'si', true);
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]')) loop
    if not exists (select 1 from productos where id = (it->>'producto_id')::bigint and empresa_id = p_empresa) then
      raise exception 'Producto no encontrado';
    end if;
    if coalesce((it->>'cantidad')::numeric, 0) <= 0 or coalesce(trim(it->>'lote'), '') = '' or (it->>'vence') is null then
      raise exception 'Cada producto necesita lote, vencimiento y cantidad';
    end if;
    insert into lotes (empresa_id, producto_id, lote, vence, cantidad, costo)
    values (p_empresa, (it->>'producto_id')::bigint, upper(trim(it->>'lote')), (it->>'vence')::date,
            (it->>'cantidad')::numeric, coalesce((it->>'costo')::numeric, 0))
    on conflict (producto_id, lote, vence) do update set cantidad = lotes.cantidad + excluded.cantidad, costo = excluded.costo
    returning * into lt;
    insert into movimientos (empresa_id, producto_id, lote_id, tipo, cantidad, costo, referencia)
    values (p_empresa, lt.producto_id, lt.id, 'compra', (it->>'cantidad')::numeric, lt.costo, p_referencia);
    return next lt;
  end loop;
  perform set_config('cuadre.inventario', '', true);
end $$;

-- ---------- Salida de inventario (vencido, dañado, uso interno…) o ajuste ----------
create or replace function salida_inventario(p_lote bigint, p_cantidad numeric, p_motivo text, p_tipo text default 'salida')
returns lotes
language plpgsql security definer set search_path = public as $$
declare lt lotes;
begin
  select * into lt from lotes where id = p_lote for update;
  if lt.id is null or not tiene_rol(lt.empresa_id, '{dueno,gerente,regente,almacen}') then raise exception 'Lote no encontrado'; end if;
  if p_tipo not in ('salida', 'ajuste') then raise exception 'Tipo inválido'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Escribe el motivo de la salida'; end if;
  if p_tipo = 'salida' and (p_cantidad <= 0 or p_cantidad > lt.cantidad) then
    raise exception 'La salida debe ser entre 1 y % (lo que hay en el lote)', lt.cantidad;
  end if;
  if p_tipo = 'ajuste' and not tiene_rol(lt.empresa_id, '{dueno,gerente}') then raise exception 'Solo el dueño ajusta el inventario'; end if;
  perform set_config('cuadre.inventario', 'si', true);
  -- salida: p_cantidad sale; ajuste: p_cantidad es la cantidad contada (nueva existencia del lote)
  insert into movimientos (empresa_id, producto_id, lote_id, tipo, cantidad, costo, motivo)
  values (lt.empresa_id, lt.producto_id, lt.id, p_tipo,
          case when p_tipo = 'salida' then -p_cantidad else p_cantidad - lt.cantidad end, lt.costo, p_motivo);
  update lotes set cantidad = case when p_tipo = 'salida' then cantidad - p_cantidad else p_cantidad end
    where id = lt.id returning * into lt;
  perform set_config('cuadre.inventario', '', true);
  return lt;
end $$;

-- ---------- Permisos ----------
alter table productos   enable row level security;
alter table lotes       enable row level security;
alter table movimientos enable row level security;

create policy ver on productos for select using (es_miembro(empresa_id));
create policy crear on productos for insert with check (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'));
create policy editar on productos for update using (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'))
  with check (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'));
create policy ver on lotes for select using (es_miembro(empresa_id));
-- De un lote solo se cambia a mano su costo y su precio (al recibir con otro costo)
create policy precio on lotes for update using (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'))
  with check (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'));
create policy ver on movimientos for select using (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'));

revoke insert, update, delete on lotes, movimientos from anon, authenticated;
grant update (costo, precio) on lotes to authenticated;
revoke delete on productos from anon, authenticated;
revoke all on function vender(uuid, jsonb, jsonb, jsonb) from public, anon;
revoke all on function recibir_compra(uuid, jsonb, text) from public, anon;
revoke all on function salida_inventario(bigint, numeric, text, text) from public, anon;
grant execute on function vender(uuid, jsonb, jsonb, jsonb), recibir_compra(uuid, jsonb, text),
  salida_inventario(bigint, numeric, text, text) to authenticated;

create trigger auditar after insert or update on productos for each row execute function auditar();
