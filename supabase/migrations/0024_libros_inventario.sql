-- =====================================================================
-- Cuadre · Migración 0024: registro de inventario real y notas de crédito de droguería
--
--   1. registro_inventario(): el registro del mes que pide el art. 177 del
--      Reglamento de la Ley de ISLR, por producto, en unidades y en valor,
--      armado SOLO con los movimientos reales de la base:
--        inicial + compras + devoluciones de clientes − ventas − retiros
--        − devoluciones a la droguería ± ajustes por conteo = final.
--      (Antes la pantalla mostraba cifras de muestra de la maqueta.)
--   2. nota_compra(): la nota de crédito que manda la droguería. Entra al
--      Libro de Compras restando, baja lo que se le debe a esa factura y,
--      si es por devolución de mercancía, saca los productos de sus lotes.
-- =====================================================================

-- ---------- 1. Registro de inventario del mes (art. 177) ----------
-- p_mes: cualquier día del mes (por defecto, el mes de hoy en Caracas).
-- Las cantidades van en unidades; los valores en dólares al costo de cada
-- lote y en bolívares con la tasa BCV del último día del mes (o de hoy).
create or replace function registro_inventario(p_empresa uuid, p_mes date default null)
returns table (producto_id bigint, codigo text, nombre text, controlado boolean,
               inicial numeric, compras numeric, devoluciones numeric, ventas numeric,
               retiros numeric, devoluciones_proveedor numeric, ajustes numeric, final numeric,
               valor_inicial_usd numeric, valor_final_usd numeric, costo_usd numeric, tasa numeric, valor_final_bs numeric)
language plpgsql stable security definer set search_path = public as $$
declare
  mes date := date_trunc('month', coalesce(p_mes, (now() at time zone 'America/Caracas')::date))::date;
  desde timestamptz; hasta timestamptz; t numeric;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,regente,almacen}') then raise exception 'No tienes permiso para ver el registro de inventario'; end if;
  desde := mes::timestamp at time zone 'America/Caracas';
  hasta := (mes + interval '1 month')::timestamp at time zone 'America/Caracas';
  t := tasa_del_dia(least((mes + interval '1 month' - interval '1 day')::date, (now() at time zone 'America/Caracas')::date));
  return query
  with m as (
    select mv.producto_id, mv.tipo, mv.cantidad, coalesce(mv.costo, 0) costo, mv.fecha,
           (mv.tipo = 'salida' and mv.motivo ilike 'Devolución a droguería%') a_proveedor
    from movimientos mv where mv.empresa_id = p_empresa and mv.fecha < hasta
  ), s as (
    select m.producto_id,
      coalesce(sum(m.cantidad) filter (where m.fecha < desde), 0) ini,
      coalesce(sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'compra'), 0) com,
      coalesce(sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'devolucion'), 0) dev,
      coalesce(-sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'venta'), 0) ven,
      coalesce(-sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'salida' and not m.a_proveedor), 0) ret,
      coalesce(-sum(m.cantidad) filter (where m.fecha >= desde and m.a_proveedor), 0) dpr,
      coalesce(sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'ajuste'), 0) aju,
      coalesce(sum(m.cantidad), 0) fin,
      coalesce(sum(m.cantidad * m.costo) filter (where m.fecha < desde), 0) vi,
      coalesce(sum(m.cantidad * m.costo), 0) vf
    from m group by m.producto_id
  )
  select p.id, p.codigo, p.nombre, p.controlado,
         s.ini, s.com, s.dev, s.ven, s.ret, s.dpr, s.aju, s.fin,
         round(s.vi, 2), round(s.vf, 2),
         case when s.fin > 0 then round(s.vf / s.fin, 4) else 0 end,
         t, round(s.vf * coalesce(t, 0), 2)
  from s join productos p on p.id = s.producto_id
  where s.ini <> 0 or s.fin <> 0 or s.com <> 0 or s.ven <> 0 or s.dev <> 0 or s.ret <> 0 or s.dpr <> 0 or s.aju <> 0
  order by p.nombre;
end $$;
revoke all on function registro_inventario(uuid, date) from public, anon;
grant execute on function registro_inventario(uuid, date) to authenticated;

-- ---------- 2. Nota de crédito de la droguería ----------
alter table compras
  add column if not exists afecta_id bigint references compras,
  add column if not exists motivo text;
alter table compras
  add constraint compras_nota check ((tipo = 'FAC') = (afecta_id is null)),
  add constraint compras_motivo_sin_codigo check (coalesce(motivo, '') !~ '[<>]');

-- p_nota:  {"numero","control","fecha","exento_usd","gravable_usd","motivo"}
-- p_items: [{"lote_id","cantidad"}]  lo que se le devolvió a la droguería (puede ir vacío:
--          por ejemplo, un descuento o un error de precio en la factura)
create or replace function nota_compra(p_factura bigint, p_nota jsonb, p_items jsonb default '[]')
returns compras
language plpgsql security definer set search_path = public as $$
declare f compras; n compras; ex numeric; gr numeric; iva numeric; tot numeric; resta numeric; saldo numeric; it jsonb; lt lotes;
  mot text := trim(coalesce(p_nota->>'motivo', ''));
begin
  select * into f from compras where id = p_factura and tipo = 'FAC';
  if f.id is null or not tiene_rol(f.empresa_id, '{dueno,gerente,regente,almacen}') then raise exception 'Factura de compra no encontrada'; end if;
  if coalesce(trim(p_nota->>'numero'), '') = '' then raise exception 'Escribe el número de la nota de crédito de la droguería'; end if;
  if mot = '' then raise exception 'Escribe el motivo de la nota de crédito'; end if;
  ex := round(coalesce((p_nota->>'exento_usd')::numeric, 0), 2);
  gr := round(coalesce((p_nota->>'gravable_usd')::numeric, 0), 2);
  if ex < 0 or gr < 0 or ex + gr <= 0 then raise exception 'La nota de crédito necesita un monto'; end if;
  iva := round(gr * 0.16, 2); tot := ex + gr + iva;
  -- No más de lo que queda de la factura (descontando las notas que ya tiene)
  select f.total_usd - coalesce(sum(total_usd), 0) into resta from compras where afecta_id = f.id and tipo = 'NC';
  if tot > resta + 0.004 then raise exception 'La nota (% $) pasa de lo que queda de la factura % (% $)', tot, f.numero, round(resta, 2); end if;

  insert into compras (empresa_id, proveedor_id, proveedor, rif, tipo, numero, control, fecha, tasa,
                       exento_usd, gravable_usd, iva_usd, total_usd, vence, pagado_usd, afecta_id, motivo)
  values (f.empresa_id, f.proveedor_id, f.proveedor, f.rif, 'NC', trim(p_nota->>'numero'), nullif(trim(p_nota->>'control'), ''),
          coalesce((p_nota->>'fecha')::date, (now() at time zone 'America/Caracas')::date),
          coalesce(tasa_del_dia(coalesce((p_nota->>'fecha')::date, current_date)), f.tasa),
          ex, gr, iva, tot, null, tot, f.id, mot)
  returning * into n;

  -- Lo que se le debía a la droguería por esa factura baja con la nota
  saldo := greatest(f.total_usd - f.pagado_usd, 0);
  if least(saldo, tot) > 0 then
    insert into pagos_compras (empresa_id, compra_id, monto_usd, metodo) values (f.empresa_id, f.id, least(saldo, tot), 'Nota de crédito ' || n.numero);
    update compras set pagado_usd = pagado_usd + least(saldo, tot) where id = f.id;
  end if;

  -- Mercancía devuelta: sale de su lote como devolución a la droguería
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]')) loop
    select * into lt from lotes where id = (it->>'lote_id')::bigint and empresa_id = f.empresa_id;
    if lt.id is null then raise exception 'Lote no encontrado'; end if;
    perform salida_inventario(lt.id, (it->>'cantidad')::numeric, 'Devolución a droguería · nota ' || n.numero || ' de ' || f.proveedor);
  end loop;
  return n;
end $$;
revoke all on function nota_compra(bigint, jsonb, jsonb) from public, anon;
grant execute on function nota_compra(bigint, jsonb, jsonb) to authenticated;
