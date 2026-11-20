-- =====================================================================
-- 0016_folios_unicos.sql — No se repiten folios de contrato ni boletas de báscula
--   Se compara sin espacios de más ni diferencias de mayúsculas/acentos ("prv-101" = "PRV-101").
--   Se valida al guardar (no rompe si ya hubiera repetidos capturados antes).
-- =====================================================================

create or replace function trg_folio_contrato_unico() returns trigger language plpgsql as $$
declare v_otro bigint;
begin
  if nullif(trim(new.folio), '') is null then new.folio := null; return new; end if;
  new.folio := regexp_replace(upper(trim(new.folio)), '\s+', ' ', 'g');
  select id into v_otro from contratos_mp
  where nombre_normalizado(folio) = nombre_normalizado(new.folio) and id <> coalesce(new.id, -1) limit 1;
  if v_otro is not null then
    raise exception 'El folio de contrato % ya existe. No puede repetirse.', new.folio;
  end if;
  return new;
end $$;
create trigger folio_unico before insert or update of folio on contratos_mp
  for each row execute function trg_folio_contrato_unico();

create or replace function trg_boleta_unica() returns trigger language plpgsql as $$
declare v_otra record;
begin
  if nullif(trim(new.boleta), '') is null then new.boleta := null; return new; end if;
  new.boleta := regexp_replace(upper(trim(new.boleta)), '\s+', ' ', 'g');
  select l.id, l.fecha into v_otra from llegadas_mp l
  where nombre_normalizado(l.boleta) = nombre_normalizado(new.boleta) and l.id <> coalesce(new.id, -1) limit 1;
  if v_otra.id is not null then
    raise exception 'La boleta % ya está registrada en la llegada del %. No puede repetirse.', new.boleta, to_char(v_otra.fecha, 'DD/MM/YYYY');
  end if;
  return new;
end $$;
create trigger boleta_unica before insert or update of boleta on llegadas_mp
  for each row execute function trg_boleta_unica();

-- Para avisar en pantalla antes de guardar.
create index on contratos_mp (nombre_normalizado(folio));
create index on llegadas_mp (nombre_normalizado(boleta));
create index on llegadas_mp (nombre_normalizado(factura));
