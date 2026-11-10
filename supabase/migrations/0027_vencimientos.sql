-- =====================================================================
-- Cuadre · Migración 0027: vencimientos
--
-- En la práctica del 10 nov, al recibir una compra el año del vencimiento
-- quedó en un solo dígito (0002, 0007): la pantalla se repintaba con cada
-- tecla. La pantalla ya se corrigió; esto es lo que la base hace cumplir:
--
--   1. Un vencimiento tiene que ser una fecha razonable (2000 a 2100).
--   2. No se recibe por Compras mercancía que ya está vencida.
--   3. corregir_vencimiento(): cambia el vencimiento de un lote que se
--      escribió mal. Dueño, gerente, regente o almacén, con motivo; queda
--      un movimiento con la fecha anterior, la nueva y quién lo hizo.
-- =====================================================================

-- ---------- 1. Fechas razonables (los lotes viejos mal escritos se corrigen con la función) ----------
alter table lotes drop constraint if exists lotes_vence_razonable;
alter table lotes add constraint lotes_vence_razonable
  check (vence between date '2000-01-01' and date '2100-12-31') not valid;

-- ---------- 2. Recibir compra: nada vencido ----------
-- p_items: [{"producto_id", "lote", "vence", "cantidad", "costo"}]
create or replace function recibir_compra(p_empresa uuid, p_items jsonb, p_referencia text default null)
returns setof lotes
language plpgsql security definer set search_path = public as $$
declare it jsonb; lt lotes;
begin
  if not tiene_rol(p_empresa, '{dueno,gerente,regente,almacen}') then raise exception 'Tu usuario no recibe compras'; end if;
  perform set_config('cuadre.inventario', 'si', true);
  for it in select * from jsonb_array_elements(coalesce(p_items, '[]')) loop
    if not exists (select 1 from productos where id = (it->>'producto_id')::bigint and empresa_id = p_empresa) then
      raise exception 'Producto no encontrado';
    end if;
    if coalesce((it->>'cantidad')::numeric, 0) <= 0 or coalesce(trim(it->>'lote'), '') = '' or (it->>'vence') is null then
      raise exception 'Cada producto necesita lote, vencimiento y cantidad';
    end if;
    if (it->>'vence')::date < (now() at time zone 'America/Caracas')::date then
      raise exception 'El lote % de % ya está vencido (%): no se recibe mercancía vencida', upper(trim(it->>'lote')),
        (select nombre from productos where id = (it->>'producto_id')::bigint), to_char((it->>'vence')::date, 'DD/MM/YYYY');
    end if;
    insert into lotes (empresa_id, producto_id, lote, vence, cantidad, costo)
    values (p_empresa, (it->>'producto_id')::bigint, upper(trim(it->>'lote')), (it->>'vence')::date,
            (it->>'cantidad')::numeric, coalesce((it->>'costo')::numeric, 0))
    on conflict (producto_id, lote, vence) do update set cantidad = lotes.cantidad + excluded.cantidad, costo = excluded.costo
    returning * into lt;
    insert into movimientos (empresa_id, producto_id, lote_id, tipo, cantidad, costo, referencia)
    values (p_empresa, lt.producto_id, lt.id, 'compra', (it->>'cantidad')::numeric, lt.costo, p_referencia);
    return next lt;
  end loop;
  perform set_config('cuadre.inventario', '', true);
end $$;

-- ---------- 3. Corregir el vencimiento de un lote ----------
create or replace function corregir_vencimiento(p_lote bigint, p_vence date, p_motivo text)
returns lotes
language plpgsql security definer set search_path = public as $$
declare lt lotes; antes date; mot text := trim(coalesce(p_motivo, ''));
begin
  select * into lt from lotes where id = p_lote for update;
  if lt.id is null or not tiene_rol(lt.empresa_id, '{dueno,gerente,regente,almacen}') then raise exception 'Lote no encontrado'; end if;
  if p_vence is null or p_vence < date '2000-01-01' or p_vence > date '2100-12-31' then
    raise exception 'Escribe la fecha de vencimiento completa, con el año de cuatro cifras';
  end if;
  if length(mot) < 5 then raise exception 'Escribe por qué se corrige el vencimiento'; end if;
  if mot ~ '[<>]' then raise exception 'El motivo no puede llevar los signos < >'; end if;
  if p_vence = lt.vence then raise exception 'El lote ya tiene ese vencimiento'; end if;
  if exists (select 1 from lotes where producto_id = lt.producto_id and lote = lt.lote and vence = p_vence and id <> lt.id) then
    raise exception 'Ya hay otro lote % de ese producto con ese vencimiento', lt.lote;
  end if;
  antes := lt.vence;
  update lotes set vence = p_vence where id = lt.id returning * into lt;
  -- Sin unidades: solo deja el rastro (y, si es controlado, pasa a su libro)
  insert into movimientos (empresa_id, producto_id, lote_id, tipo, cantidad, costo, motivo)
  values (lt.empresa_id, lt.producto_id, lt.id, 'ajuste', 0, lt.costo,
          'Vencimiento corregido: ' || to_char(antes, 'DD/MM/YYYY') || ' → ' || to_char(p_vence, 'DD/MM/YYYY') || ' · ' || mot);
  return lt;
end $$;
revoke all on function corregir_vencimiento(bigint, date, text) from public, anon;
grant execute on function corregir_vencimiento(bigint, date, text) to authenticated;
