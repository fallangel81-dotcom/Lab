@AbapCatalog.sqlViewEntityName: 'ETNICRCOCRHD'
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Aktuell gültige Leistungsarten je Arbeitsplatz'

define view entity /ETN/I_CRCO_CRHD
  as select from crhd as wkc                  // Arbeitsplatz (Stamm)

    inner join crco as costl                   // Kostenstellenzuordnung des Arbeitsplatzes
      on  costl.objty = wkc.objty
      and costl.objid = wkc.objid

    inner join csla as lstart                  // Existenzprüfung: Leistungsart muss gültig sein
      on  lstart.kokrs = costl.kokrs
      and lstart.lstar = costl.lstar

{
  key wkc.objid    as WorkCenterInternalId,
  key costl.lstar  as DefaultActivityType,
  key costl.endda  as CostCenterAssignmentEndDate,  // Key: mehrere Zeitscheiben möglich

      costl.kostl  as CostCenter,
      costl.kokrs  as ControllingArea,
      wkc.arbpl    as WorkCenter,
      wkc.steus    as ControlKey
}

where wkc.objty    =  'A'                     // nur Arbeitsplätze (nicht Kapazitäten o.ä.)
  and wkc.begda    <= $session.system_date
  and wkc.endda    >= $session.system_date
  and costl.endda  >= $session.system_date
  and lstart.datbi >= $session.system_date
