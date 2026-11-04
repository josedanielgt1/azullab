-- Cuadre · 0019 · IGTF solo para contribuyentes especiales
-- La Ley del IGTF pone a cobrar el 3 % por pagos en divisas a los sujetos pasivos especiales.
-- Los tres negocios del grupo son contribuyentes ordinarios: la caja no lo cobra y la factura
-- tampoco debe sumarlo (antes la base lo agregaba y el total no cuadraba con lo cobrado).
-- Si el SENIAT designa especial a un negocio, se pone igtf = 3 en su fila de empresas.
alter table empresas alter column igtf set default 0;
update empresas set igtf = 0 where igtf <> 0;
comment on column empresas.igtf is 'IGTF en %: 0 para contribuyente ordinario; 3 si el SENIAT lo designa contribuyente especial';
