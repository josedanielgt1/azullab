-- =====================================================================
-- Cuadre · Migración 0023: facturación por máquina fiscal (farmacia)
--
-- La farmacia factura por impresora fiscal (Providencia 0071, art. 8;
-- normas técnicas de la SNAT/2018/0141). El laboratorio y el CrossFit
-- siguen con imprenta digital: el medio se escoge por empresa.
--
--   * empresas.medio_factura: 'imprenta' (como hasta hoy) o 'maquina',
--     con marca, modelo, número de registro (el que va junto al logo MH),
--     distribuidor y la dirección del agente local de la caja.
--   * Cada documento guarda por qué medio salió: 'imprenta', 'maquina'
--     o 'talonario' (sin internet o con la máquina dañada).
--   * Con máquina, la factura queda «pendiente» hasta que la impresora la
--     imprime y devuelve su número de la memoria fiscal:
--     registrar_maquina(). Cuadre nunca inventa ese número.
--   * Si la impresora falla: registrar_falla_maquina() la pasa al número
--     del talonario de imprenta autorizada (Providencia 0071).
--   * Un número del talonario se usa una sola vez, sea por falta de
--     internet o por falla de la máquina (talonario_usados).
--   * Reporte Z: uno por día y por máquina. La base lo compara con sus
--     propias facturas y dice si cuadra (registrar_reporte_z).
--   * Libro de ventas: con máquina, las facturas a consumidor final van en
--     un renglón por Reporte Z, del primer al último número (Reglamento de
--     la Ley del IVA, art. 77); las de contribuyentes con RIF, una por una.
--   * Libro de control de la máquina: instalación, inspecciones, fallas y
--     reparaciones (maquina_eventos). No se edita ni se borra.
-- =====================================================================

-- ---------- Medio de facturación de cada empresa ----------
alter table empresas
  add column if not exists medio_factura text not null default 'imprenta',
  add column if not exists maquina_marca text,
  add column if not exists maquina_modelo text,
  add column if not exists maquina_registro text,
  add column if not exists maquina_distribuidor text,
  add column if not exists maquina_agente text not null default 'http://127.0.0.1:7123';
alter table empresas
  add constraint empresas_medio_factura check (medio_factura in ('imprenta', 'maquina')),
  add constraint empresas_maquina_registro check (maquina_registro is null or maquina_registro ~ '^[A-Z0-9]{6,15}$'),
  add constraint empresas_maquina_lista check (medio_factura = 'imprenta' or maquina_registro is not null),
  add constraint empresas_maquina_sin_codigo check ((coalesce(maquina_marca, '') || coalesce(maquina_modelo, '') || coalesce(maquina_distribuidor, '')) !~ '[<>]'),
  add constraint empresas_maquina_agente check (maquina_agente ~ '^(https?://(127\.0\.0\.1|localhost)(:[0-9]{2,5})?/?|simulada)$');
comment on column empresas.medio_factura is 'imprenta (imprenta digital autorizada) o maquina (impresora fiscal); el talonario es solo para contingencias';
comment on column empresas.maquina_registro is 'Número de registro de la impresora fiscal (el que sale junto al logo MH), en mayúsculas';
comment on column empresas.maquina_agente is 'Dirección del agente local de la caja (http://127.0.0.1:7123) o «simulada» para practicar';

-- ---------- Por qué medio salió cada documento ----------
alter table documentos
  add column if not exists medio text not null default 'imprenta',
  add column if not exists maquina_registro text,
  add column if not exists numero_fiscal bigint,
  add column if not exists reporte_z int;
alter table documentos
  add constraint documentos_medio check (medio in ('imprenta', 'maquina', 'talonario')),
  add constraint documentos_maquina check (medio <> 'maquina' or maquina_registro is not null),
  add constraint documentos_numero_fiscal_pos check (numero_fiscal is null or numero_fiscal > 0);
-- Un número de la memoria fiscal no se repite en la misma máquina
create unique index if not exists documentos_numero_fiscal
  on documentos (empresa_id, maquina_registro, tipo, numero_fiscal) where numero_fiscal is not null;
create index if not exists documentos_pendientes_maquina on documentos (empresa_id) where medio = 'maquina' and estado = 'pendiente_imprenta';

-- Lo ya emitido sin internet salió del talonario
select set_config('cuadre.imprenta', 'si', false);
update documentos set medio = 'talonario' where origen = 'contingencia' and medio <> 'talonario';
select set_config('cuadre.imprenta', '', false);

-- El medio lo decide la empresa, no quien emite: así vender(), emitir_nota(),
-- crear_orden() y cobrar_membresia() no cambian.
create or replace function documentos_medio() returns trigger
language plpgsql security definer set search_path = public as $$
declare emp empresas;
begin
  if new.origen = 'contingencia' then
    new.medio := 'talonario'; new.maquina_registro := null; return new;
  end if;
  select * into emp from empresas where id = new.empresa_id;
  if emp.medio_factura = 'maquina' then
    new.medio := 'maquina'; new.maquina_registro := emp.maquina_registro;
  else
    new.medio := 'imprenta'; new.maquina_registro := null;
  end if;
  new.numero_fiscal := null; new.reporte_z := null;
  return new;
end $$;
revoke all on function documentos_medio() from public, anon, authenticated;
create or replace trigger documentos_medio before insert on documentos for each row execute function documentos_medio();

-- ---------- Talonario de imprenta autorizada: cada número una sola vez ----------
create table if not exists talonario_usados (
  empresa_id   uuid not null references empresas,
  numero       bigint not null check (numero > 0),
  documento_id uuid not null references documentos,
  uso          text not null check (uso in ('sin internet', 'falla de la máquina')),
  en           timestamptz not null default now(),
  primary key (empresa_id, numero)
);
alter table talonario_usados enable row level security;
create policy ver on talonario_usados for select using (es_miembro(empresa_id));
revoke insert, update, delete on talonario_usados from anon, authenticated;

insert into talonario_usados (empresa_id, numero, documento_id, uso, en)
select empresa_id, numero, id, 'sin internet', fecha from documentos where origen = 'contingencia'
on conflict do nothing;

create or replace function talonario_marcar() returns trigger
language plpgsql security definer set search_path = public as $$
declare otro uuid;
begin
  select documento_id into otro from talonario_usados where empresa_id = new.empresa_id and numero = new.numero;
  if otro is not null then
    -- Sin la palabra «duplicate»: la caja no debe tomarla como una venta que ya había subido
    raise exception 'El número % del talonario ya se usó en otra factura: revisa el talonario', new.numero;
  end if;
  insert into talonario_usados (empresa_id, numero, documento_id, uso) values (new.empresa_id, new.numero, new.id, 'sin internet');
  return new;
end $$;
revoke all on function talonario_marcar() from public, anon, authenticated;
create or replace trigger talonario_marcar after insert on documentos for each row when (new.origen = 'contingencia')
  execute function talonario_marcar();

-- ---------- Libro de control de la máquina (Providencia 0141) ----------
create table if not exists maquina_eventos (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references empresas,
  maquina_registro text,
  fecha            date not null default (now() at time zone 'America/Caracas')::date,
  tipo             text not null check (tipo in ('instalacion', 'inspeccion', 'reparacion', 'falla', 'cambio de precinto', 'otro')),
  detalle          text not null check (length(trim(detalle)) > 0 and detalle !~ '[<>]'),
  tecnico          text check (tecnico is null or tecnico !~ '[<>]'),
  creado_por       uuid references auth.users default auth.uid(),
  creado_en        timestamptz not null default now()
);
create index if not exists maquina_eventos_empresa on maquina_eventos (empresa_id, fecha);
alter table maquina_eventos enable row level security;
create policy ver on maquina_eventos for select using (es_miembro(empresa_id));
create policy anotar on maquina_eventos for insert
  with check (tiene_rol(empresa_id, '{dueno,gerente,regente,cajero}') and creado_por = auth.uid());
revoke update, delete on maquina_eventos from anon, authenticated;
create trigger auditar after insert on maquina_eventos for each row execute function auditar();

-- ---------- La impresora imprimió: se guarda su número ----------
-- La caja llama aquí con lo que devolvió el agente local. El número no se
-- repite (índice único) y el Reporte Z del día lo compara con la máquina.
create or replace function registrar_maquina(p_doc uuid, p_numero bigint, p_registro text, p_resp jsonb default '{}')
returns documentos
language plpgsql security definer set search_path = public as $$
declare d documentos;
begin
  select * into d from documentos where id = p_doc for update;
  if d.id is null or not tiene_rol(d.empresa_id, '{dueno,gerente,regente,cajero}') then
    raise exception 'Documento no encontrado';
  end if;
  if d.medio <> 'maquina' then raise exception 'Ese documento no se factura por máquina fiscal'; end if;
  if d.estado <> 'pendiente_imprenta' then raise exception 'Ese documento ya quedó impreso'; end if;
  if p_numero is null or p_numero <= 0 then raise exception 'La impresora no devolvió un número válido'; end if;
  if upper(trim(coalesce(p_registro, ''))) is distinct from d.maquina_registro then
    raise exception 'El documento salió por la máquina % y este negocio usa la %', coalesce(p_registro, '(sin registro)'), d.maquina_registro;
  end if;
  if exists (select 1 from documentos where empresa_id = d.empresa_id and maquina_registro = d.maquina_registro
             and tipo = d.tipo and numero_fiscal = p_numero) then
    raise exception 'El número % de la máquina ya está en otra factura', p_numero;
  end if;
  perform set_config('cuadre.imprenta', 'si', true);
  update documentos set numero_fiscal = p_numero, estado = 'emitido', imprenta_resp = coalesce(p_resp, '{}')
    where id = p_doc returning * into d;
  perform set_config('cuadre.imprenta', '', true);
  return d;
end $$;
revoke all on function registrar_maquina(uuid, bigint, text, jsonb) from public, anon;
grant execute on function registrar_maquina(uuid, bigint, text, jsonb) to authenticated;

-- ---------- La impresora falló: la factura sale del talonario ----------
create or replace function registrar_falla_maquina(p_doc uuid, p_numero bigint, p_motivo text default 'Falla de la impresora fiscal')
returns documentos
language plpgsql security definer set search_path = public as $$
declare d documentos; emp empresas;
begin
  select * into d from documentos where id = p_doc for update;
  if d.id is null or not tiene_rol(d.empresa_id, '{dueno,gerente,regente,cajero}') then
    raise exception 'Documento no encontrado';
  end if;
  if d.medio <> 'maquina' or d.estado <> 'pendiente_imprenta' then
    raise exception 'Solo una factura que la máquina no imprimió pasa al talonario';
  end if;
  if coalesce(trim(p_motivo), '') = '' or p_motivo ~ '[<>]' then raise exception 'Escribe qué le pasó a la impresora'; end if;
  select * into emp from empresas where id = d.empresa_id;
  if p_numero is null or p_numero not between coalesce(emp.talonario_desde, 0) and coalesce(emp.talonario_hasta, -1) then
    raise exception 'El número % no está en el talonario de contingencia', p_numero;
  end if;
  if exists (select 1 from talonario_usados where empresa_id = d.empresa_id and numero = p_numero) then
    raise exception 'El número % del talonario ya se usó en otra factura: revisa el talonario', p_numero;
  end if;
  insert into talonario_usados (empresa_id, numero, documento_id, uso) values (d.empresa_id, p_numero, d.id, 'falla de la máquina');
  perform set_config('cuadre.imprenta', 'si', true);
  update documentos set medio = 'talonario', numero_control = emp.talonario_serie || '-' || lpad(p_numero::text, 8, '0'),
         estado = 'emitido', imprenta_resp = jsonb_build_object('falla_maquina', p_motivo)
    where id = p_doc returning * into d;
  perform set_config('cuadre.imprenta', '', true);
  insert into maquina_eventos (empresa_id, maquina_registro, tipo, detalle)
  values (d.empresa_id, emp.maquina_registro, 'falla', p_motivo || ' · factura del talonario ' || d.numero_control);
  return d;
end $$;
revoke all on function registrar_falla_maquina(uuid, bigint, text) from public, anon;
grant execute on function registrar_falla_maquina(uuid, bigint, text) to authenticated;

-- ---------- Lo que la base sabe de la jornada (para el Reporte X y antes del Z) ----------
create or replace function jornada_maquina(p_empresa uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare emp empresas; r jsonb;
begin
  if not es_miembro(p_empresa) then raise exception 'Empresa no encontrada'; end if;
  select * into emp from empresas where id = p_empresa;
  select jsonb_build_object(
    'registro', emp.maquina_registro,
    'fac_desde', min(numero_fiscal) filter (where tipo = 'FAC'), 'fac_hasta', max(numero_fiscal) filter (where tipo = 'FAC'),
    'cant_fac', count(*) filter (where tipo = 'FAC'),
    'nc_desde', min(numero_fiscal) filter (where tipo = 'NC'), 'nc_hasta', max(numero_fiscal) filter (where tipo = 'NC'),
    'cant_nc', count(*) filter (where tipo = 'NC'),
    'nd_desde', min(numero_fiscal) filter (where tipo = 'ND'), 'nd_hasta', max(numero_fiscal) filter (where tipo = 'ND'),
    'cant_nd', count(*) filter (where tipo = 'ND'),
    'exento', coalesce(sum(case when tipo = 'NC' then -base_exenta else base_exenta end), 0),
    'base_general', coalesce(sum(case when tipo = 'NC' then -base_general else base_general end), 0),
    'iva_general', coalesce(sum(case when tipo = 'NC' then -iva_general else iva_general end), 0),
    'base_reducida', coalesce(sum(case when tipo = 'NC' then -base_reducida else base_reducida end), 0),
    'iva_reducida', coalesce(sum(case when tipo = 'NC' then -iva_reducida else iva_reducida end), 0),
    'total', coalesce(sum(case when tipo = 'NC' then -total else total end), 0),
    'pendientes', (select count(*) from documentos where empresa_id = p_empresa and medio = 'maquina' and estado = 'pendiente_imprenta'),
    'ultimo_z', (select jsonb_build_object('numero', numero, 'fecha', fecha, 'dia', dia) from reportes_z
                  where empresa_id = p_empresa and maquina_registro = emp.maquina_registro order by numero desc limit 1))
  into r
  from documentos
  where empresa_id = p_empresa and medio = 'maquina' and maquina_registro = emp.maquina_registro
    and estado = 'emitido' and numero_fiscal is not null and reporte_z is null;
  return r;
end $$;

-- ---------- Reporte Z ----------
create table if not exists reportes_z (
  id               bigint generated always as identity primary key,
  empresa_id       uuid not null references empresas,
  maquina_registro text not null,
  numero           int not null check (numero > 0),
  fecha            timestamptz not null default now(),
  dia              date not null,
  -- Lo que dice la máquina
  fac_desde bigint, fac_hasta bigint, cant_fac int not null default 0,
  nc_desde  bigint, nc_hasta  bigint, cant_nc  int not null default 0,
  nd_desde  bigint, nd_hasta  bigint, cant_nd  int not null default 0,
  exento        numeric(16,2) not null default 0,
  base_general  numeric(16,2) not null default 0,
  iva_general   numeric(16,2) not null default 0,
  base_reducida numeric(16,2) not null default 0,
  iva_reducida  numeric(16,2) not null default 0,
  total         numeric(16,2) not null,          -- neto: facturas + notas de débito − notas de crédito
  -- Lo que dice la base de esas mismas facturas
  sis_cant_fac int, sis_cant_nc int, sis_cant_nd int, sis_total numeric(16,2),
  cuadra       boolean,
  datos        jsonb,                            -- respuesta completa del agente
  creado_por   uuid not null references auth.users default auth.uid(),
  unique (empresa_id, maquina_registro, numero),
  unique (empresa_id, maquina_registro, dia)
);
alter table reportes_z enable row level security;
create policy ver on reportes_z for select using (es_miembro(empresa_id));
revoke insert, update, delete on reportes_z from anon, authenticated;
create trigger auditar after insert on reportes_z for each row execute function auditar();

-- Liga al Z las facturas y notas de su rango y compara con lo que dijo la máquina.
-- Se vuelve a correr cuando sube una venta que se imprimió sin internet.
create or replace function z_cuadrar(p_z bigint) returns reportes_z
language plpgsql security definer set search_path = public as $$
declare z reportes_z; n_fac int; n_nc int; n_nd int; t numeric;
begin
  select * into z from reportes_z where id = p_z;
  perform set_config('cuadre.imprenta', 'si', true);
  update documentos set reporte_z = z.numero
   where empresa_id = z.empresa_id and medio = 'maquina' and maquina_registro = z.maquina_registro
     and estado = 'emitido' and reporte_z is null and numero_fiscal is not null
     and ((tipo = 'FAC' and numero_fiscal between z.fac_desde and z.fac_hasta)
       or (tipo = 'NC'  and numero_fiscal between z.nc_desde  and z.nc_hasta)
       or (tipo = 'ND'  and numero_fiscal between z.nd_desde  and z.nd_hasta));
  perform set_config('cuadre.imprenta', '', true);
  select count(*) filter (where tipo = 'FAC'), count(*) filter (where tipo = 'NC'), count(*) filter (where tipo = 'ND'),
         coalesce(sum(case when tipo = 'NC' then -total else total end), 0)
    into n_fac, n_nc, n_nd, t
    from documentos where empresa_id = z.empresa_id and maquina_registro = z.maquina_registro and reporte_z = z.numero and medio = 'maquina';
  update reportes_z set sis_cant_fac = n_fac, sis_cant_nc = n_nc, sis_cant_nd = n_nd, sis_total = t,
         cuadra = (n_fac = z.cant_fac and n_nc = z.cant_nc and n_nd = z.cant_nd and abs(t - z.total) < 0.05)
   where id = z.id returning * into z;
  return z;
end $$;
revoke all on function z_cuadrar(bigint) from public, anon, authenticated;

-- p_z: {"numero","fac_desde","fac_hasta","cant_fac","nc_desde","nc_hasta","cant_nc","nd_desde","nd_hasta","cant_nd",
--       "exento","base_general","iva_general","base_reducida","iva_reducida","total", "fecha"}  (montos en Bs)
--   "fecha" solo si el Z se imprimió sin internet y sube después (hasta 3 días atrás).
create or replace function registrar_reporte_z(p_empresa uuid, p_registro text, p_z jsonb) returns reportes_z
language plpgsql security definer set search_path = public as $$
declare emp empresas; z reportes_z; prev reportes_z; quien text; f timestamptz; hoy date;
  num_txt text := nullif(p_z->>'numero', '');
begin
  select * into emp from empresas where id = p_empresa and activo;
  if emp.id is null or not tiene_rol(p_empresa, '{dueno,gerente,regente,cajero}') then raise exception 'No tienes permiso para el Reporte Z'; end if;
  if emp.medio_factura <> 'maquina' then raise exception 'Este negocio no factura por máquina fiscal'; end if;
  if upper(trim(coalesce(p_registro, ''))) is distinct from emp.maquina_registro then
    raise exception 'El Reporte Z salió por la máquina % y este negocio usa la %', coalesce(p_registro, '(sin registro)'), emp.maquina_registro;
  end if;
  if num_txt is null or num_txt !~ '^[0-9]+$' or num_txt::int <= 0 then raise exception 'La impresora no devolvió el número del Reporte Z'; end if;
  if (p_z->>'total') is null then raise exception 'La impresora no devolvió el total del Reporte Z'; end if;
  f := coalesce(nullif(p_z->>'fecha', '')::timestamptz, now());
  if f > now() + interval '5 minutes' or f < now() - interval '3 days' then raise exception 'Fecha del Reporte Z inválida'; end if;
  hoy := (f at time zone 'America/Caracas')::date;

  -- Si ya subió (se reintentó al volver internet), se devuelve el mismo
  select * into prev from reportes_z where empresa_id = p_empresa and maquina_registro = emp.maquina_registro and numero = num_txt::int;
  if prev.id is not null then return prev; end if;
  select * into prev from reportes_z where empresa_id = p_empresa and maquina_registro = emp.maquina_registro and dia = hoy;
  if prev.id is not null then
    select nombre into quien from perfiles where user_id = prev.creado_por;
    raise exception 'El Reporte Z de hoy ya lo hizo % a las %', coalesce(quien, 'otro usuario'),
      to_char(prev.fecha at time zone 'America/Caracas', 'HH24:MI');
  end if;

  insert into reportes_z (empresa_id, maquina_registro, numero, fecha, dia, fac_desde, fac_hasta, cant_fac, nc_desde, nc_hasta, cant_nc,
                          nd_desde, nd_hasta, cant_nd, exento, base_general, iva_general, base_reducida, iva_reducida, total, datos)
  values (p_empresa, emp.maquina_registro, num_txt::int, f, hoy,
          nullif(p_z->>'fac_desde', '')::bigint, nullif(p_z->>'fac_hasta', '')::bigint, coalesce(nullif(p_z->>'cant_fac', '')::int, 0),
          nullif(p_z->>'nc_desde', '')::bigint, nullif(p_z->>'nc_hasta', '')::bigint, coalesce(nullif(p_z->>'cant_nc', '')::int, 0),
          nullif(p_z->>'nd_desde', '')::bigint, nullif(p_z->>'nd_hasta', '')::bigint, coalesce(nullif(p_z->>'cant_nd', '')::int, 0),
          coalesce((p_z->>'exento')::numeric, 0), coalesce((p_z->>'base_general')::numeric, 0), coalesce((p_z->>'iva_general')::numeric, 0),
          coalesce((p_z->>'base_reducida')::numeric, 0), coalesce((p_z->>'iva_reducida')::numeric, 0), (p_z->>'total')::numeric, p_z)
  returning * into z;
  return z_cuadrar(z.id);
end $$;
revoke all on function registrar_reporte_z(uuid, text, jsonb) from public, anon;
grant execute on function registrar_reporte_z(uuid, text, jsonb) to authenticated;

-- ---------- Sin internet, la máquina sigue facturando ----------
-- La impresora va por cable a la caja: sin internet imprime igual y la venta
-- queda guardada en el equipo. Al volver la conexión sube por aquí con el
-- número que ya imprimió la máquina, la fecha y la tasa de ese momento.
-- Si se reintenta, devuelve la misma factura (no la repite).
create or replace function vender_impresa(p_empresa uuid, p_cliente jsonb, p_items jsonb, p_pagos jsonb,
                                          p_fecha timestamptz, p_numero bigint, p_registro text, p_resp jsonb default '{}')
returns documentos
language plpgsql security definer set search_path = public as $$
declare emp empresas; d documentos; zid bigint;
begin
  select * into emp from empresas where id = p_empresa and activo;
  if emp.id is null or not tiene_rol(p_empresa, '{dueno,gerente,regente,cajero}') then raise exception 'Tu usuario no vende'; end if;
  if emp.medio_factura <> 'maquina' then raise exception 'Este negocio no factura por máquina fiscal'; end if;
  if upper(trim(coalesce(p_registro, ''))) is distinct from emp.maquina_registro then
    raise exception 'La factura salió por la máquina % y este negocio usa la %', coalesce(p_registro, '(sin registro)'), emp.maquina_registro;
  end if;
  if p_numero is null or p_numero <= 0 then raise exception 'La impresora no devolvió un número válido'; end if;
  if p_fecha is null or p_fecha > now() + interval '5 minutes' or p_fecha < now() - interval '30 days' then
    raise exception 'Fecha de la venta sin conexión inválida';
  end if;
  select * into d from documentos where empresa_id = p_empresa and maquina_registro = emp.maquina_registro and tipo = 'FAC' and numero_fiscal = p_numero;
  if d.id is not null then
    if d.fecha = p_fecha and d.cliente_rif = upper(trim(p_cliente->>'rif')) then return d; end if;   -- ya había subido
    raise exception 'El número % de la máquina ya está en otra factura', p_numero;
  end if;

  -- vender() hace todo lo demás (inventario, permisos, precio con la tolerancia de sin internet);
  -- la tasa es la del día en que se imprimió
  perform set_config('cuadre.impresa', 'si', true);
  perform set_config('cuadre.fecha', p_fecha::text, true);
  d := vender(p_empresa, p_cliente, p_items, p_pagos);
  perform set_config('cuadre.impresa', '', true);
  perform set_config('cuadre.fecha', '', true);

  perform set_config('cuadre.imprenta', 'si', true);
  update documentos set numero_fiscal = p_numero, estado = 'emitido', fecha = p_fecha,
         imprenta_resp = coalesce(p_resp, '{}') || '{"sin_internet":true}'
   where id = d.id returning * into d;
  perform set_config('cuadre.imprenta', '', true);

  -- Si el Z de ese día ya subió, la factura entra en él
  select id into zid from reportes_z where empresa_id = p_empresa and maquina_registro = emp.maquina_registro
     and p_numero between fac_desde and fac_hasta;
  if zid is not null then perform z_cuadrar(zid); select * into d from documentos where id = d.id; end if;
  return d;
end $$;
revoke all on function vender_impresa(uuid, jsonb, jsonb, jsonb, timestamptz, bigint, text, jsonb) from public, anon;
grant execute on function vender_impresa(uuid, jsonb, jsonb, jsonb, timestamptz, bigint, text, jsonb) to authenticated;

-- vender(): igual que en la 0018, con un cambio: una venta que la máquina ya
-- imprimió sin internet (vender_impresa) acepta el precio que tenía la caja,
-- con el mismo piso del 80 % que la venta del talonario.
create or replace function vender(p_empresa uuid, p_cliente jsonb, p_items jsonb, p_pagos jsonb default '[]',
                                  p_origen origen_doc default 'sistema', p_numero bigint default null, p_fecha timestamptz default null)
returns documentos
language plpgsql security definer set search_path = public as $$
declare
  it jsonb; pr productos; lt lotes; d documentos;
  lineas jsonb := '[]'; resta numeric; toma numeric; pu numeric; ok boolean;
  libre boolean := p_origen = 'contingencia' or coalesce(current_setting('cuadre.impresa', true), '') = 'si';
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
    -- Sin internet vale el precio que tenía la caja, pero nunca por debajo del 80 % del precio vigente
    if not ok and (not libre or pu < round(0.8 * least(pr.precio, coalesce((select min(precio) from lotes where producto_id = pr.id and cantidad > 0 and precio is not null), pr.precio)), 2)) then
      raise exception 'El precio de % cambió. Actualiza la caja', pr.nombre;
    end if;
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

revoke all on function jornada_maquina(uuid) from public, anon;
grant execute on function jornada_maquina(uuid) to authenticated;

-- ---------- Libro de ventas con máquina fiscal ----------
-- Mismas columnas de antes (en el mismo orden) y al final: medio, número fiscal,
-- registro de la máquina, Reporte Z y el rango de números del renglón del Z.
create or replace view libro_ventas with (security_invoker = true) as
select d.empresa_id, date_trunc('month', d.fecha)::date as mes, d.fecha::date as fecha,
       d.tipo, d.numero, d.numero_control, d.serie, d.origen,
       a.numero as afecta_numero, d.cliente_rif, d.cliente_nombre,
       s * d.total as total, s * d.base_exenta as exento,
       s * d.base_general as base_general, s * d.iva_general as iva_general,
       s * d.base_reducida as base_reducida, s * d.iva_reducida as iva_reducida,
       s * d.igtf as igtf, d.tasa,
       d.medio, d.numero_fiscal, d.maquina_registro, d.reporte_z,
       null::bigint as desde, null::bigint as hasta
from documentos d
left join documentos a on a.id = d.afecta_id
cross join lateral (select case when d.tipo = 'NC' then -1 else 1 end as s) x
where d.estado <> 'rechazado'
  -- Las de consumidor final ya cerradas en un Z van en el renglón del Z
  and not (d.medio = 'maquina' and d.tipo = 'FAC' and d.reporte_z is not null
           and d.cliente_rif !~ '^[JGVEP]-[0-9]{8}-[0-9]$')
union all
select z.empresa_id, date_trunc('month', z.dia)::date, z.dia,
       'FAC'::tipo_doc, z.numero::bigint, null::text, ''::text, 'sistema'::origen_doc,
       null::bigint, '—', 'Consumidor final · Reporte Z N.° ' || lpad(z.numero::text, 4, '0'),
       sum(d.total), sum(d.base_exenta), sum(d.base_general), sum(d.iva_general),
       sum(d.base_reducida), sum(d.iva_reducida), sum(d.igtf), min(d.tasa)::numeric(14,4),
       'maquina', null::bigint, z.maquina_registro, z.numero,
       min(d.numero_fiscal), max(d.numero_fiscal)
from reportes_z z
join documentos d on d.empresa_id = z.empresa_id and d.maquina_registro = z.maquina_registro
                 and d.reporte_z = z.numero and d.medio = 'maquina' and d.tipo = 'FAC'
                 and d.estado <> 'rechazado' and d.cliente_rif !~ '^[JGVEP]-[0-9]{8}-[0-9]$'
group by z.id, z.empresa_id, z.dia, z.numero, z.maquina_registro;
