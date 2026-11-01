-- =====================================================================
-- Cuadre · Migración 0010: cuánto gana el negocio, por mes
--   ventas  = bases de las facturas (sin IVA ni IGTF) − notas de crédito + notas de débito, en dólares
--   costo   = costo de los lotes que salieron vendidos − lo devuelto
--   gastos  = gastos del mes que no están anulados
-- Solo lo ven el dueño y el gerente.
-- =====================================================================
create or replace function resumen_mensual(p_empresa uuid, p_meses int default 3)
returns table (mes date, ventas_usd numeric, costo_usd numeric, gastos_usd numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not tiene_rol(p_empresa, '{dueno,gerente}') then raise exception 'Solo el dueño ve las ganancias'; end if;
  return query
  with meses as (
    select (date_trunc('month', current_date) - (n || ' month')::interval)::date m from generate_series(0, greatest(p_meses, 1) - 1) n
  )
  select m,
    coalesce((select round(sum(case when d.tipo = 'NC' then -1 else 1 end * (d.base_exenta + d.base_general + d.base_reducida) / d.tasa), 2)
              from documentos d where d.empresa_id = p_empresa and d.estado <> 'rechazado' and date_trunc('month', d.fecha)::date = m), 0),
    coalesce((select round(sum(-mv.cantidad * coalesce(mv.costo, 0)), 2)
              from movimientos mv where mv.empresa_id = p_empresa and mv.tipo in ('venta', 'devolucion') and date_trunc('month', mv.fecha)::date = m), 0),
    coalesce((select sum(g.usd) from gastos g where g.empresa_id = p_empresa and not g.anulado and date_trunc('month', g.fecha)::date = m), 0)
  from meses order by m;
end $$;
revoke all on function resumen_mensual(uuid, int) from public, anon;
grant execute on function resumen_mensual(uuid, int) to authenticated;
