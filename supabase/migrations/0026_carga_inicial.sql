-- =====================================================================
-- Cuadre · Migración 0026: carga inicial del inventario
--
-- Lo que ya está en los anaqueles el día que el negocio arranca con Cuadre
-- NO es una compra: no lleva factura de droguería, no va al Libro de
-- Compras y no deja deuda. Antes la única entrada era recibir_factura(),
-- así que cargar el anaquel obligaba a inventar una factura.
--
--   1. Movimiento «inicial»: entra a los lotes como inventario inicial.
--   2. carga_inicial(): crea los productos que falten y sus lotes, todo
--      junto (si un renglón está mal, no entra nada). Sirve para la carga
--      a mano y para la que viene de una hoja de Excel.
--   3. cerrar_carga_inicial(): el dueño la cierra cuando termina de
--      contar. Después de eso la mercancía solo entra con su factura.
--   4. registro_inventario() (art. 177): la carga inicial sale en la
--      columna «inicial», no en «compras».
--   5. Libro de controlados: la carga queda como «Inventario inicial».
-- =====================================================================

-- ---------- 1. El movimiento «inicial» ----------
alter table movimientos drop constraint if exists movimientos_tipo_check;
alter table movimientos add constraint movimientos_tipo_check
  check (tipo in ('compra','venta','devolucion','salida','ajuste','inicial'));

alter table empresas add column if not exists carga_inicial_cerrada timestamptz;

-- Una vez cerrada, un usuario no la vuelve a abrir (ni la cierra por fuera de la función)
create or replace function empresas_carga_inicial() returns trigger
language plpgsql as $$
begin
  if new.carga_inicial_cerrada is distinct from old.carga_inicial_cerrada
     and auth.uid() is not null and current_setting('cuadre.carga_inicial', true) is distinct from 'si' then
    raise exception 'La carga inicial se cierra con su botón y no se vuelve a abrir. Si hace falta, avisa a Cuadre';
  end if;
  return new;
end $$;
drop trigger if exists empresas_carga_inicial on empresas;
create trigger empresas_carga_inicial before update on empresas
  for each row execute function empresas_carga_inicial();

-- ---------- 2. Carga inicial ----------
-- p_items: [{"producto_id"}  o  {"codigo","codigos_alt":[...],"nombre","principio_activo","laboratorio",
--            "presentacion","seccion","iva","costo","margen","precio","pmvp","minimo","rx","controlado"},
--           más  "lote","vence","cantidad","costo"]
--   * Con producto_id, el renglón va a ese producto.
--   * Sin él, se busca por código (principal o alterno); si no trae código, por nombre y presentación.
--     Si no existe, se crea con los datos del renglón.
--   * Sin cantidad, el renglón solo crea el producto (catálogo sin existencia).
--   * Sin lote, queda como «S/L» (los controlados sí lo exigen). El vencimiento es obligatorio.
create or replace function carga_inicial(p_empresa uuid, p_items jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  it jsonb; n int := 0; pr productos; lt lotes; e empresas;
  cod text; nom text; q numeric; c numeric; mg numeric; pv numeric; lote_txt text; iv text;
  nuevos int := 0; lotes_n int := 0; unidades numeric := 0; ids bigint[] := '{}';
begin
  if not tiene_rol(p_empresa, '{dueno,gerente}') then raise exception 'Solo el dueño o el gerente hacen la carga inicial'; end if;
  select * into e from empresas where id = p_empresa;
  if e.tipo <> 'farmacia' then raise exception 'La carga inicial de inventario es de la farmacia'; end if;
  if e.carga_inicial_cerrada is not null then
    raise exception 'La carga inicial ya se cerró el %. La mercancía nueva entra por Compras, con su factura',
      to_char(e.carga_inicial_cerrada at time zone 'America/Caracas', 'DD/MM/YYYY');
  end if;
  if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items) = 0 then raise exception 'La carga no trae renglones'; end if;
  if jsonb_array_length(p_items) > 5000 then raise exception 'Sube la carga en partes de hasta 5.000 renglones'; end if;

  perform set_config('cuadre.inventario', 'si', true);
  for it in select * from jsonb_array_elements(p_items) loop
    n := n + 1;
    begin
      cod := nullif(nullif(trim(it->>'codigo'), ''), '—');
      nom := trim(coalesce(it->>'nombre', ''));
      q := coalesce(nullif(trim(it->>'cantidad'), '')::numeric, 0);
      c := nullif(trim(it->>'costo'), '')::numeric;
      if q < 0 or c < 0 then raise exception 'la cantidad y el costo no pueden ser negativos'; end if;

      -- El producto: por número, por código o por nombre y presentación
      pr := null;
      if (it->>'producto_id') is not null then
        select * into pr from productos where id = (it->>'producto_id')::bigint and empresa_id = p_empresa and activo;
        if pr.id is null then raise exception 'producto no encontrado'; end if;
      elsif cod is not null then
        select * into pr from productos where empresa_id = p_empresa and activo and (codigo = cod or cod = any(codigos_alt)) limit 1;
      elsif nom <> '' then
        select * into pr from productos where empresa_id = p_empresa and activo and lower(nombre) = lower(nom)
          and lower(coalesce(nullif(presentacion, '—'), '')) = lower(trim(coalesce(it->>'presentacion', ''))) order by id limit 1;
      end if;
      if pr.id is null then
        if nom = '' then raise exception 'falta el nombre del producto'; end if;
        if nom ~ '[<>]' then raise exception 'el nombre no puede llevar los signos < >'; end if;
        iv := upper(coalesce(nullif(trim(it->>'iva'), ''), 'E'));
        if iv not in ('E', 'G', 'R') then raise exception 'el IVA debe ser E (exento), G (16 %%) o R (8 %%)'; end if;
        mg := coalesce(nullif(trim(it->>'margen'), '')::numeric, 30);
        if mg < 0 or mg > 1000 then raise exception 'el %% de ganancia no es válido'; end if;
        pv := coalesce(nullif(trim(it->>'precio'), '')::numeric, round(coalesce(c, 0) * (1 + mg / 100), 2));
        insert into productos (empresa_id, codigo, codigos_alt, nombre, principio_activo, laboratorio, presentacion, seccion,
                               iva, costo, margen, precio, pmvp, minimo, rx, controlado)
        values (p_empresa, cod,
                coalesce(array(select jsonb_array_elements_text(case when jsonb_typeof(it->'codigos_alt') = 'array' then it->'codigos_alt' else '[]' end)), '{}'),
                nom, nullif(trim(it->>'principio_activo'), ''), nullif(trim(it->>'laboratorio'), ''), nullif(trim(it->>'presentacion'), ''),
                nullif(trim(it->>'seccion'), ''), iv::alicuota_iva, coalesce(c, 0), mg, pv, nullif(trim(it->>'pmvp'), '')::numeric,
                coalesce(nullif(trim(it->>'minimo'), '')::int, 5),
                coalesce((it->>'rx')::boolean, false) or coalesce((it->>'controlado')::boolean, false), coalesce((it->>'controlado')::boolean, false))
        returning * into pr;
        nuevos := nuevos + 1;
      end if;
      if not pr.id = any(ids) then ids := ids || pr.id; end if;

      -- La existencia: entra a su lote como inventario inicial
      if q > 0 then
        if nullif(trim(it->>'vence'), '') is null then raise exception 'falta la fecha de vencimiento'; end if;
        lote_txt := upper(nullif(trim(it->>'lote'), ''));
        if lote_txt is null and pr.controlado then raise exception 'un controlado necesita su número de lote'; end if;
        insert into lotes (empresa_id, producto_id, lote, vence, cantidad, costo)
        values (p_empresa, pr.id, coalesce(lote_txt, 'S/L'), (it->>'vence')::date, q, coalesce(c, pr.costo))
        on conflict (producto_id, lote, vence) do update set cantidad = lotes.cantidad + excluded.cantidad, costo = excluded.costo
        returning * into lt;
        insert into movimientos (empresa_id, producto_id, lote_id, tipo, cantidad, costo, motivo)
        values (p_empresa, pr.id, lt.id, 'inicial', q, lt.costo, 'Inventario inicial');
        lotes_n := lotes_n + 1; unidades := unidades + q;
      end if;
    exception when others then
      raise exception 'Renglón %: %', n, sqlerrm;
    end;
  end loop;
  perform set_config('cuadre.inventario', '', true);
  return jsonb_build_object('renglones', n, 'productos_nuevos', nuevos, 'lotes', lotes_n, 'unidades', unidades, 'productos', to_jsonb(ids));
end $$;
revoke all on function carga_inicial(uuid, jsonb) from public, anon;
grant execute on function carga_inicial(uuid, jsonb) to authenticated;

-- ---------- 3. Cerrar la carga inicial (solo el dueño, una vez) ----------
create or replace function cerrar_carga_inicial(p_empresa uuid)
returns timestamptz
language plpgsql security definer set search_path = public as $$
declare t timestamptz;
begin
  if not tiene_rol(p_empresa, '{dueno}') then raise exception 'Solo el dueño cierra la carga inicial'; end if;
  perform set_config('cuadre.carga_inicial', 'si', true);
  update empresas set carga_inicial_cerrada = coalesce(carga_inicial_cerrada, now()) where id = p_empresa
    returning carga_inicial_cerrada into t;
  perform set_config('cuadre.carga_inicial', '', true);
  return t;
end $$;
revoke all on function cerrar_carga_inicial(uuid) from public, anon;
grant execute on function cerrar_carga_inicial(uuid) to authenticated;

-- ---------- 4. Registro de inventario: la carga inicial va en «inicial» ----------
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
      coalesce(sum(m.cantidad) filter (where m.fecha < desde or m.tipo = 'inicial'), 0) ini,
      coalesce(sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'compra'), 0) com,
      coalesce(sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'devolucion'), 0) dev,
      coalesce(-sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'venta'), 0) ven,
      coalesce(-sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'salida' and not m.a_proveedor), 0) ret,
      coalesce(-sum(m.cantidad) filter (where m.fecha >= desde and m.a_proveedor), 0) dpr,
      coalesce(sum(m.cantidad) filter (where m.fecha >= desde and m.tipo = 'ajuste'), 0) aju,
      coalesce(sum(m.cantidad), 0) fin,
      coalesce(sum(m.cantidad * m.costo) filter (where m.fecha < desde or m.tipo = 'inicial'), 0) vi,
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

-- ---------- 5. Libro de controlados: «Inventario inicial» ----------
create or replace function libro_por_movimiento() returns trigger
language plpgsql security definer set search_path = public as $$
declare pr productos; lt lotes; d documentos; rx recipes; ci text; concepto text; origen text;
begin
  select * into pr from productos where id = new.producto_id;
  if not pr.controlado then return new; end if;
  select * into lt from lotes where id = new.lote_id;
  if new.tipo = 'venta' then
    select * into d from documentos where id = new.documento_id;
    ci := upper(regexp_replace(regexp_replace(d.cliente_rif, '[.\s]', '', 'g'), '^([VEJGP])-?', '\1-'));
    select * into rx from recipes
      where empresa_id = new.empresa_id and tipo = 'especial' and producto_id = new.producto_id and paciente_ci = ci
        and vendido - new.cantidad <= despachado and fecha > now() - interval '30 days'
      order by fecha limit 1 for update;
    if rx.id is null then
      raise exception '% es controlado: registra primero el récipe especial de este paciente (cédula %), o no alcanza lo que autoriza', pr.nombre, ci;
    end if;
    update recipes set vendido = vendido - new.cantidad where id = rx.id;
    concepto := 'Récipe especial N° ' || rx.numero_especial || ' · factura ' || lpad(d.numero::text, 8, '0');
    origen := coalesce(rx.medico, '') || coalesce(' · MPPS ' || rx.mpps, '');
  elsif new.tipo = 'compra' then concepto := 'Compra' || coalesce(' · ' || new.referencia, ''); origen := 'Droguería';
  elsif new.tipo = 'inicial' then concepto := 'Inventario inicial'; origen := 'Conteo al arrancar el sistema';
  elsif new.tipo = 'devolucion' then concepto := 'Devolución' || coalesce(' · ' || new.motivo, '');
  else concepto := initcap(new.tipo) || coalesce(': ' || new.motivo, '');
  end if;
  insert into libro_controlados (empresa_id, fecha, producto_id, producto, concepto, origen, paciente_ci, lote, entrada, salida, recipe_id, movimiento_id, usuario)
  values (new.empresa_id, new.fecha, pr.id, pr.nombre, concepto, origen, ci, lt.lote,
          greatest(new.cantidad, 0), greatest(-new.cantidad, 0), rx.id, new.id, new.usuario);
  return new;
end $$;
