-- Cuadre · Para pegar en el SQL Editor de Supabase (proyecto azullab) y darle Run una vez.
-- Migraciones desde la 0018. Generado por supabase/armar_sql_editor.sh; no editar a mano.

-- >>>>> migrations/0018_seguridad_ataque.sql
-- =====================================================================
-- Cuadre · Migración 0018: auditoría de seguridad (pruebas como atacante)
--   1. Nadie emite facturas directo: solo por vender(), crear_orden(),
--      cobrar_membresia() y emitir_nota(), que controlan precio, inventario
--      y permisos. (Antes un cajero podía facturar a cualquier precio.)
--   2. Solo la integración con la imprenta digital (clave de servicio)
--      registra el número de control. (Antes un cajero podía falsificarlo.)
--   3. La venta sin internet no baja del 80 % del precio vigente.
--   4. Los socios del CrossFit no escriben en las listas internas del equipo.
--   5. Un resultado del laboratorio solo se entrega si fue validado.
--   6. Nombres y textos libres no aceptan < ni > (nadie esconde código en un nombre).
-- =====================================================================

-- 1 y 2
revoke execute on function emitir_documento(uuid, tipo_doc, jsonb, jsonb, jsonb, uuid, text, origen_doc, bigint, text, uuid) from public, anon, authenticated;
revoke execute on function registrar_imprenta(uuid, text, estado_doc, jsonb) from public, anon, authenticated;
grant execute on function registrar_imprenta(uuid, text, estado_doc, jsonb) to service_role;

-- 3
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
    -- Sin internet vale el precio que tenía la caja, pero nunca por debajo del 80 % del precio vigente
    -- (antes, por esta vía se podía vender a cualquier precio)
    if not ok and (p_origen <> 'contingencia' or pu < round(0.8 * least(pr.precio, coalesce((select min(precio) from lotes where producto_id = pr.id and cantidad > 0 and precio is not null), pr.precio)), 2)) then
      raise exception 'El precio de % cambió. Actualiza la caja', pr.nombre;
    end if;
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

-- 4
drop policy if exists escribir on colecciones;
drop policy if exists editar on colecciones;
create policy escribir on colecciones for insert with check (tiene_rol(empresa_id, '{dueno,gerente}') or (nombre like 'equipo\_%' and es_miembro(empresa_id) and not es_socio(empresa_id)));
create policy editar on colecciones for update using (tiene_rol(empresa_id, '{dueno,gerente}') or (nombre like 'equipo\_%' and es_miembro(empresa_id) and not es_socio(empresa_id)))
  with check (tiene_rol(empresa_id, '{dueno,gerente}') or (nombre like 'equipo\_%' and es_miembro(empresa_id) and not es_socio(empresa_id)));

-- 5
create or replace function ordenes_entrega() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.estado = 'Entregado' and old.estado not in ('Validado', 'Entregado') then
    raise exception 'Solo se entrega un resultado validado por el bioanalista';
  end if;
  return new;
end $$;
revoke execute on function ordenes_entrega() from public, anon, authenticated;
drop trigger if exists ordenes_entrega on ordenes;
create trigger ordenes_entrega before update on ordenes for each row execute function ordenes_entrega();

-- 6 (not valid: lo ya guardado no se revisa; todo lo nuevo sí)
alter table perfiles    add constraint perfiles_sin_codigo    check (nombre !~ '[<>]') not valid;
alter table clientes    add constraint clientes_sin_codigo    check (nombre !~ '[<>]' and coalesce(direccion, '') !~ '[<>]') not valid;
alter table productos   add constraint productos_sin_codigo   check ((nombre || coalesce(principio_activo, '') || coalesce(laboratorio, '') || coalesce(presentacion, '') || coalesce(seccion, '')) !~ '[<>]') not valid;
alter table pacientes   add constraint pacientes_sin_codigo   check (nombre !~ '[<>]') not valid;
alter table socios      add constraint socios_sin_codigo      check (nombre !~ '[<>]') not valid;
alter table proveedores add constraint proveedores_sin_codigo check (nombre !~ '[<>]') not valid;
alter table medicos     add constraint medicos_sin_codigo     check (nombre !~ '[<>]') not valid;
alter table examenes    add constraint examenes_sin_codigo    check (nombre !~ '[<>]') not valid;
alter table planes      add constraint planes_sin_codigo      check (nombre !~ '[<>]') not valid;

-- >>>>> migrations/0019_igtf_contribuyente.sql
-- Cuadre · 0019 · IGTF solo para contribuyentes especiales
-- La Ley del IGTF pone a cobrar el 3 % por pagos en divisas a los sujetos pasivos especiales.
-- Los tres negocios del grupo son contribuyentes ordinarios: la caja no lo cobra y la factura
-- tampoco debe sumarlo (antes la base lo agregaba y el total no cuadraba con lo cobrado).
-- Si el SENIAT designa especial a un negocio, se pone igtf = 3 en su fila de empresas.
alter table empresas alter column igtf set default 0;
update empresas set igtf = 0 where igtf <> 0;
comment on column empresas.igtf is 'IGTF en %: 0 para contribuyente ordinario; 3 si el SENIAT lo designa contribuyente especial';

-- >>>>> Historial de migraciones
insert into supabase_migrations.schema_migrations (version, name) values
  ('0018', 'seguridad_ataque'),('0019', 'igtf_contribuyente')
on conflict (version) do nothing;
select 'Listo: migraciones aplicadas' as resultado;
