# Spike: IH – BE Einschränkungen für globale Suche (alle Cockpits)

## $search (OData globale Suche)

### Wie funktioniert $search in SAP/HANA

OData `$search=<Wert>` wird von SAP SADL intern in ein HANA `CONTAINS`-Prädikat übersetzt:

```sql
WHERE CONTAINS( ("FIELD1", "FIELD2", ...), ?, FUZZY(...) )
```

Durchsucht werden alle Felder der CDS View die mit `@Search.defaultSearchElement: true` annotiert sind.

---

### Problem: HANA SQL-Code 7 – Dump

**Fehlermeldung:**
> feature not supported: CONTAINS predicates on aggregate functions

**Ursache:**  
HANA kann kein `CONTAINS` auf Felder anwenden, wenn die zugrundeliegende SQL-Abfrage ein `GROUP BY` enthält.  
`SELECT DISTINCT` in CDS Views wird von HANA intern als `GROUP BY` behandelt und löst denselben Fehler aus.

**Gilt für die gesamte View-Kette:** Tritt ein `DISTINCT` oder `GROUP BY` irgendwo in der View-Hierarchie auf (auch in tief verschachtelten Assoziationen), schlägt `CONTAINS` fehl – **aber nur**, wenn ein Feld aus dieser aggregierenden View auch tatsächlich als `@Search.defaultSearchElement: true` exponiert ist.

---

### Verfügbare SADL-Exit-Interfaces

| Interface | Beschreibung | Für $search nutzbar? |
|---|---|---|
| `IF_SADL_EXIT_FILTER_TRANSFORM` | Filter manipulieren | Nur indirekt ($search → $filter) |
| `IF_SADL_EXIT_CALC_ELEMENT_READ` | Berechnete Felder | Nein |
| `IF_SADL_EXIT_DB_HINTS` | DB Hints | Nein |
| `IF_SADL_EXIT_SORT_TRANSFORM` | Sortierung | Nein |
| `IF_SADL_EXIT_SEARCH_TRANSFORM` | Dedizierter Search-Exit | **Nicht verfügbar** |

Ein programmatischer Exit speziell für `$search` existiert in der vorliegenden SADL-Version nicht.

---

### Lösung: Felder per CDS-Annotation ausschließen

Felder, die aus Views mit Aggregation stammen oder nicht sinnvoll durchsuchbar sind, müssen explizit ausgeschlossen werden:

```cds
@Search.defaultSearchElement: false
BetroffenesFeld,
```

**Virtuelle / berechnete Felder** (`@ObjectModel.virtualElement: true`) müssen grundsätzlich ausgeschlossen werden, da sie nicht in der Datenbank existieren.

**Empfehlung Deny-by-default:**  
`@Search.searchable: true` auf View-Ebene beibehalten, aber nur explizit geprüfte Felder auf `true` setzen. Neue Felder sind damit automatisch nicht durchsucht bis sie bewusst freigegeben werden.

---

### Offene Punkte / $count

→ wird im Nachgang ergänzt
