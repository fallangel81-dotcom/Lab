# Spike: $count – Analyse & Erkenntnisse

**Cockpit:** AC Order List (`/ETN/C_AC_ORDER_LIST`)
**Service:** `PM_COCKPIT_C_AC_SRV`

---

## Ausgangsfrage
Führt ein `$count`-Request unnötigerweise teure Operationen aus (Status-Berechnung, Text-Joins, Assoziations-Auflösung)?

---

## Erkenntnisse

### 1. HANA eliminiert Text-JOINs automatisch
Ein `$count` ohne Filter auf Textfelder erzeugt folgenden SQL:
```sql
SELECT COUNT(*) FROM "/ETN/C_AC_ORDER_LIST"
WHERE "MANDT" = ? AND "ORDER_TYPE" = ?
```
HANA's Query Optimizer schneidet alle `LEFT OUTER JOINs` auf Text-/Beschreibungstabellen weg, da sie für `COUNT(*)` irrelevant sind. Verifiziert via ST05 / HANA Plan Visualizer.

**Gelesene Tabellen bei $count:** nur `AUFK`, `AFIH`, `AFKO`, `ILOA` (INNER JOINs des Basis-Views).

### 2. SADL-Exit wird bei $count nicht aufgerufen
Das Framework übergibt bei `$count` eine leere `it_requested_calc_elements`-Tabelle. Der Exit `IF_SADL_EXIT_CALC_ELEMENT_READ~CALCULATE` wird dadurch nicht aufgerufen – der teure `STATUS_TEXT_EDIT`-Loop läuft nicht.

### 3. Assoziationen werden bei $count nicht aufgelöst
Reine CDS-Assoziationen (nicht als Path-Expression im SELECT verwendet) werden bei `$count` nicht gejoint. Betrifft `_systemstatus`, `_userstatus`, `_partner` u.a.

---

## Durchgeführte Massnahme

**Defensiver Early-Return im SADL-Exit** (`/ETN/CL_PM_VDM_IH_STATUS` / `cl_pm_order_stat`):

```abap
" $count requests carry no calc elements -> skip expensive status reads
if it_requested_calc_elements is initial.
  ct_calculated_data = corresponding #( it_original_data ).
  return.
endif.
```

Sicherheitsnetz für Edge Cases, in denen der Framework-Aufruf dennoch erfolgt.

---

## Nicht umgesetzt (kein Mehrwert)

- **`@ObjectModel.text.association`** statt Path-Expressions: HANA eliminiert Text-JOINs bei $count bereits selbst. Umbau wäre Breaking Change für bestehende UIs und bringt keinen messbaren Gewinn.

---

## $Search
→ siehe separater Chat / wird nachgetragen
