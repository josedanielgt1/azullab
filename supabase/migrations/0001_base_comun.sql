-- =====================================================================
-- Cuadre · Base común del Grupo Azullab
-- Migración 0001 para Supabase (Postgres 15 o superior)
--
-- La usan los tres sistemas: farmacia, laboratorio y CrossFit.
-- Cada negocio es un contribuyente con su propio RIF (una "empresa").
--
-- Reglas que hace cumplir la base de datos (no solo la pantalla):
--   * Cada usuario ve solo las empresas donde es miembro, con su rol.
--   * Los números de factura, nota de crédito y nota de débito son
--     correlativos por empresa, sin saltos ni repetidos.
--   * Los totales, el IVA y el IGTF los calcula la base, no el navegador.
--   * Un documento fiscal emitido no se edita ni se borra: se corrige con
--     una nota de crédito o de débito.
--   * Una nota de crédito no puede acreditar más de lo que queda de su factura.
--   * Todo cambio queda en la auditoría con usuario y hora.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tipos ----------
create type tipo_negocio as enum ('farmacia','laboratorio','crossfit');
create type rol_usuario  as enum (
  'dueno',        -- todo, en todas sus empresas
  'gerente',      -- administra una empresa
  'regente',      -- farmacéutico regente (farmacia)
  'cajero',       -- caja (farmacia)
  'almacen',      -- inventario y compras (farmacia)
  'atencion',     -- recepción y caja (laboratorio, CrossFit)
  'bioanalista',  -- resultados (laboratorio)
  'coach'         -- pizarra y clases (CrossFit)
);
create type tipo_doc     as enum ('FAC','NC','ND');
create type origen_doc   as enum ('sistema','contingencia');
create type estado_doc   as enum ('pendiente_imprenta','emitido','rechazado');
create type alicuota_iva as enum ('E','G','R');   -- exento, general 16 %, reducida 8 %

-- ---------- Empresas (un RIF por negocio) ----------
create table empresas (
  id              uuid primary key default gen_random_uuid(),
  tipo            tipo_negocio not null,
  nombre          text not null,                 -- "Azullab Farmacia"
  razon_social    text not null,
  rif             text not null unique check (rif ~ '^[JGVEP]-[0-9]{8}-[0-9]$'),
  domicilio       text not null,
  telefono        text,
  -- Imprenta digital autorizada por el SENIAT
  imprenta_nombre text,
  imprenta_rif    text check (imprenta_rif is null or imprenta_rif ~ '^[JGVEP]-[0-9]{8}-[0-9]$'),
  imprenta_serie  text not null default '00',
  providencia     text,
  -- Talonario de contingencia (cuando no hay internet o falla la imprenta)
  talonario_serie text not null default '01',
  talonario_desde int,
  talonario_hasta int,
  -- Parámetros que cambian por ley: se editan, no se programan
  iva_general     numeric(5,2) not null default 16,
  iva_reducida    numeric(5,2) not null default 8,
  igtf            numeric(5,2) not null default 3,
  roles_notas     rol_usuario[] not null default '{dueno,gerente}',  -- quién emite NC y ND
  activo          boolean not null default true,
  creado_en       timestamptz not null default now()
);

-- ---------- Usuarios ----------
create table perfiles (
  user_id   uuid primary key references auth.users on delete cascade,
  nombre    text not null,
  cedula    text,
  creado_en timestamptz not null default now()
);

-- Un usuario puede estar en varias empresas con un rol distinto en cada una
create table miembros (
  user_id    uuid not null references perfiles on delete cascade,
  empresa_id uuid not null references empresas on delete cascade,
  rol        rol_usuario not null,
  caja       text,                       -- "Caja 1", "Almacén"…
  activo     boolean not null default true,
  primary key (user_id, empresa_id)
);
create index on miembros (empresa_id);

-- ---------- Funciones de permisos ----------
create or replace function rol_en(e uuid) returns rol_usuario
language sql stable security definer set search_path = public as $$
  select rol from miembros where user_id = auth.uid() and empresa_id = e and activo
$$;

create or replace function es_miembro(e uuid) returns boolean
language sql stable as $$ select rol_en(e) is not null $$;

create or replace function tiene_rol(e uuid, roles rol_usuario[]) returns boolean
language sql stable as $$ select coalesce(rol_en(e) = any(roles), false) $$;

create or replace function mis_empresas() returns setof uuid
language sql stable security definer set search_path = public as $$
  select empresa_id from miembros where user_id = auth.uid() and activo
$$;

-- ---------- Tasa BCV ----------
-- La carga la función "tasa-bcv" (supabase/functions) cada hora; el dueño puede corregirla.
create table tasas_bcv (
  fecha     date primary key,
  tasa      numeric(14,4) not null check (tasa > 0),
  fuente    text not null default 'BCV',
  creado_en timestamptz not null default now(),
  creado_por uuid references auth.users
);

-- Tasa vigente en una fecha (la última publicada hasta ese día)
create or replace function tasa_del_dia(f date default current_date) returns numeric
language sql stable security definer set search_path = public as $$
  select tasa from tasas_bcv where fecha <= f order by fecha desc limit 1
$$;

-- ---------- Correlativos fiscales ----------
-- Solo los usa emitir_documento(), dentro de la misma transacción: si la
-- emisión falla, el número no se consume. Nadie lo llama directo.
create table correlativos (
  empresa_id uuid not null references empresas on delete cascade,
  tipo       tipo_doc not null,
  origen     origen_doc not null default 'sistema',
  siguiente  bigint not null default 1 check (siguiente > 0),
  primary key (empresa_id, tipo, origen)
);

create or replace function tomar_numero(e uuid, t tipo_doc, o origen_doc) returns bigint
language plpgsql security definer set search_path = public as $$
declare n bigint;
begin
  insert into correlativos (empresa_id, tipo, origen) values (e, t, o)
    on conflict do nothing;
  update correlativos set siguiente = siguiente + 1
    where empresa_id = e and tipo = t and origen = o
    returning siguiente - 1 into n;
  return n;
end $$;
revoke all on function tomar_numero(uuid, tipo_doc, origen_doc) from public, anon, authenticated;

-- ---------- Documentos fiscales (factura, nota de crédito, nota de débito) ----------
create table documentos (
  id              uuid primary key default gen_random_uuid(),
  empresa_id      uuid not null references empresas,
  tipo            tipo_doc not null,
  origen          origen_doc not null default 'sistema',
  numero          bigint not null,
  numero_control  text,                         -- lo asigna la imprenta digital
  serie           text not null,
  estado          estado_doc not null default 'pendiente_imprenta',
  fecha           timestamptz not null default now(),
  -- Cliente o receptor
  cliente_rif     text not null,                -- RIF o cédula (V-12345678)
  cliente_nombre  text not null,
  cliente_dir     text,
  cliente_tel     text,
  -- Montos en bolívares, calculados por la base
  tasa            numeric(14,4) not null,
  base_exenta     numeric(16,2) not null default 0,
  base_general    numeric(16,2) not null default 0,
  iva_general     numeric(16,2) not null default 0,
  base_reducida   numeric(16,2) not null default 0,
  iva_reducida    numeric(16,2) not null default 0,
  igtf            numeric(16,2) not null default 0,
  total           numeric(16,2) not null,
  total_usd       numeric(16,2) not null,
  -- Nota de crédito o débito: a qué factura afecta y por qué
  afecta_id       uuid references documentos,
  motivo          text,
  -- De dónde viene (venta de caja, orden del laboratorio, cobro del box…)
  ref_tipo        text,
  ref_id          uuid,
  imprenta_resp   jsonb,                        -- respuesta de la imprenta digital
  creado_por      uuid not null references auth.users default auth.uid(),
  unique (empresa_id, tipo, origen, numero),
  check ((tipo = 'FAC') = (afecta_id is null)),
  check (tipo = 'FAC' or motivo is not null)
);
create index on documentos (empresa_id, fecha);
create index on documentos (afecta_id);

create table documento_lineas (
  id           bigint generated always as identity primary key,
  documento_id uuid not null references documentos on delete cascade,
  renglon      int not null,
  descripcion  text not null,
  cantidad     numeric(12,3) not null check (cantidad > 0),
  precio_unit  numeric(16,2) not null check (precio_unit >= 0),   -- en Bs
  alicuota     alicuota_iva not null,
  monto        numeric(16,2) not null,
  ref          jsonb,                                            -- producto, examen, plan…
  unique (documento_id, renglon)
);

create table documento_pagos (
  id           bigint generated always as identity primary key,
  documento_id uuid not null references documentos on delete cascade,
  metodo       text not null,                 -- "Pago móvil", "Efectivo USD", "Zelle"…
  monto_bs     numeric(16,2) not null check (monto_bs > 0),
  divisa       boolean not null default false,-- pagado en moneda extranjera: causa IGTF
  referencia   text
);

-- Emitir un documento fiscal.
--   cliente: {"rif","nombre","dir","tel"}
--   lineas:  [{"descripcion","cantidad","precio_usd" | "precio_bs","alicuota","ref"}]
--   pagos:   [{"metodo","monto_bs","divisa","referencia"}]   (solo facturas)
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
    t := tasa_del_dia(current_date);
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

  insert into documentos (empresa_id, tipo, origen, numero, serie, estado, cliente_rif, cliente_nombre,
                          cliente_dir, cliente_tel, tasa, base_exenta, base_general, iva_general,
                          base_reducida, iva_reducida, igtf, total, total_usd,
                          afecta_id, motivo, ref_tipo, ref_id)
  values (p_empresa, p_tipo, p_origen,
          case when p_origen = 'contingencia' then p_numero_manual else tomar_numero(p_empresa, p_tipo, p_origen) end,
          case when p_origen = 'contingencia' then emp.talonario_serie else emp.imprenta_serie end,
          case when p_origen = 'contingencia' then 'emitido'::estado_doc else 'pendiente_imprenta'::estado_doc end,
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

-- Lo que puede cambiar después de emitir: solo lo que devuelve la imprenta digital
create or replace function registrar_imprenta(p_doc uuid, p_control text, p_estado estado_doc, p_resp jsonb)
returns documentos
language plpgsql security definer set search_path = public as $$
declare d documentos;
begin
  select * into d from documentos where id = p_doc;
  if d.id is null or not (es_miembro(d.empresa_id) or auth.role() = 'service_role') then
    raise exception 'Documento no encontrado';
  end if;
  if d.estado <> 'pendiente_imprenta' then raise exception 'El documento ya fue procesado por la imprenta'; end if;
  perform set_config('cuadre.imprenta', 'si', true);
  update documentos set numero_control = p_control, estado = p_estado, imprenta_resp = p_resp
    where id = p_doc returning * into d;
  return d;
end $$;

-- Ningún documento emitido se edita ni se borra
create or replace function documentos_inmutables() returns trigger
language plpgsql as $$
begin
  if tg_op = 'DELETE' then raise exception 'Un documento fiscal no se borra: emite una nota de crédito'; end if;
  if tg_table_name = 'documentos' and current_setting('cuadre.imprenta', true) = 'si'
     and (old.numero, old.total, old.cliente_rif, old.empresa_id, old.tipo) = (new.numero, new.total, new.cliente_rif, new.empresa_id, new.tipo) then
    return new;
  end if;
  raise exception 'Un documento fiscal emitido no se edita: emite una nota de crédito o de débito';
end $$;
create trigger documentos_inmutables before update or delete on documentos
  for each row execute function documentos_inmutables();
create trigger lineas_inmutables before update or delete on documento_lineas
  for each row execute function documentos_inmutables();
create trigger pagos_inmutables before update or delete on documento_pagos
  for each row execute function documentos_inmutables();

-- ---------- Libro de ventas (por empresa y mes) ----------
create or replace view libro_ventas with (security_invoker = true) as
select d.empresa_id, date_trunc('month', d.fecha)::date as mes, d.fecha::date as fecha,
       d.tipo, d.numero, d.numero_control, d.serie, d.origen,
       a.numero as afecta_numero, d.cliente_rif, d.cliente_nombre,
       s * d.total as total, s * d.base_exenta as exento,
       s * d.base_general as base_general, s * d.iva_general as iva_general,
       s * d.base_reducida as base_reducida, s * d.iva_reducida as iva_reducida,
       s * d.igtf as igtf, d.tasa
from documentos d
left join documentos a on a.id = d.afecta_id
cross join lateral (select case when d.tipo = 'NC' then -1 else 1 end as s) x
where d.estado <> 'rechazado';

-- ---------- Auditoría ----------
create table auditoria (
  id         bigint generated always as identity primary key,
  empresa_id uuid,
  tabla      text not null,
  operacion  text not null,
  fila_id    text,
  antes      jsonb,
  despues    jsonb,
  usuario    uuid default auth.uid(),
  en         timestamptz not null default now()
);
create index on auditoria (empresa_id, en);

create or replace function auditar() returns trigger
language plpgsql security definer set search_path = public as $$
declare r jsonb := to_jsonb(coalesce(new, old));
begin
  insert into auditoria (empresa_id, tabla, operacion, fila_id, antes, despues)
  values (coalesce((r->>'empresa_id')::uuid, case when tg_table_name = 'empresas' then (r->>'id')::uuid end),
          tg_table_name, tg_op, coalesce(r->>'id', r->>'user_id', r->>'fecha'),
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end);
  return coalesce(new, old);
end $$;
create trigger auditar after insert or update or delete on empresas   for each row execute function auditar();
create trigger auditar after insert or update or delete on miembros   for each row execute function auditar();
create trigger auditar after insert or update or delete on tasas_bcv  for each row execute function auditar();
create trigger auditar after insert                     on documentos for each row execute function auditar();

-- ---------- Seguridad por filas ----------
alter table empresas         enable row level security;
alter table perfiles         enable row level security;
alter table miembros         enable row level security;
alter table tasas_bcv        enable row level security;
alter table correlativos     enable row level security;
alter table documentos       enable row level security;
alter table documento_lineas enable row level security;
alter table documento_pagos  enable row level security;
alter table auditoria        enable row level security;

create policy ver on empresas for select using (id in (select mis_empresas()));
create policy editar on empresas for update using (tiene_rol(id, '{dueno}')) with check (tiene_rol(id, '{dueno}'));

create policy ver on perfiles for select using (
  user_id = auth.uid()
  or user_id in (select user_id from miembros where empresa_id in (select mis_empresas())));
create policy editar_propio on perfiles for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy ver on miembros for select using (empresa_id in (select mis_empresas()));
create policy dueno_crea on miembros for insert with check (tiene_rol(empresa_id, '{dueno,gerente}') and (rol <> 'dueno' or tiene_rol(empresa_id, '{dueno}')));
create policy dueno_edita on miembros for update using (tiene_rol(empresa_id, '{dueno}')) with check (tiene_rol(empresa_id, '{dueno}'));
create policy dueno_borra on miembros for delete using (tiene_rol(empresa_id, '{dueno}') and user_id <> auth.uid());

create policy ver on tasas_bcv for select to authenticated using (true);
create policy dueno_carga on tasas_bcv for insert to authenticated
  with check (exists (select 1 from miembros where user_id = auth.uid() and rol = 'dueno' and activo));
create policy dueno_corrige on tasas_bcv for update to authenticated
  using (exists (select 1 from miembros where user_id = auth.uid() and rol = 'dueno' and activo));

-- Documentos: se leen con permiso; se crean solo con emitir_documento()
create policy ver on documentos for select using (es_miembro(empresa_id));
create policy ver on documento_lineas for select using (exists (select 1 from documentos d where d.id = documento_id and es_miembro(d.empresa_id)));
create policy ver on documento_pagos  for select using (exists (select 1 from documentos d where d.id = documento_id and es_miembro(d.empresa_id)));

create policy dueno_ve on auditoria for select using (tiene_rol(empresa_id, '{dueno,gerente}'));

revoke insert, update, delete on documentos, documento_lineas, documento_pagos, correlativos, auditoria from anon, authenticated;
revoke all on function emitir_documento from public, anon;
grant execute on function emitir_documento to authenticated;
revoke all on function registrar_imprenta from public, anon;
grant execute on function registrar_imprenta to authenticated, service_role;
