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

-- >>>>> Historial de migraciones
insert into supabase_migrations.schema_migrations (version, name) values
  ('0003', 'usuarios'),('0004', 'farmacia'),('0005', 'clientes'),('0006', 'notas'),('0007', 'laboratorio')
on conflict (version) do nothing;
select 'Listo: migraciones aplicadas' as resultado;
