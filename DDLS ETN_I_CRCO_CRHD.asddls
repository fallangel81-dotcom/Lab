@AbapCatalog.sqlViewEntityName: 'ETNICRCOCRHD'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Gültige und zukünftige Leistungsarten je Arbeitsplatz'

define view entity /ETN/I_CRCO_CRHD
  as select from crhd as wkc                        // Arbeitsplatz (Stamm, aktuell gültig)

    inner join crco as costl                         // Kostenstellenzuordnung – aktuell + Zukunft
      on  costl.objty = wkc.objty
      and costl.objid = wkc.objid

    inner join /ETN/I_CSLA_MinValid as lstart        // Existenzprüfung: eine Zeile pro Leistungsart,
      on  lstart.kokrs = costl.kokrs                 // verhindert Duplikate bei mehreren csla-Zeitscheiben
      and lstart.lstar = costl.lstar

{
  key wkc.objid              as WorkCenterInternalId,
  key costl.lstar            as DefaultActivityType,
  key costl.endda            as CostCenterAssignmentEndDate, // eine Zeile pro Zuordnungs-Zeitscheibe (crco)

      costl.kostl            as CostCenter,
      costl.kokrs            as ControllingArea,
      wkc.arbpl              as WorkCenter,
      wkc.steus              as ControlKey,
      lstart.leinh            as ActivityTypeUnit
}

where wkc.objty    =  'A'                            // nur Arbeitsplätze
  and wkc.begda    <= $session.system_date           // Arbeitsplatz heute vorhanden
  and wkc.endda    >= $session.system_date
  and costl.endda  >= $session.system_date           // Zuordnung aktuell oder zukünftig
