-- 0030 · El vuelto queda en la factura y se resta de la caja
--
-- Antes: si el cliente pagaba $20 por una venta de $12, la factura guardaba
-- «Efectivo USD $20» y el cierre de caja esperaba $20 en la gaveta. Al cajero
-- que daba bien el vuelto le faltaban $8; al que no lo daba, le cuadraba.
--
-- Ahora el vuelto es un renglón más de documento_pagos, con monto negativo y
-- la forma en que se entregó (efectivo en bolívares, efectivo en dólares,
-- pago móvil). Así cada forma de pago queda con lo que de verdad entró.
--   * documento_pagos.vuelto dice si el renglón es vuelto (monto negativo).
--   * El vuelto no puede pasar de lo que el cliente pagó de más.
--   * En la venta de la farmacia (vender), si el cliente pagó de más y no se
--     registró el vuelto, la factura no sale: primero el vuelto, después el ticket.
--   * El vuelto no cuenta para el IGTF ni cambia el total de la factura.
--
-- Una caja vieja (sin el paso del vuelto) que cobre de más recibe el aviso de
-- registrar el vuelto: hay que recargarla (Ctrl+Shift+R).

alter table documento_pagos drop constraint documento_pagos_monto_bs_check;
alter table documento_pagos add constraint documento_pagos_monto_bs_check check (monto_bs <> 0);
alter table documento_pagos add column vuelto boolean generated always as (monto_bs < 0) stored;
comment on column documento_pagos.vuelto is 'Vuelto entregado al cliente por esta forma de pago (monto negativo)';

-- emitir_documento(): igual que en la 0016, más el vuelto
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
  pag_bs numeric := 0; vto_bs numeric := 0; tol numeric; mp numeric;
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
    -- Un pago con monto negativo es vuelto: lo que la caja le devolvió al cliente por esa forma de pago
    for p in select * from jsonb_array_elements(coalesce(p_pagos, '[]')) loop
      mp := round((p->>'monto_bs')::numeric, 2);
      if mp is null or mp = 0 then raise exception 'Hay un pago sin monto'; end if;
      if coalesce(trim(p->>'metodo'), '') = '' then raise exception 'Hay un pago sin forma de pago'; end if;
      if mp < 0 then vto_bs := vto_bs - mp;
      else
        pag_bs := pag_bs + mp;
        if coalesce((p->>'divisa')::boolean, false) then div_bs := div_bs + mp; end if;
      end if;
    end loop;
    v_igtf := round(least(div_bs, tot) * emp.igtf / 100, 2);
    -- El vuelto se revisa en la venta que se está cobrando. Lo que ya se imprimió o se facturó sin
    -- internet sube como ocurrió. Tolerancia: un centavo de dólar, por el redondeo entre monedas.
    if p_origen = 'sistema' and coalesce(current_setting('cuadre.impresa', true), '') <> 'si' then
      tol := round(0.01 * t, 2) + 0.01;
      if vto_bs > greatest(pag_bs - tot, 0) + tol then
        raise exception 'El vuelto (Bs %) pasa de lo que el cliente pagó de más (Bs %)', vto_bs, greatest(pag_bs - tot, 0);
      end if;
      if p_ref_tipo = 'venta' and pag_bs - tot - vto_bs > tol then
        raise exception 'El cliente pagó Bs % de más: registra el vuelto antes de facturar', pag_bs - tot - vto_bs;
      end if;
    end if;
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
      values (d.id, trim(p->>'metodo'), round((p->>'monto_bs')::numeric, 2), coalesce((p->>'divisa')::boolean, false), p->>'referencia');
    end loop;
  end if;
  return d;
end $$;
