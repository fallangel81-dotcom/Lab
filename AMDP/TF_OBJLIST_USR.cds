/*
  CDS Table Function /ETN/TF_OBJLIST_USR
  ─────────────────────────────────────────────────────────────────────────────
  Thin CDS wrapper that exposes the AMDP Table Function to the CDS layer.

  Field ORDER and types must match /ETN/CL_TF_OBJLIST_USR=>ty_result exactly.
  The AMDP reads session_context() internally – no input parameters needed.
  ─────────────────────────────────────────────────────────────────────────────
*/
@EndUserText.label: 'Object List for Current User (Table Function)'

define table function /ETN/TF_OBJLIST_USR
  returns {
    key OrderId                     : aufnr;
    key Counter                     : obzae;
        ObjectListKey               : objknr;
        Iloan                       : iloan;
        NotifNo                     : qmnum;
        EquiNo                      : equnr;
        PlanPlant                   : iwerk;
        ABCIndicator                : abckz;
        KeyGeoCoordinates           : /eon/pmd_geo_koordinaten;
        TechObjAddressNo            : adrnr;
        TechObjectKey               : eams_tech_obj_alpha_conv;
        TechObjectNo                : abap.char(30);
        TechObjectDesc              : abap.char(40);
        TechObjectType              : eqart;
        TechObjectInternalKey       : abap.char(30);
        TechObjIsEquipOrFuncnlLoc   : eams_tec_obj_type_value;
        ParentTechObjectKey         : abap.char(30);
        ParentObjectIsEquiOrFuncloc : eams_tec_obj_type_value;
  }
  implemented by method /ETN/CL_TF_OBJLIST_USR=>GET_OBJLIST_FOR_USER;
