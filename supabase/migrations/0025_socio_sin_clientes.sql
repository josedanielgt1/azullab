-- Cuadre · 0025: el socio del CrossFit no ve ni toca la lista de clientes ni de proveedores
--
-- Desde la 0016 el socio es miembro del CrossFit (para su app). Las reglas de
-- clientes y proveedores solo pedían es_miembro, así que con su usuario podía
-- leer cédulas y teléfonos de todos los clientes, crearlos y cambiarlos, y leer
-- los proveedores. Lo que su app sí usa (planes, clases, pizarra, productos del
-- box) no se toca: son precios y horarios que el socio debe ver.

drop policy if exists ver on clientes;
drop policy if exists crear on clientes;
drop policy if exists editar on clientes;
create policy ver on clientes for select using (es_miembro(empresa_id) and not es_socio(empresa_id));
create policy crear on clientes for insert with check (es_miembro(empresa_id) and not es_socio(empresa_id));
create policy editar on clientes for update using (es_miembro(empresa_id) and not es_socio(empresa_id))
  with check (es_miembro(empresa_id) and not es_socio(empresa_id));

drop policy if exists ver on proveedores;
create policy ver on proveedores for select using (es_miembro(empresa_id) and not es_socio(empresa_id));
