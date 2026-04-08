@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Suchhilfe: Leistungsarten je Arbeitsplatz (aktuell und Zukunft)'
@Search.searchable: true

define view entity /ETN/I_ACTIVITYTYPE
  as select from /ETN/I_CRCO_CRHD as wkc

    left outer to one join /ETN/I_CSKS as costc
      on  costc.ControllingArea = wkc.ControllingArea
      and costc.CostCenter      = wkc.CostCenter

    // Leistungsart-Texte (sprachabhängig); datbi >= heute, da cslt ebenfalls zeitabhängig ist
    association [0..1] to cslt as clst
      on  clst.kokrs = $projection.ControllingArea
      and clst.lstar = $projection.ActivityType
      and clst.datbi >= $session.system_date
      and clst.spras = $session.system_language

{
  key  wkc.ControllingArea              as ControllingArea,

  @ObjectModel.text.element: [ 'ActivityTypeDesc' ]
  key  wkc.DefaultActivityType          as ActivityType,

  key  wkc.CostCenterAssignmentEndDate  as CostCenterAssignmentEndDate, // unterscheidet aktuelle/zukünftige Zeitscheiben

       @Search.defaultSearchElement: true
       @Search.fuzzinessThreshold: 0.8
       @Semantics.text: true
       clst.ktext                       as ActivityTypeDesc,
       clst.ltext                       as ActivityTypeLongText,

       wkc.ActivityTypeUnit             as Unit,

       wkc.WorkCenter                   as WorkCenter,
       wkc.WorkCenterInternalId,
       wkc.CostCenter                   as CostCenter,
       costc.CostCenterDesc             as CostCenterDesc,
       costc.CompanyCode                as CompanyCode,
       clst.spras                       as Language
}
