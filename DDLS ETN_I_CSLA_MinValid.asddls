@AbapCatalog.sqlViewEntityName: 'ETNICSLAMV'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Leistungsart – früheste gültige oder zukünftige Periode'

// Hilfssicht: Verdichtet csla auf eine Zeile pro (Kostenrechnungskreis, Leistungsart).
// Wird verwendet, um Duplikate im Join zu vermeiden, wenn mehrere Datbi-Zeitscheiben
// gleichzeitig gültig oder vorerfasst sind (z.B. über den Jahreswechsel).
// leinh ist in GROUP BY statt MIN(), da UNIT von MIN() nicht unterstützt wird;
// in der Praxis ist die Mengeneinheit je Leistungsart über alle Perioden konstant.

define view entity /ETN/I_CSLA_MinValid
  as select from csla
  where datbi >= $session.system_date       // nur aktuelle und zukünftige Sätze
{
  key kokrs,
  key lstar,
      leinh,                                // GROUP BY – kein Aggregat nötig (UNIT nicht MIN-fähig)
      min( datbi )  as EarliestValidDateTo  // frühester Gültig-bis-Termin >= heute (Typ DATS)
}
group by
  kokrs,
  lstar,
  leinh
