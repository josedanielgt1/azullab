-- =====================================================================
-- Cuadre · Migración 0014: facturas de compra sin inventario
-- (laboratorio y CrossFit: reactivos, insumos, servicios, alquiler…)
--   * registrar_compra(): la factura del proveedor va al libro de compras
--     con su exento y su base gravable (IVA 16 %), y, si aplica, la
--     retención de ISLR que se le hizo.
--   * La misma factura del mismo proveedor no se registra dos veces.
-- =====================================================================
alter table compras add column if not exists datos jsonb not null default '{}';

-- p_factura: {"proveedor","rif","numero","control","fecha","exento_bs","gravable_bs","retencion":{"k","pn","comp"}}
create or replace function registrar_compra(p_empresa uuid, p_factura jsonb)
returns compras
language plpgsql security definer set search_path = public as $$
declare c compras; t numeric; f date; ex numeric; gr numeric; rif text;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente}') then raise exception 'Solo el dueño registra facturas de compra'; end if;
  if coalesce(trim(p_factura->>'proveedor'), '') = '' or coalesce(trim(p_factura->>'numero'), '') = '' then
    raise exception 'Escribe el proveedor y el número de la factura';
  end if;
  rif := upper(regexp_replace(coalesce(p_factura->>'rif', ''), '[.\s]', '', 'g'));
  rif := regexp_replace(rif, '^([JGVEP])-?([0-9]{8})-?([0-9])$', '\1-\2-\3');
  if rif <> '' and rif !~ '^[JGVEP]-[0-9]{8}-[0-9]$' then raise exception 'El RIF del proveedor debe quedar así: J-12345678-9'; end if;
  f := coalesce((p_factura->>'fecha')::date, current_date);
  t := tasa_del_dia(f);
  if t is null then raise exception 'No hay tasa BCV cargada'; end if;
  ex := coalesce((p_factura->>'exento_bs')::numeric, 0); gr := coalesce((p_factura->>'gravable_bs')::numeric, 0);
  if ex < 0 or gr < 0 or ex + gr = 0 then raise exception 'Escribe el monto exento o la base gravable'; end if;
  insert into compras (empresa_id, proveedor, rif, numero, control, fecha, tasa, exento_usd, gravable_usd, iva_usd, total_usd, pagado_usd, datos)
  values (p_empresa, trim(p_factura->>'proveedor'), nullif(rif, ''), trim(p_factura->>'numero'), nullif(trim(p_factura->>'control'), ''), f, t,
          round(ex / t, 2), round(gr / t, 2), round(gr * 0.16 / t, 2), round((ex + gr + round(gr * 0.16, 2)) / t, 2),
          round((ex + gr + round(gr * 0.16, 2)) / t, 2),   -- servicios y gastos: se registran ya pagados
          jsonb_build_object('exento_bs', ex, 'gravable_bs', gr, 'retencion', p_factura->'retencion'))
  returning * into c;
  return c;
end $$;
revoke all on function registrar_compra(uuid, jsonb) from public, anon;
grant execute on function registrar_compra(uuid, jsonb) to authenticated;
