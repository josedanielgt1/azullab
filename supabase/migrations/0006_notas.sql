-- =====================================================================
-- Cuadre · Migración 0006: notas de crédito y débito desde la pantalla
--   * emitir_nota(): la nota cita su factura y toma de ella al cliente.
--   * Si es una devolución, lo devuelto vuelve a los lotes de los que salió
--     en esa venta (nunca más de lo vendido menos lo ya devuelto).
--   * Quién emite notas en cada negocio, como en las maquetas.
-- =====================================================================

-- p_lineas: [{"descripcion","cantidad","precio_bs","alicuota","ref":{"producto_id"}}]
create or replace function emitir_nota(p_factura uuid, p_tipo tipo_doc, p_lineas jsonb, p_motivo text, p_reintegrar boolean default false)
returns documentos
language plpgsql security definer set search_path = public as $$
declare f documentos; d documentos; l jsonb; m record; resta numeric; vendida numeric; devuelta numeric; toma numeric;
begin
  if p_tipo = 'FAC' then raise exception 'Usa vender() para facturar'; end if;
  select * into f from documentos where id = p_factura and tipo = 'FAC';
  if f.id is null or not es_miembro(f.empresa_id) then raise exception 'Factura no encontrada'; end if;
  d := emitir_documento(f.empresa_id, p_tipo, jsonb_build_object('rif', f.cliente_rif, 'nombre', f.cliente_nombre, 'dir', f.cliente_dir, 'tel', f.cliente_tel),
                        p_lineas, '[]', f.id, p_motivo);
  if p_tipo = 'NC' and p_reintegrar then
    perform set_config('cuadre.inventario', 'si', true);
    for l in select * from jsonb_array_elements(p_lineas) loop
      continue when l->'ref'->>'producto_id' is null;
      resta := (l->>'cantidad')::numeric;
      select coalesce(-sum(cantidad), 0) into vendida from movimientos
        where documento_id = f.id and producto_id = (l->'ref'->>'producto_id')::bigint and tipo = 'venta';
      select coalesce(sum(mv.cantidad), 0) into devuelta from movimientos mv join documentos n on n.id = mv.documento_id
        where n.afecta_id = f.id and mv.producto_id = (l->'ref'->>'producto_id')::bigint and mv.tipo = 'devolucion';
      if resta > vendida - devuelta then
        raise exception 'Se devuelven % y de esa venta quedan % por devolver', resta::float, (vendida - devuelta)::float;
      end if;
      -- A los lotes de esa venta, empezando por el último que se tomó
      for m in select lote_id, -sum(cantidad) q from movimientos
               where documento_id = f.id and producto_id = (l->'ref'->>'producto_id')::bigint and tipo = 'venta'
               group by lote_id order by max(id) desc loop
        exit when resta <= 0;
        toma := least(m.q, resta);
        update lotes set cantidad = cantidad + toma where id = m.lote_id;
        insert into movimientos (empresa_id, producto_id, lote_id, tipo, cantidad, costo, documento_id, motivo)
        select f.empresa_id, producto_id, id, 'devolucion', toma, costo, d.id, p_motivo from lotes where id = m.lote_id;
        resta := resta - toma;
      end loop;
    end loop;
    perform set_config('cuadre.inventario', '', true);
  end if;
  return d;
end $$;
revoke all on function emitir_nota(uuid, tipo_doc, jsonb, text, boolean) from public, anon;
grant execute on function emitir_nota(uuid, tipo_doc, jsonb, text, boolean) to authenticated;

update empresas set roles_notas = '{dueno,gerente,regente}'  where tipo = 'farmacia';
update empresas set roles_notas = '{dueno,gerente,atencion}' where tipo = 'laboratorio';
