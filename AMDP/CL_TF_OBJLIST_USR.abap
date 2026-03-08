CLASS /etn/cl_tf_objlist_usr DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_amdp_marker_hdb.

    "! Result row type – field ORDER must match CDS Table Function returns {}
    TYPES:
      BEGIN OF ty_result,
        orderid                      TYPE aufnr,
        counter                      TYPE obzae,
        objectlistkey                TYPE objknr,
        iloan                        TYPE iloan,
        notifno                      TYPE qmnum,
        equino                       TYPE equnr,
        planplant                    TYPE iwerk,
        abcindicator                 TYPE abckz,
        keygeocoordinates            TYPE /eon/pmd_geo_koordinaten,
        techobjaddressno             TYPE adrnr,
        techobjectkey                TYPE eams_tech_obj_alpha_conv,
        techobjectno                 TYPE c LENGTH 30,
        techobjectdesc               TYPE c LENGTH 40,
        techobjecttype               TYPE eqart,
        techobjectinternalkey        TYPE c LENGTH 30,
        techobjiseequiporfuncnlloc   TYPE eams_tec_obj_type_value,
        parenttechobjectkey          TYPE c LENGTH 30,
        parentobjectiseequiorfuncloc TYPE eams_tec_obj_type_value,
      END OF ty_result.

    TYPES ty_result_tab TYPE STANDARD TABLE OF ty_result WITH DEFAULT KEY.

    CLASS-METHODS get_objlist_for_user
      RETURNING
        VALUE(result) TYPE ty_result_tab
      RAISING
        cx_amdp_error.

ENDCLASS.


CLASS /etn/cl_tf_objlist_usr IMPLEMENTATION.

  METHOD get_objlist_for_user
    BY DATABASE FUNCTION FOR HDB
    LANGUAGE SQLSCRIPT
    OPTIONS READ-ONLY
    USING
      pa0105
      kbed
      jest
      afko
      aufk
      afih
      objk
      qmih
      iloa
      iflot
      iflotx
      iflos
      equz
      equi
      eqkt
      t001w.

    -- -----------------------------------------------------------------------
    -- Session context: replaces $session.* variables from CDS
    -- CLIENT must be explicit on every table – HANA has no auto-client filter
    -- -----------------------------------------------------------------------
    DECLARE lv_clnt NVARCHAR(3);
    DECLARE lv_unam NVARCHAR(12);
    DECLARE lv_date NVARCHAR(8);
    DECLARE lv_lang NVARCHAR(1);

    lv_clnt := session_context('CLIENT');
    lv_unam := session_context('APPLICATIONUSER');
    lv_date := session_context('SAP_SYSTEM_DATE');
    lv_lang := session_context('LOCALE_SAP');

    -- -----------------------------------------------------------------------
    -- Step 1: Distinct orders for the current user
    --   PA0105 (usrty=0001) → KBED (anti-join deleted ops) → AFKO → AUFK (ZD%)
    --   → AFIH (iphas=2, released)
    --   Result: distinct aufnr + obknr + iwerk
    -- -----------------------------------------------------------------------
    lt_orders = SELECT DISTINCT ah.aufnr, ah.obknr, ah.iwerk
      FROM pa0105 AS p5
      INNER JOIN kbed AS kb
             ON  kb.mandt = :lv_clnt
             AND kb.pernr = p5.pernr
      INNER JOIN afko AS ak
             ON  ak.mandt = :lv_clnt
             AND ak.aufpl = kb.aufpl
      INNER JOIN aufk AS au
             ON  au.mandt = :lv_clnt
             AND au.aufnr = ak.aufnr
             AND au.auart LIKE 'ZD%'
      INNER JOIN afih AS ah
             ON  ah.mandt = :lv_clnt
             AND ah.aufnr = ak.aufnr
             AND ah.iphas = '2'
      WHERE  p5.mandt  = :lv_clnt
        AND  p5.usrty  = '0001'
        AND  p5.usrid  = :lv_unam
        AND  p5.begda <= :lv_date
        AND  p5.endda >= :lv_date
        AND  kb.pernr != '00000000'
        AND  NOT EXISTS (
               SELECT 1 FROM jest AS j
               WHERE  j.mandt = :lv_clnt
                 AND  j.objnr = kb.obsta
                 AND  j.inact = ''
                 AND  j.stat  IN ('I0013', 'I0076')
             );

    -- -----------------------------------------------------------------------
    -- Step 2: Object list entries (OBJK) for found orders
    -- -----------------------------------------------------------------------
    lt_objlist = SELECT
        ord.aufnr  AS orderid,
        ord.iwerk  AS planplant,
        ol.obzae   AS counter,
        ol.obknr   AS objectlistkey,
        ol.iloan   AS olist_iloan,
        ol.equnr   AS olist_equi,
        ol.ihnum   AS notifno
      FROM :lt_orders AS ord
      INNER JOIN objk AS ol
             ON  ol.mandt = :lv_clnt
             AND ol.obknr = ord.obknr;

    -- -----------------------------------------------------------------------
    -- Step 3: IloanTP for notification-based object list entries
    --   Logic (= I_ILOA_NOTIF_TP):  QMIH.iloan → ILOA.tplnr → IFLOT.iloan
    --   IloanTP is the ILOAN of the functional location the notification
    --   is installed on – needed to find the TechObject in step 5/6.
    -- -----------------------------------------------------------------------
    lt_notif_iloa = SELECT
        qm.qmnum,
        qm.equnr AS notif_equi,
        CASE WHEN COALESCE(fl.iloan, '') != ''
             THEN fl.iloan
             ELSE COALESCE(il.iloan, '')
        END AS iloan_tp
      FROM qmih AS qm
      INNER JOIN ( SELECT DISTINCT notifno
                   FROM   :lt_objlist
                   WHERE  notifno != '' ) AS nos
             ON  nos.notifno = qm.qmnum
      LEFT OUTER JOIN iloa AS il
             ON  il.mandt = :lv_clnt
             AND il.iloan = qm.iloan
             AND il.tplnr != ''              -- only ILOAs with a functional loc
      LEFT OUTER JOIN iflot AS fl
             ON  fl.mandt = :lv_clnt
             AND fl.tplnr = il.tplnr
      WHERE  qm.mandt = :lv_clnt;

    -- -----------------------------------------------------------------------
    -- Step 4: Harmonize Iloan + EquiNo  (= core logic of I_OBJLIST_CORE)
    --   Priority: direct from OBJK → via Notification → empty
    -- -----------------------------------------------------------------------
    lt_harmonized = SELECT
        ol.orderid,
        ol.planplant,
        ol.counter,
        ol.objectlistkey,
        ol.notifno,
        CASE
          WHEN COALESCE(ol.olist_iloan, '') != '' THEN ol.olist_iloan
          WHEN COALESCE(ol.notifno,     '') != '' THEN COALESCE(ni.iloan_tp, '')
          ELSE ''
        END AS iloan,
        CASE
          WHEN COALESCE(ol.olist_equi, '') != '' THEN ol.olist_equi
          WHEN COALESCE(ol.notifno,    '') != '' THEN COALESCE(ni.notif_equi, '')
          ELSE ''
        END AS equino
      FROM :lt_objlist AS ol
      LEFT OUTER JOIN :lt_notif_iloa AS ni
             ON ni.qmnum = ol.notifno;

    -- -----------------------------------------------------------------------
    -- Step 5a: Functional Location details  (= I_PM_FUNCTLOC inline)
    -- -----------------------------------------------------------------------
    lt_fl = SELECT
        fl.iloan,
        fl.iwerk,
        fl.tplnr                                    AS technical_object,
        COALESCE(sn.strno,  fl.tplnr)               AS technical_object_label,
        COALESCE(ft.pltxt,  '')                     AS technical_object_desc,
        COALESCE(fl.eqart,  '')                     AS technical_object_type,
        fl.objnr                                    AS technical_object_id,
        'EAMS_FL'                                   AS tech_obj_is_equip_or_funcloc,
        CAST('' AS NVARCHAR(18))                    AS equipment,
        COALESCE(fl.tplma,  '')                     AS parent_object,
        COALESCE(psn.strno, COALESCE(fl.tplma,''))  AS parent_label,
        CASE WHEN COALESCE(fl.tplma, '') != ''
             THEN 'EAMS_FL' ELSE ''
        END                                         AS parent_obj_is_equi_or_funcloc,
        fl.tplnr                                    AS funcloc_no
      FROM iflot AS fl
      INNER JOIN ( SELECT DISTINCT iloan
                   FROM   :lt_harmonized
                   WHERE  iloan != '' ) AS h
             ON  h.iloan = fl.iloan
      LEFT OUTER JOIN iflotx AS ft
             ON  ft.mandt = :lv_clnt
             AND ft.tplnr = fl.tplnr
             AND ft.spras = :lv_lang
      LEFT OUTER JOIN iflos AS sn            -- primary label (Kennzeichensystem)
             ON  sn.mandt = :lv_clnt
             AND sn.tplnr = fl.tplnr
             AND sn.actvs = 'X'
             AND sn.prkey = 'X'
      LEFT OUTER JOIN iflos AS psn           -- parent label
             ON  psn.mandt = :lv_clnt
             AND psn.tplnr = fl.tplma
             AND psn.actvs = 'X'
             AND psn.prkey = 'X'
      WHERE  fl.mandt = :lv_clnt;

    -- -----------------------------------------------------------------------
    -- Step 5b: Equipment details  (= I_PM_EQUIPMNT inline)
    --   Exclude mirror objects (equnr LIKE '0%'), current record only
    -- -----------------------------------------------------------------------
    lt_eq = SELECT
        ez.iloan,
        ez.iwerk,
        ez.equnr                                    AS technical_object,
        LTRIM(ez.equnr, '0')                        AS technical_object_label,
        COALESCE(et.eqktx, '')                      AS technical_object_desc,
        COALESCE(ei.eqart, '')                      AS technical_object_type,
        ei.objnr                                    AS technical_object_id,
        'EAMS_EQUI'                                 AS tech_obj_is_equip_or_funcloc,
        ez.equnr                                    AS equipment,
        COALESCE(ez.hequi, '')                      AS parent_object,
        COALESCE(ez.hequi, '')                      AS parent_label,
        CASE WHEN COALESCE(ez.hequi, '') != ''
             THEN 'EAMS_EQUI' ELSE 'EAMS_FL'
        END                                         AS parent_obj_is_equi_or_funcloc,
        CAST('' AS NVARCHAR(30))                    AS funcloc_no
      FROM equz AS ez
      INNER JOIN equi AS ei
             ON  ei.mandt = :lv_clnt
             AND ei.equnr = ez.equnr
      INNER JOIN ( SELECT DISTINCT iloan
                   FROM   :lt_harmonized
                   WHERE  iloan != '' ) AS h
             ON  h.iloan = ez.iloan
      LEFT OUTER JOIN eqkt AS et
             ON  et.mandt = :lv_clnt
             AND et.equnr = ez.equnr
             AND et.spras = :lv_lang
      WHERE  ez.mandt = :lv_clnt
        AND  ez.datbi = '99991231'
        AND  ez.eqlfn = '001'
        AND  ez.equnr LIKE '0%';

    -- -----------------------------------------------------------------------
    -- Step 5c: Union  (= I_PM_TOBJ_UNION inline)
    -- -----------------------------------------------------------------------
    lt_tobj_union = SELECT * FROM :lt_fl
                    UNION ALL
                    SELECT * FROM :lt_eq;

    -- -----------------------------------------------------------------------
    -- Step 6: Enrich with ILOA attributes + T001W 2D access control
    --   (= C_ILOA_TECHOBJ inline)
    --   ILOA filter tplnr != '' keeps only ILOAs belonging to a funcl. loc.
    --   T001W join: werks (maintenance plant from ILOA) must map to iwerk
    --   (planning plant from TechObj) – this is the 2D access control filter.
    -- -----------------------------------------------------------------------
    lt_iloa_tobj = SELECT
        tobj.technical_object,
        tobj.technical_object_label,
        tobj.technical_object_desc,
        tobj.technical_object_type,
        tobj.technical_object_id,
        tobj.tech_obj_is_equip_or_funcloc,
        tobj.parent_object,
        tobj.parent_label,
        tobj.parent_obj_is_equi_or_funcloc,
        tobj.iloan,
        tobj.iwerk,
        tobj.funcloc_no,
        il.abckz               AS abc_indicator,
        il.zz_geo_coordinates  AS key_geo_coordinates,
        il.adrnr               AS tech_obj_address_no
      FROM :lt_tobj_union AS tobj
      INNER JOIN iloa AS il
             ON  il.mandt = :lv_clnt
             AND il.iloan = tobj.iloan
             AND il.tplnr != ''
      INNER JOIN t001w AS t1w
             ON  t1w.mandt = :lv_clnt
             AND t1w.werks = il.swerk
             AND t1w.iwerk = tobj.iwerk;

    -- -----------------------------------------------------------------------
    -- Step 7: Final result – parent key logic from I_OBJLIST_BASE
    --   ParentObjectIsEquiOrFuncloc is intentionally simplified:
    --   Equipment always resolves to PARENT_FUNCLOC (equi hangs under FL).
    -- -----------------------------------------------------------------------
    result = SELECT
        h.orderid,
        h.counter,
        h.objectlistkey,
        h.iloan,
        h.notifno,
        h.equino,
        h.planplant,
        it.abc_indicator                             AS abcindicator,
        it.key_geo_coordinates                       AS keygeocoordinates,
        it.tech_obj_address_no                       AS techobjaddressno,
        it.technical_object                          AS techobjectkey,
        it.technical_object_label                    AS techobjectno,
        it.technical_object_desc                     AS techobjectdesc,
        it.technical_object_type                     AS techobjecttype,
        CAST(it.technical_object_id AS NVARCHAR(30)) AS techobjectinternalkey,
        it.tech_obj_is_equip_or_funcloc              AS techobjiseequiporfuncnlloc,
        -- Parent key: Equi-under-Equi → parent equi; otherwise → funcl. loc.
        CASE
          WHEN h.equino != '' AND it.parent_obj_is_equi_or_funcloc = 'EAMS_EQUI'
            THEN it.parent_object
          WHEN h.equino != '' AND it.parent_obj_is_equi_or_funcloc = 'EAMS_FL'
            THEN it.funcloc_no
          WHEN h.equino  = '' AND it.parent_object != ''
            THEN it.parent_object
          ELSE ''
        END                                          AS parenttechobjectkey,
        CASE
          WHEN h.equino != '' AND it.parent_obj_is_equi_or_funcloc = 'EAMS_EQUI'
            THEN 'EAMS_EQUI'
          WHEN h.equino != ''
            THEN 'PARENT_FUNCLOC'
          WHEN h.equino  = '' AND it.parent_object != ''
            THEN 'PARENT_FUNCLOC'
          ELSE ''
        END                                          AS parentobjectiseequiorfuncloc
      FROM :lt_harmonized AS h
      INNER JOIN :lt_iloa_tobj AS it
             ON  it.iloan = h.iloan
             AND it.iwerk = h.planplant;

  ENDMETHOD.

ENDCLASS.
