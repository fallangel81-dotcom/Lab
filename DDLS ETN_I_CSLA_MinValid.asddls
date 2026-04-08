@AbapCatalog.sqlViewEntityName: 'ETNICSLAMV'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Leistungsart – früheste gültige oder zukünftige Periode'

// Hilfssicht: Verdichtet csla auf eine Zeile pro (Kostenrechnungskreis, Leistungsart).
// Wird verwendet, um Duplikate im Join zu vermeiden, wenn mehrere Datbi-Zeitscheiben
// gleichzeitig gültig oder vorerfasst sind (z.B. über den Jahreswechsel).

define view entity /ETN/I_CSLA_MinValid
  as select from csla
  where datbi >= $session.system_date       // nur aktuelle und zukünftige Sätze
{
  key kokrs,
  key lstar,
      min( datbi )  as EarliestValidDateTo, // frühester Gültig-bis-Termin >= heute
      min( leinh )  as ActivityTypeUnit     // Mengeneinheit – in der Praxis je Leistungsart konstant
}
group by
  kokrs,
  lstar
