-- =====================================================================
-- Cuadre · Migración 0015: cobros sin internet en el laboratorio y el CrossFit
--   crear_orden() y cobrar_membresia() aceptan, como vender(), el número del
--   talonario de contingencia y la fecha en que se cobró; la factura queda
--   con esa fecha y la tasa BCV de ese día.
-- =====================================================================

drop function if exists crear_orden(uuid, bigint, jsonb, text, boolean, jsonb, jsonb);
create or replace function crear_orden(p_empresa uuid, p_paciente bigint, p_items jsonb, p_medico text default null,
                                       p_urgente boolean default false, p_visita jsonb default '{}', p_pagos jsonb default '[]',
                                       p_origen origen_doc default 'sistema', p_numero bigint default null, p_fecha timestamptz default null)
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

  insert into ordenes (empresa_id, numero, paciente_id, items, total_usd, medico, urgente, visita, creado_en)
  values (p_empresa, 'L-' || lpad(contar(p_empresa, 'orden')::text, 4, '0'), pa.id, items, tot, nullif(p_medico, ''), coalesce(p_urgente, false), coalesce(p_visita, '{}'), coalesce(case when p_origen = 'contingencia' then p_fecha end, now()))
  returning * into o;
  if p_origen = 'contingencia' then
    if p_fecha is null or p_fecha > now() + interval '5 minutes' or p_fecha < now() - interval '30 days' then raise exception 'Fecha del cobro sin conexión inválida'; end if;
    perform set_config('cuadre.fecha', p_fecha::text, true);
  end if;
  d := emitir_documento(p_empresa, 'FAC', jsonb_build_object('rif', coalesce(nullif(pa.cedula, ''), 'V-00000000'), 'nombre', pa.nombre, 'tel', pa.telefono),
                        lineas, p_pagos, null, null, p_origen, p_numero, 'orden', null);
  perform set_config('cuadre.fecha', '', true);
  perform set_config('cuadre.orden', 'si', true);
  update ordenes set documento_id = d.id where id = o.id returning * into o;
  perform set_config('cuadre.orden', '', true);
  return jsonb_build_object('orden', to_jsonb(o), 'documento', to_jsonb(d));
end $$;
revoke all on function crear_orden(uuid, bigint, jsonb, text, boolean, jsonb, jsonb, origen_doc, bigint, timestamptz) from public, anon;
grant execute on function crear_orden(uuid, bigint, jsonb, text, boolean, jsonb, jsonb, origen_doc, bigint, timestamptz) to authenticated;

drop function if exists cobrar_membresia(uuid, bigint, bigint, text, boolean, jsonb);
create or replace function cobrar_membresia(p_empresa uuid, p_socio bigint, p_plan bigint, p_metodo text, p_divisa boolean default false,
                                            p_producto jsonb default null,
                                            p_origen origen_doc default 'sistema', p_numero bigint default null, p_fecha timestamptz default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare so socios; pl planes; pr productos_box; desde date; lineas jsonb; d documentos; m membresias; t numeric; tot numeric;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,atencion}') then raise exception 'Tu usuario no cobra'; end if;
  select * into so from socios where id = p_socio and empresa_id = p_empresa for update;
  select * into pl from planes where id = p_plan and empresa_id = p_empresa and activo;
  if so.id is null or pl.id is null then raise exception 'Socio o plan no encontrado'; end if;
  desde := greatest(coalesce(so.vence, coalesce(p_fecha::date, current_date)), coalesce(p_fecha::date, current_date));
  lineas := jsonb_build_array(jsonb_build_object('descripcion', pl.nombre || ' · desde el ' || to_char(desde, 'DD-MM-YYYY'),
                                                 'cantidad', 1, 'precio_usd', pl.precio, 'alicuota', 'G', 'ref', jsonb_build_object('plan_id', pl.id)));
  if p_producto is not null and p_producto->>'id' is not null then
    select * into pr from productos_box where id = (p_producto->>'id')::bigint and empresa_id = p_empresa and activo;
    if pr.id is null then raise exception 'Producto no encontrado'; end if;
    lineas := lineas || jsonb_build_object('descripcion', pr.nombre, 'cantidad', coalesce((p_producto->>'cantidad')::numeric, 1),
                                           'precio_usd', pr.precio, 'alicuota', 'G', 'ref', jsonb_build_object('producto_box_id', pr.id));
  end if;
  -- Para el pago: el total con IVA a la tasa del día
  t := tasa_del_dia(coalesce(p_fecha::date, current_date));
  if t is null then raise exception 'No hay tasa BCV cargada'; end if;
  select sum(round(round((l->>'precio_usd')::numeric * t, 2) * (l->>'cantidad')::numeric, 2)) into tot from jsonb_array_elements(lineas) l;
  tot := tot + round(tot * (select iva_general from empresas where id = p_empresa) / 100, 2);
  if p_origen = 'contingencia' then
    if p_fecha is null or p_fecha > now() + interval '5 minutes' or p_fecha < now() - interval '30 days' then raise exception 'Fecha del cobro sin conexión inválida'; end if;
    perform set_config('cuadre.fecha', p_fecha::text, true);
  end if;
  d := emitir_documento(p_empresa, 'FAC', jsonb_build_object('rif', so.cedula, 'nombre', so.nombre, 'tel', so.telefono), lineas,
                        jsonb_build_array(jsonb_build_object('metodo', p_metodo, 'monto_bs', tot, 'divisa', coalesce(p_divisa, false))),
                        null, null, p_origen, p_numero, 'membresia', null);
  perform set_config('cuadre.fecha', '', true);
  insert into membresias (empresa_id, socio_id, plan_id, desde, hasta, vence_antes, precio_usd, metodo, documento_id)
  values (p_empresa, so.id, pl.id, desde, desde + pl.dias, so.vence, pl.precio, p_metodo, d.id) returning * into m;
  update socios set plan_id = pl.id, vence = m.hasta where id = so.id returning * into so;
  return jsonb_build_object('membresia', to_jsonb(m), 'documento', to_jsonb(d), 'socio', to_jsonb(so));
end $$;
revoke all on function cobrar_membresia(uuid, bigint, bigint, text, boolean, jsonb, origen_doc, bigint, timestamptz) from public, anon;
grant execute on function cobrar_membresia(uuid, bigint, bigint, text, boolean, jsonb, origen_doc, bigint, timestamptz) to authenticated;
