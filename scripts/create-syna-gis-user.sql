-- ============================================================
-- SYNA_GIS DB-User anlegen
-- Führe dieses Skript einmalig als DBADMIN in der HANA Cloud
-- SQL Console aus (z.B. SAP HANA Cockpit oder DBeaver).
--
-- Danach muss das MTA-Projekt neu deployed werden, damit
-- die .hdbgrants-Datei die Tabellenrechte setzt.
-- ============================================================

-- 1. User anlegen
--    Passwort vor Ausführung anpassen!
CREATE USER SYNA_GIS PASSWORD "Initial1234!" NO FORCE_FIRST_PASSWORD_CHANGE;

-- 2. Login-Recht (wird automatisch vergeben, zur Dokumentation)
GRANT CREATE SESSION TO SYNA_GIS;

-- ============================================================
-- Hinweis:
-- INSERT / UPDATE / DELETE auf die innogis-Tabellen werden
-- NICHT hier gesetzt, sondern automatisch beim MTA-Deploy
-- über db/cfg/innogis-syna-gis.hdbgrants gesetzt.
-- ============================================================
