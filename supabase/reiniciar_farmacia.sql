-- =====================================================================
-- Cuadre · Reiniciar la farmacia: borra TODO lo que se hizo de práctica
--
-- Para qué: después de practicar y de la revisión con el dueño, dejar la
-- farmacia vacía para cargar los datos reales. Se corre UNA sola vez,
-- antes de la primera factura real. NO es una migración.
--
-- Cómo: Supabase → SQL Editor → pegar este archivo completo → en la línea
-- de abajo, cambiar el texto por el RIF que la farmacia tiene HOY en
-- Configuración → Datos fiscales → Run. Si el RIF no coincide, no hace nada.
--
-- Borra (solo de la farmacia): productos, lotes y movimientos; facturas,
--   notas y sus pagos; compras, pagos y droguerías; clientes, médicos,
--   récipes, libro de controlados y alertas; gastos; reportes Z y libro
--   de control de la máquina; talonario usado; la configuración guardada
--   en pantalla (secciones, formas de cobro, cuentas, fallas, cotizaciones,
--   empleados y nómina) y el registro de quién hizo qué. Los números de
--   factura y de notas vuelven a empezar en 1.
-- Deja: las tres empresas, los usuarios con sus roles, la tasa BCV, el
--   laboratorio y el CrossFit completos, y los datos fiscales de la farmacia
--   (pero sin confirmar: hay que revisarlos y confirmarlos de nuevo).
-- Se niega si la farmacia ya tiene facturas de una máquina fiscal de verdad.
--
-- Después, en cada equipo donde se practicó: borrar los datos del sitio en
-- el navegador (la impresora «simulada» y la copia sin conexión viven ahí).
-- =====================================================================

select set_config('cuadre.reiniciar', 'ESCRIBE AQUI EL RIF DE LA FARMACIA', false);

do $$
declare
  e empresas; rif_escrito text := upper(trim(current_setting('cuadre.reiniciar', true)));
  t text; n bigint; resumen text := '';
  -- En este orden: primero lo que apunta a otra tabla
  tablas text[] := array['libro_controlados', 'alertas_pacientes', 'talonario_usados', 'movimientos', 'recipes', 'lotes', 'productos',
                         'pagos_compras', 'compras', 'proveedores', 'gastos', 'documentos', 'clientes', 'medicos',
                         'reportes_z', 'maquina_eventos', 'colecciones', 'correlativos', 'contadores', 'auditoria'];
begin
  if (select count(*) from empresas where tipo = 'farmacia') <> 1 then raise exception 'Se esperaba una sola farmacia: no se borró nada'; end if;
  select * into e from empresas where tipo = 'farmacia';
  if rif_escrito is distinct from upper(e.rif) then
    raise exception 'No se borró nada. Para reiniciar la farmacia, escribe su RIF actual (%) en la línea de set_config', e.rif;
  end if;
  if exists (select 1 from documentos where empresa_id = e.id and medio = 'maquina' and numero_fiscal is not null and numero_fiscal < 900000001) then
    raise exception 'No se borró nada: la farmacia ya tiene facturas impresas por una máquina fiscal de verdad. Eso no es práctica';
  end if;

  -- Los candados (documentos y movimientos que no se borran, existencia que no se toca a mano)
  -- se apagan solo dentro de esta operación; si algo falla, todo vuelve a como estaba
  foreach t in array tablas || array['documento_lineas', 'documento_pagos', 'empresas'] loop
    if to_regclass('public.' || t) is not null then execute format('alter table public.%I disable trigger user', t); end if;
  end loop;

  foreach t in array tablas loop
    if to_regclass('public.' || t) is null then continue; end if;
    execute format('delete from public.%I where empresa_id = $1', t) using e.id;
    get diagnostics n = row_count;
    if n > 0 then resumen := resumen || t || ': ' || n || E'\n'; end if;
  end loop;

  update empresas set datos_confirmados = false where id = e.id;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'empresas' and column_name = 'carga_inicial_cerrada') then
    execute 'update empresas set carga_inicial_cerrada = null where id = $1' using e.id;
  end if;

  foreach t in array tablas || array['documento_lineas', 'documento_pagos', 'empresas'] loop
    if to_regclass('public.' || t) is not null then execute format('alter table public.%I enable trigger user', t); end if;
  end loop;

  perform set_config('cuadre.reiniciado', 'Farmacia ' || e.rif || E' reiniciada. Filas borradas:\n' || coalesce(nullif(resumen, ''), '(ya estaba vacía)'), false);
end $$;

select current_setting('cuadre.reiniciado', true) as resultado;
