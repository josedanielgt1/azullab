-- Cuadre · Para pegar en el SQL Editor de Supabase (proyecto azullab) y darle Run una vez.
-- Migraciones desde la 0003. Generado por supabase/armar_sql_editor.sh; no editar a mano.

-- >>>>> migrations/0003_usuarios.sql
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

-- >>>>> migrations/0004_farmacia.sql
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

-- >>>>> migrations/0005_clientes.sql
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

-- >>>>> migrations/0006_notas.sql
-- =====================================================================
-- Cuadre · Migración 0006: notas de crédito y débito desde la pantalla
--   * emitir_nota(): la nota cita su factura y toma de ella al cliente.
--   * Si es una devolución, lo devuelto vuelve a los lotes de los que salió
--     en esa venta (nunca más de lo vendido menos lo ya devuelto).
--   * Quién emite notas en cada negocio, como en las maquetas.
-- =====================================================================

-- p_lineas: [{"descripcion","cantidad","precio_bs","alicuota","ref":{"producto_id"}}]
create or replace function emitir_nota(p_factura uuid, p_tipo tipo_doc, p_lineas jsonb, p_motivo text, p_reintegrar boolean default false)
returns documentos
language plpgsql security definer set search_path = public as $$
declare f documentos; d documentos; l jsonb; m record; resta numeric; vendida numeric; devuelta numeric; toma numeric;
begin
  if p_tipo = 'FAC' then raise exception 'Usa vender() para facturar'; end if;
  select * into f from documentos where id = p_factura and tipo = 'FAC';
  if f.id is null or not es_miembro(f.empresa_id) then raise exception 'Factura no encontrada'; end if;
  d := emitir_documento(f.empresa_id, p_tipo, jsonb_build_object('rif', f.cliente_rif, 'nombre', f.cliente_nombre, 'dir', f.cliente_dir, 'tel', f.cliente_tel),
                        p_lineas, '[]', f.id, p_motivo);
  if p_tipo = 'NC' and p_reintegrar then
    perform set_config('cuadre.inventario', 'si', true);
    for l in select * from jsonb_array_elements(p_lineas) loop
      continue when l->'ref'->>'producto_id' is null;
      resta := (l->>'cantidad')::numeric;
      select coalesce(-sum(cantidad), 0) into vendida from movimientos
        where documento_id = f.id and producto_id = (l->'ref'->>'producto_id')::bigint and tipo = 'venta';
      select coalesce(sum(mv.cantidad), 0) into devuelta from movimientos mv join documentos n on n.id = mv.documento_id
        where n.afecta_id = f.id and mv.producto_id = (l->'ref'->>'producto_id')::bigint and mv.tipo = 'devolucion';
      if resta > vendida - devuelta then
        raise exception 'Se devuelven % y de esa venta quedan % por devolver', resta::float, (vendida - devuelta)::float;
      end if;
      -- A los lotes de esa venta, empezando por el último que se tomó
      for m in select lote_id, -sum(cantidad) q from movimientos
               where documento_id = f.id and producto_id = (l->'ref'->>'producto_id')::bigint and tipo = 'venta'
               group by lote_id order by max(id) desc loop
        exit when resta <= 0;
        toma := least(m.q, resta);
        update lotes set cantidad = cantidad + toma where id = m.lote_id;
        insert into movimientos (empresa_id, producto_id, lote_id, tipo, cantidad, costo, documento_id, motivo)
        select f.empresa_id, producto_id, id, 'devolucion', toma, costo, d.id, p_motivo from lotes where id = m.lote_id;
        resta := resta - toma;
      end loop;
    end loop;
    perform set_config('cuadre.inventario', '', true);
  end if;
  return d;
end $$;
revoke all on function emitir_nota(uuid, tipo_doc, jsonb, text, boolean) from public, anon;
grant execute on function emitir_nota(uuid, tipo_doc, jsonb, text, boolean) to authenticated;

update empresas set roles_notas = '{dueno,gerente,regente}'  where tipo = 'farmacia';
update empresas set roles_notas = '{dueno,gerente,atencion}' where tipo = 'laboratorio';

-- >>>>> migrations/0007_laboratorio.sql
-- =====================================================================
-- Cuadre · Migración 0007: laboratorio (pacientes, exámenes, órdenes)
--
-- Reglas que hace cumplir la base:
--   * La orden y su factura se crean juntas (crear_orden), con los precios
--     del catálogo y un número de orden correlativo (L-0001…).
--   * Lo cobrado (exámenes, paciente, total, factura) no se cambia después.
--   * Solo el bioanalista (o el dueño) valida; un resultado validado ya no
--     se cambia; una orden solo se anula con su nota de crédito.
--   * Las órdenes y los pacientes no se borran.
-- =====================================================================

create table pacientes (
  id             bigint generated always as identity primary key,
  empresa_id     uuid not null references empresas,
  cedula         text,
  nombre         text not null check (trim(nombre) <> ''),
  sexo           text check (sexo in ('M', 'F')),
  nacimiento     date,
  telefono       text,
  datos          jsonb not null default '{}',     -- ficha completa: antecedentes, seguro, sangre…
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);
create unique index pacientes_cedula on pacientes (empresa_id, upper(regexp_replace(cedula, '[.\s-]', '', 'g')))
  where coalesce(cedula, '') not in ('', '—');

create table examenes (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  codigo     text not null,
  nombre     text not null,
  area       text,
  tubo       text,
  tiempo     text,
  precio     numeric(12,2) not null default 0 check (precio >= 0),
  parametros jsonb not null default '[]',        -- [{k, n, u, r, crit, d}]
  activo     boolean not null default true,
  unique (empresa_id, codigo)
);

create table perfiles_lab (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  codigo     text not null,
  nombre     text not null,
  examenes   text[] not null default '{}',
  precio     numeric(12,2) not null default 0 check (precio >= 0),
  activo     boolean not null default true,
  unique (empresa_id, codigo)
);

create table medicos (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  nombre     text not null,
  activo     boolean not null default true,
  unique (empresa_id, nombre)
);

-- Contadores por negocio (número de orden y otros que no son fiscales)
create table contadores (
  empresa_id uuid not null references empresas,
  clave      text not null,
  siguiente  bigint not null default 1,
  primary key (empresa_id, clave)
);
create or replace function contar(e uuid, k text) returns bigint
language plpgsql security definer set search_path = public as $$
declare n bigint;
begin
  insert into contadores (empresa_id, clave) values (e, k) on conflict do nothing;
  update contadores set siguiente = siguiente + 1 where empresa_id = e and clave = k returning siguiente - 1 into n;
  return n;
end $$;
revoke all on function contar(uuid, text) from public, anon, authenticated;

create table ordenes (
  id           bigint generated always as identity primary key,
  empresa_id   uuid not null references empresas,
  numero       text not null,
  paciente_id  bigint not null references pacientes,
  items        jsonb not null,                   -- [{k:'ex'|'perf', c, precio}]
  total_usd    numeric(12,2) not null,
  medico       text,
  urgente      boolean not null default false,
  visita       jsonb not null default '{}',      -- datos de la visita: ayuno, origen…
  estado       text not null default 'Por tomar'
               check (estado in ('Por tomar', 'En proceso', 'Por validar', 'Validado', 'Entregado', 'Anulada')),
  datos        jsonb not null default '{}',      -- toma, resultados, validación, entrega, avisos
  documento_id uuid references documentos,
  creado_por   uuid default auth.uid(),
  creado_en    timestamptz not null default now(),
  unique (empresa_id, numero)
);
create index on ordenes (empresa_id, creado_en);
create index on ordenes (paciente_id);

-- ---------- Crear la orden con su factura ----------
-- p_items: [{"k":"ex"|"perf","c":"HEM"}]   p_pagos: como en emitir_documento
create or replace function crear_orden(p_empresa uuid, p_paciente bigint, p_items jsonb, p_medico text default null,
                                       p_urgente boolean default false, p_visita jsonb default '{}', p_pagos jsonb default '[]')
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  pa pacientes; it jsonb; nom text; pr numeric; lineas jsonb := '[]'; items jsonb := '[]'; tot numeric := 0;
  d documentos; o ordenes;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,atencion}') then raise exception 'Tu usuario no crea órdenes'; end if;
  select * into pa from pacientes where id = p_paciente and empresa_id = p_empresa;
  if pa.id is null then raise exception 'Paciente no encontrado'; end if;
  if jsonb_array_length(coalesce(p_items, '[]')) = 0 then raise exception 'La orden no tiene exámenes'; end if;
  for it in select * from jsonb_array_elements(p_items) loop
    if it->>'k' = 'perf' then
      select case when nombre ~* '^perfil' then nombre else 'Perfil ' || nombre end, precio into nom, pr
        from perfiles_lab where empresa_id = p_empresa and codigo = it->>'c' and activo;
    else
      select nombre, precio into nom, pr from examenes where empresa_id = p_empresa and codigo = it->>'c' and activo;
    end if;
    if nom is null then raise exception 'El examen o perfil % no está en el catálogo', it->>'c'; end if;
    lineas := lineas || jsonb_build_object('descripcion', nom, 'cantidad', 1, 'precio_usd', pr, 'alicuota', 'E', 'ref', jsonb_build_object('c', it->>'c'));
    items := items || jsonb_build_object('k', it->>'k', 'c', it->>'c', 'precio', pr);
    tot := tot + pr; nom := null;
  end loop;

  insert into ordenes (empresa_id, numero, paciente_id, items, total_usd, medico, urgente, visita)
  values (p_empresa, 'L-' || lpad(contar(p_empresa, 'orden')::text, 4, '0'), pa.id, items, tot, nullif(p_medico, ''), coalesce(p_urgente, false), coalesce(p_visita, '{}'))
  returning * into o;
  d := emitir_documento(p_empresa, 'FAC', jsonb_build_object('rif', coalesce(nullif(pa.cedula, ''), 'V-00000000'), 'nombre', pa.nombre, 'tel', pa.telefono),
                        lineas, p_pagos, null, null, 'sistema', null, 'orden', null);
  perform set_config('cuadre.orden', 'si', true);
  update ordenes set documento_id = d.id where id = o.id returning * into o;
  perform set_config('cuadre.orden', '', true);
  return jsonb_build_object('orden', to_jsonb(o), 'documento', to_jsonb(d));
end $$;
revoke all on function crear_orden(uuid, bigint, jsonb, text, boolean, jsonb, jsonb) from public, anon;
grant execute on function crear_orden(uuid, bigint, jsonb, text, boolean, jsonb, jsonb) to authenticated;

-- ---------- Reglas de la orden después de creada ----------
create or replace function ordenes_reglas() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.items, new.paciente_id, new.total_usd, new.numero, new.empresa_id) is distinct from (old.items, old.paciente_id, old.total_usd, old.numero, old.empresa_id)
     or (new.documento_id is distinct from old.documento_id and current_setting('cuadre.orden', true) is distinct from 'si') then
    raise exception 'Lo cobrado en una orden no se cambia: anúlala con una nota de crédito';
  end if;
  if old.estado in ('Validado', 'Entregado') and (new.datos->'res') is distinct from (old.datos->'res') then
    raise exception 'Un resultado validado ya no se cambia';
  end if;
  if new.estado = 'Validado' and old.estado <> 'Validado' and not tiene_rol(new.empresa_id, '{dueno,gerente,bioanalista}') then
    raise exception 'Solo el bioanalista valida resultados';
  end if;
  if (new.datos->'res') is distinct from (old.datos->'res') and not tiene_rol(new.empresa_id, '{dueno,gerente,bioanalista}') then
    raise exception 'Solo el bioanalista carga resultados';
  end if;
  if new.estado = 'Anulada' and old.estado <> 'Anulada'
     and not exists (select 1 from documentos where afecta_id = old.documento_id and tipo = 'NC') then
    raise exception 'Una orden solo se anula con su nota de crédito';
  end if;
  if old.estado = 'Anulada' and new.estado <> 'Anulada' then raise exception 'Una orden anulada no se reabre'; end if;
  return new;
end $$;
create trigger ordenes_reglas before update on ordenes for each row execute function ordenes_reglas();

create or replace function pacientes_fecha() returns trigger language plpgsql as $$
begin new.actualizado_en := now(); return new; end $$;
create trigger pacientes_fecha before update on pacientes for each row execute function pacientes_fecha();

-- ---------- Permisos ----------
alter table pacientes    enable row level security;
alter table examenes     enable row level security;
alter table perfiles_lab enable row level security;
alter table medicos      enable row level security;
alter table ordenes      enable row level security;
alter table contadores   enable row level security;

create policy ver on pacientes for select using (es_miembro(empresa_id));
create policy crear on pacientes for insert with check (tiene_rol(empresa_id, '{dueno,gerente,atencion}'));
create policy editar on pacientes for update using (tiene_rol(empresa_id, '{dueno,gerente,atencion}')) with check (tiene_rol(empresa_id, '{dueno,gerente,atencion}'));

create policy ver on examenes for select using (es_miembro(empresa_id));
create policy crear on examenes for insert with check (tiene_rol(empresa_id, '{dueno,gerente,bioanalista}'));
create policy editar on examenes for update using (tiene_rol(empresa_id, '{dueno,gerente,bioanalista}')) with check (tiene_rol(empresa_id, '{dueno,gerente,bioanalista}'));
create policy ver on perfiles_lab for select using (es_miembro(empresa_id));
create policy crear on perfiles_lab for insert with check (tiene_rol(empresa_id, '{dueno,gerente}'));
create policy editar on perfiles_lab for update using (tiene_rol(empresa_id, '{dueno,gerente}')) with check (tiene_rol(empresa_id, '{dueno,gerente}'));
create policy ver on medicos for select using (es_miembro(empresa_id));
create policy crear on medicos for insert with check (es_miembro(empresa_id));
create policy editar on medicos for update using (tiene_rol(empresa_id, '{dueno,gerente}')) with check (tiene_rol(empresa_id, '{dueno,gerente}'));

create policy ver on ordenes for select using (es_miembro(empresa_id));
create policy avanzar on ordenes for update using (es_miembro(empresa_id)) with check (es_miembro(empresa_id));

revoke delete on pacientes, examenes, perfiles_lab, medicos, ordenes from anon, authenticated;
revoke insert on ordenes, contadores from anon, authenticated;
revoke update, delete on contadores from anon, authenticated;

create trigger auditar after insert or update on ordenes   for each row execute function auditar();
create trigger auditar after insert or update on examenes  for each row execute function auditar();
create trigger auditar after insert or update on pacientes for each row execute function auditar();

-- >>>>> migrations/0008_crossfit.sql
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

-- >>>>> migrations/0009_compras_gastos.sql
-- =====================================================================
-- Cuadre · Migración 0009: proveedores, compras (libro de compras y
-- cuentas por pagar), gastos y configuración guardada
--
--   * recibir_factura(): la factura del proveedor queda en el libro de
--     compras (exento y gravable según el IVA de cada producto) y sus
--     lotes entran al inventario, todo junto.
--   * Una factura de proveedor no se registra dos veces.
--   * pagar_compra(): abonos a la factura; nunca más de lo que se debe.
--   * Gastos: se anulan, no se borran.
--   * colecciones: listas de configuración de cada negocio (secciones,
--     ganancias por defecto, cuentas bancarias…).
-- =====================================================================

create table proveedores (
  id           bigint generated always as identity primary key,
  empresa_id   uuid not null references empresas,
  nombre       text not null check (trim(nombre) <> ''),
  rif          text check (rif is null or rif ~ '^[JGVEP]-[0-9]{8}-[0-9]$'),
  credito_dias int not null default 15,
  telefono     text,
  activo       boolean not null default true
);
create unique index proveedores_nombre on proveedores (empresa_id, lower(nombre));

create table compras (
  id            bigint generated always as identity primary key,
  empresa_id    uuid not null references empresas,
  proveedor_id  bigint references proveedores,
  proveedor     text not null,
  rif           text,
  tipo          tipo_doc not null default 'FAC',
  numero        text not null,
  control       text,
  fecha         date not null,
  tasa          numeric(14,4) not null,
  exento_usd    numeric(14,2) not null default 0,
  gravable_usd  numeric(14,2) not null default 0,
  iva_usd       numeric(14,2) not null default 0,
  total_usd     numeric(14,2) not null default 0,
  vence         date,
  pagado_usd    numeric(14,2) not null default 0 check (pagado_usd >= 0),
  creado_por    uuid default auth.uid(),
  creado_en     timestamptz not null default now(),
  unique (empresa_id, proveedor, numero, tipo)
);
create index on compras (empresa_id, fecha);

create table pagos_compras (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  compra_id  bigint not null references compras,
  fecha      date not null default current_date,
  monto_usd  numeric(14,2) not null check (monto_usd > 0),
  metodo     text,
  usuario    uuid default auth.uid(),
  creado_en  timestamptz not null default now()
);

-- p_factura: {"proveedor_id", "numero", "control", "fecha"}
-- p_items:   como recibir_compra
create or replace function recibir_factura(p_empresa uuid, p_factura jsonb, p_items jsonb)
returns compras
language plpgsql security definer set search_path = public as $$
declare pv proveedores; c compras; t numeric; ex numeric := 0; gr numeric := 0; it jsonb; iv alicuota_iva; m numeric;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,regente,almacen}') then raise exception 'Tu usuario no recibe compras'; end if;
  select * into pv from proveedores where id = (p_factura->>'proveedor_id')::bigint and empresa_id = p_empresa;
  if pv.id is null then raise exception 'Escoge la droguería'; end if;
  if coalesce(trim(p_factura->>'numero'), '') = '' then raise exception 'Escribe el número de la factura del proveedor'; end if;
  t := tasa_del_dia(coalesce((p_factura->>'fecha')::date, current_date));
  if t is null then raise exception 'No hay tasa BCV cargada'; end if;
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]')) loop
    select iva into iv from productos where id = (it->>'producto_id')::bigint and empresa_id = p_empresa;
    m := round((it->>'cantidad')::numeric * coalesce((it->>'costo')::numeric, 0), 2);
    if iv = 'E' then ex := ex + m; else gr := gr + m; end if;
  end loop;
  insert into compras (empresa_id, proveedor_id, proveedor, rif, numero, control, fecha, tasa, exento_usd, gravable_usd, iva_usd, total_usd, vence)
  values (p_empresa, pv.id, pv.nombre, pv.rif, trim(p_factura->>'numero'), nullif(trim(p_factura->>'control'), ''),
          coalesce((p_factura->>'fecha')::date, current_date), t, ex, gr, round(gr * 0.16, 2), ex + gr + round(gr * 0.16, 2),
          coalesce((p_factura->>'fecha')::date, current_date) + pv.credito_dias)
  returning * into c;
  perform recibir_compra(p_empresa, p_items, pv.nombre || ' · factura ' || c.numero);
  return c;
end $$;
revoke all on function recibir_factura(uuid, jsonb, jsonb) from public, anon;
grant execute on function recibir_factura(uuid, jsonb, jsonb) to authenticated;

create or replace function pagar_compra(p_compra bigint, p_monto numeric, p_metodo text default null)
returns compras
language plpgsql security definer set search_path = public as $$
declare c compras;
begin
  select * into c from compras where id = p_compra for update;
  if c.id is null or not tiene_rol(c.empresa_id, '{dueno,gerente}') then raise exception 'Solo el dueño registra pagos a proveedores'; end if;
  if p_monto <= 0 or p_monto > c.total_usd - c.pagado_usd + 0.004 then
    raise exception 'El pago debe ser entre 0,01 y % (lo que se debe)', (c.total_usd - c.pagado_usd)::float;
  end if;
  insert into pagos_compras (empresa_id, compra_id, monto_usd, metodo) values (c.empresa_id, c.id, p_monto, p_metodo);
  update compras set pagado_usd = pagado_usd + p_monto where id = c.id returning * into c;
  return c;
end $$;
revoke all on function pagar_compra(bigint, numeric, text) from public, anon;
grant execute on function pagar_compra(bigint, numeric, text) to authenticated;

create table gastos (
  id         bigint generated always as identity primary key,
  empresa_id uuid not null references empresas,
  fecha      date not null default current_date,
  usd        numeric(14,2) not null check (usd >= 0),
  datos      jsonb not null default '{}',     -- categoría, descripción, cuenta, deducible, retención de ISLR…
  anulado    boolean not null default false,
  creado_por uuid default auth.uid(),
  creado_en  timestamptz not null default now()
);
create index on gastos (empresa_id, fecha);

create table colecciones (
  empresa_id  uuid not null references empresas,
  nombre      text not null,
  datos       jsonb not null,
  actualizado timestamptz not null default now(),
  primary key (empresa_id, nombre)
);

-- ---------- Permisos ----------
alter table proveedores   enable row level security;
alter table compras       enable row level security;
alter table pagos_compras enable row level security;
alter table gastos        enable row level security;
alter table colecciones   enable row level security;

create policy ver on proveedores for select using (es_miembro(empresa_id));
create policy escribir on proveedores for insert with check (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'));
create policy editar on proveedores for update using (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}')) with check (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'));
create policy ver on compras for select using (tiene_rol(empresa_id, '{dueno,gerente,regente,almacen}'));
create policy ver on pagos_compras for select using (tiene_rol(empresa_id, '{dueno,gerente}'));
create policy ver on gastos for select using (tiene_rol(empresa_id, '{dueno,gerente}'));
create policy escribir on gastos for insert with check (tiene_rol(empresa_id, '{dueno,gerente}'));
create policy editar on gastos for update using (tiene_rol(empresa_id, '{dueno,gerente}')) with check (tiene_rol(empresa_id, '{dueno,gerente}'));
-- Las listas de configuración las ve todo el negocio y las cambia el dueño
-- (las que empiezan por «privado_» solo las ve el dueño)
create policy ver on colecciones for select using (es_miembro(empresa_id) and (nombre not like 'privado\_%' or tiene_rol(empresa_id, '{dueno,gerente}')));
-- (las que empiezan por «equipo_», como fallas y cotizaciones, las guarda cualquiera del negocio)
create policy escribir on colecciones for insert with check (tiene_rol(empresa_id, '{dueno,gerente}') or (nombre like 'equipo\_%' and es_miembro(empresa_id)));
create policy editar on colecciones for update using (tiene_rol(empresa_id, '{dueno,gerente}') or (nombre like 'equipo\_%' and es_miembro(empresa_id)))
  with check (tiene_rol(empresa_id, '{dueno,gerente}') or (nombre like 'equipo\_%' and es_miembro(empresa_id)));

revoke delete on proveedores, compras, pagos_compras, gastos from anon, authenticated;
revoke insert, update on compras, pagos_compras from anon, authenticated;

create trigger auditar after insert or update on gastos      for each row execute function auditar();
create trigger auditar after insert                    on compras     for each row execute function auditar();
create trigger auditar after insert or update on colecciones for each row execute function auditar();

-- >>>>> migrations/0010_resumen.sql
-- =====================================================================
-- Cuadre · Migración 0010: cuánto gana el negocio, por mes
--   ventas  = bases de las facturas (sin IVA ni IGTF) − notas de crédito + notas de débito, en dólares
--   costo   = costo de los lotes que salieron vendidos − lo devuelto
--   gastos  = gastos del mes que no están anulados
-- Solo lo ven el dueño y el gerente.
-- =====================================================================
create or replace function resumen_mensual(p_empresa uuid, p_meses int default 3)
returns table (mes date, ventas_usd numeric, costo_usd numeric, gastos_usd numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not tiene_rol(p_empresa, '{dueno,gerente}') then raise exception 'Solo el dueño ve las ganancias'; end if;
  return query
  with meses as (
    select (date_trunc('month', current_date) - (n || ' month')::interval)::date m from generate_series(0, greatest(p_meses, 1) - 1) n
  )
  select m,
    coalesce((select round(sum(case when d.tipo = 'NC' then -1 else 1 end * (d.base_exenta + d.base_general + d.base_reducida) / d.tasa), 2)
              from documentos d where d.empresa_id = p_empresa and d.estado <> 'rechazado' and date_trunc('month', d.fecha)::date = m), 0),
    coalesce((select round(sum(-mv.cantidad * coalesce(mv.costo, 0)), 2)
              from movimientos mv where mv.empresa_id = p_empresa and mv.tipo in ('venta', 'devolucion') and date_trunc('month', mv.fecha)::date = m), 0),
    coalesce((select sum(g.usd) from gastos g where g.empresa_id = p_empresa and not g.anulado and date_trunc('month', g.fecha)::date = m), 0)
  from meses order by m;
end $$;
revoke all on function resumen_mensual(uuid, int) from public, anon;
grant execute on function resumen_mensual(uuid, int) to authenticated;

-- >>>>> migrations/0011_recipes.sql
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

-- >>>>> migrations/0012_alertas.sql
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

-- >>>>> migrations/0013_contingencia.sql
-- =====================================================================
-- Cuadre · Migración 0013: ventas hechas sin internet (contingencia)
--   * vender() acepta el número del talonario de contingencia y la fecha
--     y hora en que se vendió; la factura queda con esa fecha y con la tasa
--     BCV de ese día. El número debe estar en el talonario y no repetirse.
--   * En contingencia vale el precio que tenía la caja al vender.
-- =====================================================================

create or replace function emitir_documento(
  p_empresa uuid, p_tipo tipo_doc, p_cliente jsonb, p_lineas jsonb,
  p_pagos jsonb default '[]', p_afecta uuid default null, p_motivo text default null,
  p_origen origen_doc default 'sistema', p_numero_manual bigint default null,
  p_ref_tipo text default null, p_ref_id uuid default null
) returns documentos
language plpgsql security definer set search_path = public as $$
declare
  emp empresas; fac documentos; d documentos;
  t numeric; l jsonb; p jsonb; i int := 0;
  pu numeric; m numeric;
  b_e numeric := 0; b_g numeric := 0; b_r numeric := 0; iva_g numeric; iva_r numeric;
  div_bs numeric := 0; v_igtf numeric := 0; tot numeric;
begin
  select * into emp from empresas where id = p_empresa and activo;
  if emp.id is null then raise exception 'Empresa no encontrada'; end if;
  if not es_miembro(p_empresa) or tiene_rol(p_empresa, '{almacen,coach,bioanalista}') then
    raise exception 'No tienes permiso para emitir documentos en %', emp.nombre;
  end if;
  if p_tipo <> 'FAC' and not tiene_rol(p_empresa, emp.roles_notas) then
    raise exception 'Solo % pueden emitir notas de crédito o débito', array_to_string(emp.roles_notas, ', ');
  end if;
  if jsonb_array_length(coalesce(p_lineas, '[]')) = 0 then raise exception 'El documento no tiene renglones'; end if;
  if coalesce(p_cliente->>'rif', '') = '' or coalesce(p_cliente->>'nombre', '') = '' then
    raise exception 'Falta el RIF o la cédula y el nombre del cliente';
  end if;

  if p_tipo <> 'FAC' and coalesce(trim(p_motivo), '') = '' then
    raise exception 'Una nota de crédito o débito necesita su motivo';
  end if;

  if p_tipo = 'FAC' then
    t := tasa_del_dia(coalesce(nullif(current_setting('cuadre.fecha', true), '')::timestamptz::date, current_date));
  else
    select * into fac from documentos where id = p_afecta and empresa_id = p_empresa and tipo = 'FAC';
    if fac.id is null then raise exception 'La nota debe afectar una factura de esta misma empresa'; end if;
    t := fac.tasa;      -- la nota usa la tasa de su factura
  end if;
  if t is null then raise exception 'No hay tasa BCV cargada'; end if;

  -- Número: el siguiente del correlativo, o el del talonario de contingencia
  if p_origen = 'contingencia' then
    if p_numero_manual is null
       or p_numero_manual not between coalesce(emp.talonario_desde, 0) and coalesce(emp.talonario_hasta, -1) then
      raise exception 'El número % no está en el talonario de contingencia', p_numero_manual;
    end if;
  end if;

  -- Primero se calculan los montos; luego se guarda todo de una vez
  for l in select * from jsonb_array_elements(p_lineas) loop
    if coalesce((l->>'cantidad')::numeric, 0) <= 0 then raise exception 'Renglón con cantidad inválida'; end if;
    pu := round(coalesce((l->>'precio_bs')::numeric, (l->>'precio_usd')::numeric * t), 2);
    if pu is null or pu < 0 then raise exception 'Renglón sin precio'; end if;
    m  := round(pu * (l->>'cantidad')::numeric, 2);
    case l->>'alicuota'
      when 'E' then b_e := b_e + m;
      when 'G' then b_g := b_g + m;
      when 'R' then b_r := b_r + m;
      else raise exception 'Alícuota inválida: % (usa E, G o R)', l->>'alicuota';
    end case;
  end loop;
  iva_g := round(b_g * emp.iva_general / 100, 2);
  iva_r := round(b_r * emp.iva_reducida / 100, 2);
  tot := b_e + b_g + iva_g + b_r + iva_r;

  if p_tipo = 'FAC' then
    for p in select * from jsonb_array_elements(coalesce(p_pagos, '[]')) loop
      if coalesce((p->>'divisa')::boolean, false) then div_bs := div_bs + (p->>'monto_bs')::numeric; end if;
    end loop;
    v_igtf := round(least(div_bs, tot) * emp.igtf / 100, 2);
  elsif p_tipo = 'NC' then
    -- Lo que queda por acreditar: factura sin IGTF + notas de débito − notas de crédito ya emitidas
    if tot > fac.total - fac.igtf
             + coalesce((select sum(total) from documentos where afecta_id = fac.id and tipo = 'ND' and estado <> 'rechazado'), 0)
             - coalesce((select sum(total) from documentos where afecta_id = fac.id and tipo = 'NC' and estado <> 'rechazado'), 0) then
      raise exception 'La nota de crédito pasa de lo que queda por acreditar en la factura %', fac.numero;
    end if;
  end if;

  insert into documentos (empresa_id, tipo, origen, numero, serie, estado, fecha, cliente_rif, cliente_nombre,
                          cliente_dir, cliente_tel, tasa, base_exenta, base_general, iva_general,
                          base_reducida, iva_reducida, igtf, total, total_usd,
                          afecta_id, motivo, ref_tipo, ref_id)
  values (p_empresa, p_tipo, p_origen,
          case when p_origen = 'contingencia' then p_numero_manual else tomar_numero(p_empresa, p_tipo, p_origen) end,
          case when p_origen = 'contingencia' then emp.talonario_serie else emp.imprenta_serie end,
          case when p_origen = 'contingencia' then 'emitido'::estado_doc else 'pendiente_imprenta'::estado_doc end,
          case when p_origen = 'contingencia' then coalesce(nullif(current_setting('cuadre.fecha', true), '')::timestamptz, now()) else now() end,
          upper(trim(p_cliente->>'rif')), trim(p_cliente->>'nombre'), p_cliente->>'dir', p_cliente->>'tel',
          t, b_e, b_g, iva_g, b_r, iva_r, v_igtf, tot + v_igtf, round((tot + v_igtf) / t, 2),
          p_afecta, p_motivo, p_ref_tipo, p_ref_id)
  returning * into d;

  for l in select * from jsonb_array_elements(p_lineas) loop
    i := i + 1;
    pu := round(coalesce((l->>'precio_bs')::numeric, (l->>'precio_usd')::numeric * t), 2);
    insert into documento_lineas (documento_id, renglon, descripcion, cantidad, precio_unit, alicuota, monto, ref)
    values (d.id, i, l->>'descripcion', (l->>'cantidad')::numeric, pu, (l->>'alicuota')::alicuota_iva,
            round(pu * (l->>'cantidad')::numeric, 2), l->'ref');
  end loop;

  if p_tipo = 'FAC' then
    for p in select * from jsonb_array_elements(coalesce(p_pagos, '[]')) loop
      insert into documento_pagos (documento_id, metodo, monto_bs, divisa, referencia)
      values (d.id, p->>'metodo', (p->>'monto_bs')::numeric, coalesce((p->>'divisa')::boolean, false), p->>'referencia');
    end loop;
  end if;
  return d;
end $$;

drop function if exists vender(uuid, jsonb, jsonb, jsonb);
create or replace function vender(p_empresa uuid, p_cliente jsonb, p_items jsonb, p_pagos jsonb default '[]',
                                  p_origen origen_doc default 'sistema', p_numero bigint default null, p_fecha timestamptz default null)
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
    if not ok and p_origen <> 'contingencia' then raise exception 'El precio de % cambió. Actualiza la caja', pr.nombre; end if;
    lineas := lineas || jsonb_build_object('descripcion', pr.nombre || coalesce(' · ' || nullif(pr.presentacion, '—'), ''),
                                           'cantidad', (it->>'cantidad')::numeric, 'precio_usd', pu, 'alicuota', pr.iva,
                                           'ref', jsonb_build_object('producto_id', pr.id));
  end loop;

  -- Venta hecha sin internet: número del talonario de contingencia y fecha en que se vendió
  if p_origen = 'contingencia' then
    if p_fecha is null or p_fecha > now() + interval '5 minutes' or p_fecha < now() - interval '30 days' then
      raise exception 'Fecha de la venta sin conexión inválida';
    end if;
    perform set_config('cuadre.fecha', p_fecha::text, true);
  end if;
  d := emitir_documento(p_empresa, 'FAC', p_cliente, lineas, p_pagos, null, null, p_origen, p_numero, 'venta', null);
  perform set_config('cuadre.fecha', '', true);

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
revoke all on function vender(uuid, jsonb, jsonb, jsonb, origen_doc, bigint, timestamptz) from public, anon;
grant execute on function vender(uuid, jsonb, jsonb, jsonb, origen_doc, bigint, timestamptz) to authenticated;

-- >>>>> migrations/0014_compras_servicios.sql
-- =====================================================================
-- Cuadre · Migración 0014: facturas de compra sin inventario
-- (laboratorio y CrossFit: reactivos, insumos, servicios, alquiler…)
--   * registrar_compra(): la factura del proveedor va al libro de compras
--     con su exento y su base gravable (IVA 16 %), y, si aplica, la
--     retención de ISLR que se le hizo.
--   * La misma factura del mismo proveedor no se registra dos veces.
-- =====================================================================
alter table compras add column if not exists datos jsonb not null default '{}';

-- p_factura: {"proveedor","rif","numero","control","fecha","exento_bs","gravable_bs","retencion":{"k","pn","comp"}}
create or replace function registrar_compra(p_empresa uuid, p_factura jsonb)
returns compras
language plpgsql security definer set search_path = public as $$
declare c compras; t numeric; f date; ex numeric; gr numeric; rif text;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente}') then raise exception 'Solo el dueño registra facturas de compra'; end if;
  if coalesce(trim(p_factura->>'proveedor'), '') = '' or coalesce(trim(p_factura->>'numero'), '') = '' then
    raise exception 'Escribe el proveedor y el número de la factura';
  end if;
  rif := upper(regexp_replace(coalesce(p_factura->>'rif', ''), '[.\s]', '', 'g'));
  rif := regexp_replace(rif, '^([JGVEP])-?([0-9]{8})-?([0-9])$', '\1-\2-\3');
  if rif <> '' and rif !~ '^[JGVEP]-[0-9]{8}-[0-9]$' then raise exception 'El RIF del proveedor debe quedar así: J-12345678-9'; end if;
  f := coalesce((p_factura->>'fecha')::date, current_date);
  t := tasa_del_dia(f);
  if t is null then raise exception 'No hay tasa BCV cargada'; end if;
  ex := coalesce((p_factura->>'exento_bs')::numeric, 0); gr := coalesce((p_factura->>'gravable_bs')::numeric, 0);
  if ex < 0 or gr < 0 or ex + gr = 0 then raise exception 'Escribe el monto exento o la base gravable'; end if;
  insert into compras (empresa_id, proveedor, rif, numero, control, fecha, tasa, exento_usd, gravable_usd, iva_usd, total_usd, pagado_usd, datos)
  values (p_empresa, trim(p_factura->>'proveedor'), nullif(rif, ''), trim(p_factura->>'numero'), nullif(trim(p_factura->>'control'), ''), f, t,
          round(ex / t, 2), round(gr / t, 2), round(gr * 0.16 / t, 2), round((ex + gr + round(gr * 0.16, 2)) / t, 2),
          round((ex + gr + round(gr * 0.16, 2)) / t, 2),   -- servicios y gastos: se registran ya pagados
          jsonb_build_object('exento_bs', ex, 'gravable_bs', gr, 'retencion', p_factura->'retencion'))
  returning * into c;
  return c;
end $$;
revoke all on function registrar_compra(uuid, jsonb) from public, anon;
grant execute on function registrar_compra(uuid, jsonb) to authenticated;

-- >>>>> Historial de migraciones
insert into supabase_migrations.schema_migrations (version, name) values
  ('0003', 'usuarios'),('0004', 'farmacia'),('0005', 'clientes'),('0006', 'notas'),('0007', 'laboratorio'),('0008', 'crossfit'),('0009', 'compras_gastos'),('0010', 'resumen'),('0011', 'recipes'),('0012', 'alertas'),('0013', 'contingencia'),('0014', 'compras_servicios')
on conflict (version) do nothing;
select 'Listo: migraciones aplicadas' as resultado;
