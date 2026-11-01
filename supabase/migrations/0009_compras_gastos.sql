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
