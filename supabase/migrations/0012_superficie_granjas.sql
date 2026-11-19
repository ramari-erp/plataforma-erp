-- =====================================================================
-- 0012_superficie_granjas.sql — Superficie y notas por granja (berries se mide en hectáreas)
-- =====================================================================
alter table granjas add column superficie_ha numeric(10,2) check (superficie_ha > 0);
alter table granjas add column notas text;
