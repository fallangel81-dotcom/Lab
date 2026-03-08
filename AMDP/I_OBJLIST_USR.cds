/*
  CDS View Entity /ETN/I_OBJLIST_USR
  ─────────────────────────────────────────────────────────────────────────────
  Consumes the Table Function and adds Associations for Address and Geo data.
  These are intentionally NOT resolved inside the AMDP (Phase 2 / lazy loading)
  so the UI/OData layer can decide whether to expand them.

  Usage in OData / UI:
    $expand=_Address   → adds Street, City, PostCode etc. from ADRC
    $expand=_Geo       → adds Coordinates from /ETN/PMT_GEODATA
  ─────────────────────────────────────────────────────────────────────────────
*/
@EndUserText.label: 'Object List for Current User'
@ObjectModel.usageType: {
  serviceQuality: #A,
  sizeCategory:   #XL,
  dataClass:      #TRANSACTIONAL
}

define view entity /ETN/I_OBJLIST_USR
  as select from /ETN/TF_OBJLIST_USR( ) as base

  association [0..1] to /ETN/I_PM_ADDRESS   as _Address
    on _Address.Addrnumber    = base.TechObjAddressNo

  association [0..*] to /ETN/I_TOBJ_GEODATA as _Geo
    on _Geo.KeyGeoCoordinates = base.KeyGeoCoordinates

{
  key base.OrderId,
  key base.Counter,
      base.ObjectListKey,
      base.Iloan,
      base.NotifNo,
      base.EquiNo,
      base.PlanPlant,
      base.ABCIndicator,
      base.KeyGeoCoordinates,
      base.TechObjAddressNo,
      base.TechObjectKey,
      base.TechObjectNo,
      base.TechObjectDesc,
      base.TechObjectType,
      base.TechObjectInternalKey,
      base.TechObjIsEquipOrFuncnlLoc,
      base.ParentTechObjectKey,
      base.ParentObjectIsEquiOrFuncloc,

      /* Associations – resolved on demand, not in the AMDP */
      _Address,
      _Geo
}
