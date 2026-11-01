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
