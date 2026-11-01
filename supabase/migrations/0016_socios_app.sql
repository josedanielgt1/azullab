-- =====================================================================
-- Cuadre · Migración 0016: la app del socio del CrossFit
--   * Rol «socio»: entra con su correo y clave y ve la pizarra del día, las
--     clases y sus propios datos. No ve facturas, cobros, otros socios ni
--     al equipo, y no factura.
--   * Reserva su clase y anota su resultado con funciones que solo tocan lo suyo.
--   (El rol nuevo se compara como texto para que este archivo corra completo
--    en una sola transacción del SQL Editor.)
-- =====================================================================
alter type rol_usuario add value if not exists 'socio';

alter table socios add column if not exists user_id uuid unique references auth.users on delete set null;

create or replace function es_socio(e uuid) returns boolean
language sql stable as $$ select coalesce(rol_en(e)::text = 'socio', false) $$;

create or replace function mi_socio(e uuid) returns bigint
language sql stable security definer set search_path = public as $$
  select id from socios where empresa_id = e and user_id = auth.uid()
$$;

-- El socio no factura
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
  if not es_miembro(p_empresa) or es_socio(p_empresa) or tiene_rol(p_empresa, '{almacen,coach,bioanalista}') then
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

-- Lo que el socio no ve
drop policy if exists ver on documentos;
create policy ver on documentos for select using (es_miembro(empresa_id) and not es_socio(empresa_id));
drop policy if exists ver on documento_lineas;
create policy ver on documento_lineas for select using (exists (select 1 from documentos d where d.id = documento_id and es_miembro(d.empresa_id) and not es_socio(d.empresa_id)));
drop policy if exists ver on documento_pagos;
create policy ver on documento_pagos for select using (exists (select 1 from documentos d where d.id = documento_id and es_miembro(d.empresa_id) and not es_socio(d.empresa_id)));
drop policy if exists ver on socios;
create policy ver on socios for select using (es_miembro(empresa_id) and (not es_socio(empresa_id) or user_id = auth.uid()));
drop policy if exists ver on miembros;
create policy ver on miembros for select using (empresa_id in (select mis_empresas()) and (not es_socio(empresa_id) or user_id = auth.uid()));
drop policy if exists ver on asistencias;
create policy ver on asistencias for select using (es_miembro(empresa_id) and (not es_socio(empresa_id) or socio_id = mi_socio(empresa_id)));
drop policy if exists marcar on asistencias;
create policy marcar on asistencias for insert with check (es_miembro(empresa_id) and not es_socio(empresa_id));
drop policy if exists editar on pizarras;
create policy editar on pizarras for update using (es_miembro(empresa_id) and not es_socio(empresa_id)) with check (es_miembro(empresa_id) and not es_socio(empresa_id));
drop policy if exists ver on colecciones;
create policy ver on colecciones for select using (es_miembro(empresa_id) and not es_socio(empresa_id) and (nombre not like 'privado\_%' or tiene_rol(empresa_id, '{dueno,gerente}')));
drop policy if exists editar on socios;
create policy editar on socios for update using (tiene_rol(empresa_id, '{dueno,gerente,atencion,coach}')) with check (tiene_rol(empresa_id, '{dueno,gerente,atencion,coach}'));

-- Reservar o soltar su cupo en una clase de hoy
create or replace function reservar_clase(p_empresa uuid, p_hora text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare yo bigint := mi_socio(p_empresa); c clases; pz pizarras; lista jsonb; ahora boolean;
begin
  if yo is null then raise exception 'Tu usuario no es socio de este box'; end if;
  if (select vence from socios where id = yo) < current_date then raise exception 'Tu membresía está vencida: renuévala en recepción'; end if;
  select * into c from clases where empresa_id = p_empresa and hora = p_hora and activo;
  if c.id is null then raise exception 'No hay clase a esa hora'; end if;
  insert into pizarras (empresa_id, fecha) values (p_empresa, current_date) on conflict do nothing;
  select * into pz from pizarras where empresa_id = p_empresa and fecha = current_date for update;
  lista := coalesce(pz.reservas->p_hora, '[]');
  ahora := not (lista @> to_jsonb(yo));
  if ahora then
    if jsonb_array_length(lista) >= c.cupo then raise exception 'La clase de las % está llena', p_hora; end if;
    lista := lista || to_jsonb(yo);
  else
    lista := (select coalesce(jsonb_agg(x), '[]') from jsonb_array_elements(lista) x where x <> to_jsonb(yo));
  end if;
  update pizarras set reservas = jsonb_set(coalesce(reservas, '{}'), array[p_hora], lista), actualizado = now() where empresa_id = p_empresa and fecha = current_date;
  return jsonb_build_object('reservado', ahora, 'cupos', c.cupo - jsonb_array_length(lista));
end $$;

-- Anotar su resultado del día
create or replace function anotar_resultado(p_empresa uuid, p_tiempo text, p_rx boolean) returns void
language plpgsql security definer set search_path = public as $$
declare yo bigint := mi_socio(p_empresa);
begin
  if yo is null then raise exception 'Tu usuario no es socio de este box'; end if;
  if p_tiempo !~ '^[0-9]{1,2}:[0-9]{2}$' then raise exception 'Escribe el tiempo así: 11:30'; end if;
  insert into pizarras (empresa_id, fecha) values (p_empresa, current_date) on conflict do nothing;
  update pizarras set resultados = (select coalesce(jsonb_agg(r), '[]') from jsonb_array_elements(resultados) r where (r->>'s')::bigint <> yo)
                                   || jsonb_build_object('s', yo, 't', p_tiempo, 'rx', p_rx), actualizado = now()
  where empresa_id = p_empresa and fecha = current_date;
end $$;
revoke all on function reservar_clase(uuid, text), anotar_resultado(uuid, text, boolean) from public, anon;
grant execute on function reservar_clase(uuid, text), anotar_resultado(uuid, text, boolean) to authenticated;
