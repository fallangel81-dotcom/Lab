-- =============================================================================
-- InnoGis Writer - Technischer DB-User Erstellung
-- =============================================================================
-- Voraussetzungen:
--   - Ausführen als HANA-Admin (mit CREATE USER und GRANT ANY Rechten)
--   - MTA (pm.wfm.shared) muss bereits deployed sein
--   - HDI-Container: pm-wfm-shared-db
--   - Rolle:         innogis.roles::InnoGisWriter
-- =============================================================================

-- Schritt 1: Technischen User anlegen
-- Passwort vor Ausführung anpassen (mind. 8 Zeichen, Groß/Klein/Zahl/Sonderzeichen)
CREATE USER INNOGIS_WRITER
    PASSWORD "Change_Me_123!"
    NO FORCE_FIRST_PASSWORD_CHANGE;

-- Schritt 2: Grundrechte für Datenbankverbindung
GRANT CREATE SESSION TO INNOGIS_WRITER;

-- =============================================================================
-- Schritt 3: HDI-Rolle über den Object Owner des Containers zuweisen
--
-- WICHTIG: Dieser Schritt muss als Object Owner des HDI-Containers ausgeführt
--          werden. Der Object Owner hat den Namen:
--
--              <SERVICE_INSTANCE_GUID>#OO
--
--          Die Credentials (Benutzername + Passwort) erhält man über:
--
--              cf service-key pm-wfm-shared-db <key-name>
--          oder in BTP Cockpit → Instanz → Service Keys
--
-- Alternativ: Über die _SYS_DI API als DI-Admin (siehe unten)
-- =============================================================================

-- Option A: Als Object Owner (#OO) ausführen
-- (Verbindung mit #OO Credentials herstellen, dann:)
GRANT "innogis.roles::InnoGisWriter" TO INNOGIS_WRITER;


-- Option B: Via _SYS_DI API als DI-Admin (falls kein direkter #OO Zugang)
-- Den Container-Namen (<CONTAINER_SCHEMA>) aus der Service-Key-Verbindung entnehmen.
--
-- CALL _SYS_DI#<CONTAINER_SCHEMA>.GRANT_CONTAINER_SCHEMA_ROLES(
--     '[{"role_name": "innogis.roles::InnoGisWriter",
--        "principal_schema_name": "",
--        "principal_name": "INNOGIS_WRITER"}]',
--     _SYS_DI.T_NO_PARAMETERS,
--     ?, ?, ?
-- );


-- =============================================================================
-- Verifikation: Zugewiesene Rollen prüfen
-- =============================================================================
SELECT
    GRANTEE,
    ROLE_SCHEMA_NAME,
    ROLE_NAME,
    GRANTOR,
    IS_GRANTABLE
FROM SYS.EFFECTIVE_ROLES
WHERE GRANTEE = 'INNOGIS_WRITER'
ORDER BY ROLE_NAME;

-- Zugriff auf Tabellen prüfen
SELECT
    GRANTEE,
    SCHEMA_NAME,
    OBJECT_NAME,
    PRIVILEGE
FROM SYS.EFFECTIVE_PRIVILEGES
WHERE GRANTEE = 'INNOGIS_WRITER'
  AND OBJECT_TYPE = 'TABLE'
ORDER BY OBJECT_NAME;
