-- Cuadre · Para pegar en el SQL Editor de Supabase (proyecto azullab) y darle Run una vez.
-- Migraciones desde la 0028. Generado por supabase/armar_sql_editor.sh; no editar a mano.

-- >>>>> migrations/0028_tasa_factura.sql
-- =====================================================================
-- Cuadre · Migración 0028: la tasa de la factura de compra
--
-- La factura de la droguería trae impresa su propia tasa (la del día
-- anterior, la del euro...). Esa es la que vale para el Libro de Compras:
-- los bolívares del libro tienen que ser los del papel. Antes la base le
-- ponía siempre la tasa BCV del día de la factura y no dejaba escribir otra.
--
--   1. tasa_de_factura(): la que viene escrita o, si no, la BCV de ese día.
--      Frena un error de dedo (una tasa muy lejos de la BCV).
--   2. recibir_factura(), registrar_compra() y nota_compra() aceptan "tasa".
--      Si no es la BCV, la BCV de ese día queda guardada al lado (datos.tasa_bcv).
-- =====================================================================

-- ---------- 1. La tasa que vale para una factura de compra ----------
create or replace function tasa_de_factura(p_fecha date, p_tasa numeric)
returns numeric
language plpgsql stable security definer set search_path = public as $$
declare bcv numeric := tasa_del_dia(p_fecha);
begin
  if p_tasa is null then
    if bcv is null then raise exception 'No hay tasa BCV cargada: escribe la tasa que trae la factura'; end if;
    return bcv;
  end if;
  if p_tasa <= 0 then raise exception 'La tasa de la factura debe ser mayor que cero'; end if;
  if bcv is not null and (p_tasa < bcv * 0.6 or p_tasa > bcv * 1.6) then
    raise exception 'Revisa la tasa de la factura: % queda muy lejos de la BCV de ese día (%)', round(p_tasa, 2), round(bcv, 2);
  end if;
  return round(p_tasa, 4);
end $$;
revoke all on function tasa_de_factura(date, numeric) from public, anon;
grant execute on function tasa_de_factura(date, numeric) to authenticated;

-- ---------- 2. Factura de droguería (farmacia) ----------
-- p_factura: {"proveedor_id","numero","control","fecha","tasa"}   "tasa" es opcional
create or replace function recibir_factura(p_empresa uuid, p_factura jsonb, p_items jsonb)
returns compras
language plpgsql security definer set search_path = public as $$
declare pv proveedores; c compras; t numeric; bcv numeric; ex numeric := 0; gr numeric := 0; it jsonb; iv alicuota_iva; m numeric;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,regente,almacen}') then raise exception 'Tu usuario no recibe compras'; end if;
  select * into pv from proveedores where id = (p_factura->>'proveedor_id')::bigint and empresa_id = p_empresa;
  if pv.id is null then raise exception 'Escoge la droguería'; end if;
  if coalesce(trim(p_factura->>'numero'), '') = '' then raise exception 'Escribe el número de la factura del proveedor'; end if;
  bcv := tasa_del_dia(coalesce((p_factura->>'fecha')::date, current_date));
  t := tasa_de_factura(coalesce((p_factura->>'fecha')::date, current_date), nullif(trim(p_factura->>'tasa'), '')::numeric);
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]')) loop
    select iva into iv from productos where id = (it->>'producto_id')::bigint and empresa_id = p_empresa;
    m := round((it->>'cantidad')::numeric * coalesce((it->>'costo')::numeric, 0), 2);
    if iv = 'E' then ex := ex + m; else gr := gr + m; end if;
  end loop;
  insert into compras (empresa_id, proveedor_id, proveedor, rif, numero, control, fecha, tasa, exento_usd, gravable_usd, iva_usd, total_usd, vence, datos)
  values (p_empresa, pv.id, pv.nombre, pv.rif, trim(p_factura->>'numero'), nullif(trim(p_factura->>'control'), ''),
          coalesce((p_factura->>'fecha')::date, current_date), t, ex, gr, round(gr * 0.16, 2), ex + gr + round(gr * 0.16, 2),
          coalesce((p_factura->>'fecha')::date, current_date) + pv.credito_dias,
          case when bcv is distinct from t then jsonb_build_object('tasa_bcv', bcv) else '{}'::jsonb end)
  returning * into c;
  perform recibir_compra(p_empresa, p_items, pv.nombre || ' · factura ' || c.numero);
  return c;
end $$;

-- ---------- Factura de servicios y gastos (los tres negocios) ----------
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
  t := tasa_de_factura(f, nullif(trim(p_factura->>'tasa'), '')::numeric);
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

-- ---------- Nota de crédito de la droguería ----------
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
          case when nullif(trim(p_nota->>'tasa'), '') is not null
               then tasa_de_factura(coalesce((p_nota->>'fecha')::date, current_date), (p_nota->>'tasa')::numeric)
               else coalesce(tasa_del_dia(coalesce((p_nota->>'fecha')::date, current_date)), f.tasa) end,
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

-- >>>>> Historial de migraciones
insert into supabase_migrations.schema_migrations (version, name) values
  ('0028', 'tasa_factura')
on conflict (version) do nothing;
select 'Listo: migraciones aplicadas' as resultado;
