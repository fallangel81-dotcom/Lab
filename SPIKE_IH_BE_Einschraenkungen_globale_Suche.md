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

**Gilt für die gesamte View-Kette ohne Tiefenbegrenzung:**  
Tritt ein `DISTINCT` oder `GROUP BY` irgendwo in der View-Hierarchie auf, schlägt `CONTAINS` fehl —
**aber nur**, wenn ein Feld aus dieser aggregierenden View auch tatsächlich als `@Search.defaultSearchElement: true` exponiert ist.
Ist das Feld ausgeschlossen (`false`), ist die aggregierende View in der Kette kein Problem.

```
C_VIEW (Consumption)
    └── JOIN → I_VIEW_A (ok)
                    └── JOIN → I_VIEW_B ← select distinct  💥 (nur wenn Feld davon searchable: true)
```

---

### Was wurde ausprobiert – was funktioniert nicht

#### ❌ `IF_SADL_EXIT_SEARCH_TRANSFORM`
Ein dedizierter programmatischer Exit für `$search` existiert in der vorliegenden SADL-Version nicht.
Dieses Interface ist nicht verfügbar.

#### ❌ `IF_SADL_EXIT_FILTER_TRANSFORM~MAP_ATOM` für $search
`MAP_ATOM` wird für `$filter`-Atome aufgerufen. SAP übersetzt `$search` intern in Filter-Conditions,
wodurch `MAP_ATOM` theoretisch erreichbar wäre — aber der Einstiegspunkt ist nicht zuverlässig
steuerbar und nicht der vorgesehene Weg. Für berechnete/virtuelle Felder greift es ohnehin nicht.

**Verfügbare SADL-Exit-Interfaces (vollständige Liste):**

| Interface | Beschreibung | Für $search nutzbar? |
|---|---|---|
| `IF_SADL_EXIT_FILTER_TRANSFORM` | Filter manipulieren | Nur indirekt, nicht empfohlen |
| `IF_SADL_EXIT_CALC_ELEMENT_READ` | Berechnete Felder | Nein |
| `IF_SADL_EXIT_CREATE_ADJUST` | Default-Werte | Nein |
| `IF_SADL_EXIT_CREATE_DEFAULT` | Default-Werte (Node) | Nein |
| `IF_SADL_EXIT_DB_HINTS` | DB Hints | Nein |
| `IF_SADL_EXIT_SORT_TRANSFORM` | Sortierung | Nein |
| `IF_SADL_EXIT_SEARCH_TRANSFORM` | Dedizierter Search-Exit | **Nicht verfügbar** |

---

### Lösung: Felder per CDS-Annotation ausschließen

```cds
@Search.defaultSearchElement: false
BetroffenesFeld,
```

**Virtuelle / berechnete Felder** (`@ObjectModel.virtualElement: true`) müssen grundsätzlich
ausgeschlossen werden — sie existieren nicht in der Datenbank und können nicht per CONTAINS gesucht werden.

**Empfehlung Deny-by-default:**  
`@Search.searchable: true` auf View-Ebene beibehalten, aber nur explizit geprüfte Felder auf `true` setzen.
Neue Felder sind damit automatisch nicht durchsucht bis sie bewusst freigegeben werden.

---

### Besonderheit: Text-Assoziationen (@ObjectModel.text.association)

Text-Views haben eine spezifische Struktur mit Sprachschlüssel:

```cds
@ObjectModel.dataCategory: #TEXT
@ObjectModel.representativeKey: 'OrderType'
define view entity /ETN/I_ORDER_TYPE_DESC as select from t003p {
  key auart as OrderType,
  @Semantics.language: true
  key spras as Language,         -- ← Sprachschlüssel!
  @Semantics.text: true
  txt as OrderTypeDesc
}
```

Im konsumierenden View wird die Assoziation verknüpft:

```cds
@ObjectModel.text.association: '_ordertype'
Order_Type,

association [0..1] to /ETN/I_ORDERTYPE_IH as _ordertype
  on  _ordertype.OrderType = $projection.Order_Type
 and  _ordertype.Language  = $session.system_language   -- ← Pflicht!
```

**Worauf zu achten ist:**

| Punkt | Erklärung |
|---|---|
| **Sprach-Join zwingend** | Ohne `Language = $session.system_language` im ON-Clause liefert die Assoziation mehrere Zeilen (eine pro Sprache) → Duplikate oder falsche Ergebnisse |
| **Assoziation muss [0..1] sein** | Text-Assoziationen die [0..*] sind, können nicht sicher für $search genutzt werden |
| **Beide Felder können searchable sein** | Schlüsselfeld (`Order_Type`) und Textfeld (`Order_Type_Text`) dürfen gleichzeitig `true` sein — sinnvoll, damit nach Code und Bezeichnung gesucht werden kann |
| **Text-View darf kein DISTINCT/GROUP BY enthalten** | Gilt genauso wie für alle anderen Views in der Kette |
| **`@Semantics.text: true` allein reicht nicht** | Zusätzlich muss `@Search.defaultSearchElement: true` explizit gesetzt werden, wenn das Textfeld durchsucht werden soll |

---

### $count

→ wird im Nachgang ergänzt (siehe Branch `claude/optimize-count-query-X6tje`)
