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
