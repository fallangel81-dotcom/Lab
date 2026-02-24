class /ETN/CL_PM_VDM_IH_STATUS definition
  public
  final
  create public .

public section.

  interfaces IF_SADL_EXIT .
  interfaces IF_SADL_EXIT_FILTER_TRANSFORM .
  interfaces IF_SADL_EXIT_CALC_ELEMENT_READ .
protected section.
private section.

  types:
    "*------------------------------------------------------------------*
    "* Typen
    "*------------------------------------------------------------------*
    "! Cache-Eintrag: Objekttyp + Status-Typ als Bucket-Schlüssel
    begin of ty_status_cache,
      objecttype      type j_obtyp,    " IEQ, IFL, ORI, OVG, QMI, O2C
      is_userstatus   type abap_bool,  " abap_true = Anwenderstatus
      statuscode      type j_istat,    " I0076 / E0001
      statusshortname type j_txt04,    " FREI / RÜCK
      statusprofile   type j_stsma,    " YPM01 (nur Anwenderstatus)
    end of ty_status_cache .
  types:
    ty_status_cache_tab type standard table of ty_status_cache with non-unique key objecttype is_userstatus statusshortname .
  types:
    "! Rückgabe Lookup
    begin of ty_statuscode,
      statuscode    type j_istat,
      statusprofile type j_stsma,
    end of ty_statuscode .
  types:
    ty_statuscode_tab type standard table of ty_statuscode with empty key .
  types:
    "! Ergebnis der Feldnamen-Analyse
    begin of ty_field_mapping,
      objecttype    type j_obtyp,
      is_userstatus type abap_bool,
      is_valid      type abap_bool,
    end of ty_field_mapping .


  types:
    begin of ty_cache_loaded,
      objecttype    type j_obtyp,
      is_userstatus type abap_bool,
    end of ty_cache_loaded .

  types:
    "! Zwischenergebnis für calculate: STRING_AGG je ObjectKey
    begin of ty_status_result,
      objecttype    type j_obtyp,
      is_userstatus type abap_bool,
      objectkey     type j_objnr,
      status_concat type string,
    end of ty_status_result .
  types:
    ty_status_result_tab type table of ty_status_result with key objecttype is_userstatus objectkey .

  "*------------------------------------------------------------------*
  "* CLASS-DATA = Cache (geteilt über alle Instanzen auf Work Process)
  "*
  "* gt_cache: Pro Objekttyp + Status-Typ ein Bucket
  "*   ORI + Systemstatus:    ~30 Einträge
  "*   ORI + Anwenderstatus:  ~50 Einträge (alle Profile für ORI)
  "*
  "* gt_loaded_buckets: Welche Buckets bereits geladen sind
  "*   Lazy Loading: Bucket wird nur geladen wenn gebraucht
  "*
  "* Sicher als CLASS-DATA: Customizing ist für alle User gleich!
  "*------------------------------------------------------------------*
  class-data gt_cache type ty_status_cache_tab .
*  class-data:
*    gt_loaded_buckets type sorted table of ty_bucket_key with unique key objecttype is_userstatus .
  class-data:
    gt_cache_loaded type standard table of ty_cache_loaded with default key .
  constants:
    "*------------------------------------------------------------------*
    "* Konstanten: SAP-Objekttyp-Codes
    "*------------------------------------------------------------------*
    begin of gc_objecttype,
      order        type j_obtyp value 'ORI',
      equipment    type j_obtyp value 'IEQ',
      funcloc      type j_obtyp value 'IFL',
      operation    type j_obtyp value 'OVG',
      notification type j_obtyp value 'QMI',
      capacity     type j_obtyp value 'O2C',
    end of gc_objecttype .

  "*------------------------------------------------------------------*
  "* Private Methoden
  "*------------------------------------------------------------------*
  "! Analysiert Feldnamen per Pattern-Matching (Position egal)
  methods parse_field_name
    importing
      !iv_element       type string
    returning
      value(rs_mapping) type ty_field_mapping .
  "! Stellt Cache-Bucket sicher + Lookup
  methods determine_statuscode
    importing
      !iv_statusname        type string
      !is_mapping           type ty_field_mapping
    returning
      value(rt_statuscodes) type ty_statuscode_tab .
  "! Baut OR-verknüpfte Condition aus StatusCode-Liste
  methods build_status_condition
    importing
      !iv_is_userstatus   type abap_bool
      !it_statuscodes     type ty_statuscode_tab
      !io_cfac            type ref to if_sadl_simple_cond_factory
    returning
      value(ro_condition) type ref to if_sadl_cond_provider_generic .
  methods check_cache_loaded
    importing
      !iv_objecttype    type j_obtyp
      !iv_is_userstatus type abap_bool .
  methods load_sys_status_by_objtyp
    importing
      !iv_objecttype type j_obtyp .
  methods load_usr_status_by_objtyp
    importing
      !iv_objecttype type j_obtyp .
  methods resolve_cds_view
    importing
      !iv_objecttype    type j_obtyp
      !iv_is_userstatus type abap_bool
    returning
      value(rv_view)    type string .
ENDCLASS.



CLASS /ETN/CL_PM_VDM_IH_STATUS IMPLEMENTATION.


method parse_field_name.
  "*------------------------------------------------------------------*
  "* Pattern-Erkennung - Position im Feldnamen egal!
  "*
  "* Drei Bedingungen (alle müssen erfüllt sein):
  "*   1. Pflicht:    'STAT' enthalten
  "*   2. Objekttyp: ORDER / EQUI / xFLOC / OPER / NOTIF / CAPA
  "*   3. Typ:       SYS/SYSTEM = Systemstatus
  "*                 USR/USER   = Anwenderstatus
  "*
  "* Reihenfolge bei Objekttyp:
  "*   Spezifischere Pattern zuerst (IFLOC vor FLOC)-
  "*   Bei Überschneidung: erster Match gewinnt
  "*
  "* Reihenfolge bei Status-Typ:
  "*   SYSTEM vor SYS (SYSTEM enthält SYS als Substring!)
  "*   USER   vor USR (analog)
  "*------------------------------------------------------------------*


  "----------------------------------------------------"
  "- Großbuchstaben damit man besser vergleichen kann -"
  "----------------------------------------------------"
  data(lv_field) = to_upper( iv_element ).

  "Ergebnis der Prüfung default-mäßig auf False
  rs_mapping-is_valid = abap_false.

  "*---------------------------------------------------------------------------------------------------*
  "* Check: STAT muss enthalten sein - sonst False-Positive möglich (z.B. 'ORDERTYPE', 'EQUIPMENT')  --*
  "*---------------------------------------------------------------------------------------------------*
  check lv_field cs 'STAT'.

  "*--------------------------------------------------------------------------------------------------*
  "* Objekttyp aus View-Feldnamen erkennen und zuweisen. Spezifische zuerst IFLOC/FUNCLOC vor FLOC  --*
  "*--------------------------------------------------------------------------------------------------*
  rs_mapping-objecttype = cond #(  when lv_field cs 'ORDER'       then gc_objecttype-order        "ORI
                                   when lv_field cs 'OPER'        then gc_objecttype-operation    "OVG
                                   when lv_field cs 'CAPA'
                                     or lv_field cs 'REQ'         then gc_objecttype-capacity     "O2C

                                   when lv_field cs 'EQUI'        then gc_objecttype-equipment    "EQI
                                   when lv_field cs 'IFLOC'
                                     or lv_field cs 'FUNCTLOC'
                                     or lv_field cs 'FUNCLOC'
                                     or lv_field cs 'FLOC'        then gc_objecttype-funcloc      "IFL

                                   when lv_field cs 'NOTIF'       then gc_objecttype-notification "QMI
                                 ).

  if rs_mapping-objecttype is not initial.

    "*-----------------------------------------------------------------------*
    "* Status-Typ aus View-Feldnamen erkennen - SYSTEM/SYS vs. USER/USR    --*
    "*-----------------------------------------------------------------------*
    if lv_field cs 'SYSTEM' or lv_field cs 'SYS'.
      rs_mapping-is_valid      = abap_true.
      rs_mapping-is_userstatus = abap_false.


    elseif lv_field cs 'USER' or lv_field cs 'USR'.
      rs_mapping-is_valid      = abap_true.
      rs_mapping-is_userstatus = abap_true.

    else.
      " STAT + Objekttyp erkannt, aber kein Status-Typ
      " → Nicht eindeutig genug, nicht anfassen
      " Beispiel: 'OrderStatus' ohne SYS/USR
      return.
    endif.
  endif.

endmethod.


  method determine_statuscode.

    "----------------------------------------------------------------------------"
    "- Map Atom wird pro Filterelement aufgerufen (3 Filter = 3 Aufrufe         -"
    "- Quick check if statuscodes are already cached (Lazy loading)             -"
    "-    Nein -> Status anhand Text ermitteln und in gt_cache schreiben        -"
    "-    Ja   -> Nothing to do                                                 -"
    "----------------------------------------------------------------------------"

    me->check_cache_loaded(
      iv_objecttype    = is_mapping-objecttype      "ORI, IFL, OVG usw.
      iv_is_userstatus = is_mapping-is_userstatus   "User-/Systemstatus (andere Views für Texte TJ30T/TJ02T
    ).

    "---------------------------------------------------------------"
    "-- Lookup: Status-Kurzname → interne Code(s) aus Cache        -"
    "-- Hana DB hat Index auf StatusCode aber NICHT auf Statustext -"
    "---------------------------------------------------------------"
    rt_statuscodes = value #( for <ls_cache> in gt_cache where ( objecttype      = is_mapping-objecttype and
                                                                 is_userstatus   = is_mapping-is_userstatus and
                                                                 statusshortname = iv_statusname )
                                                               ( statuscode      = <ls_cache>-statuscode
                                                                 statusprofile   = <ls_cache>-statusprofile )
                                                               ).

    sort rt_statuscodes by statusprofile statuscode.
    delete adjacent duplicates from rt_statuscodes comparing all fields.


  endmethod.


  METHOD build_status_condition.

    "*------------------------------------------------------------------*
    "* Baut OR-verknüpfte Condition
    "*
    "* Systemstatus:
    "*   STATUSCODE = 'I0076'
    "*
    "* Anwenderstatus (Profil je Auftragsart!):
    "*   (STATUSCODE = 'E0001' AND STATUSPROFILE = 'YPM01')
    "*   OR (STATUSCODE = 'E0003' AND STATUSPROFILE = 'YPM02')
    "*------------------------------------------------------------------*

     DATA(lv_status_path)  = COND string(
      WHEN iv_is_userstatus = abap_true THEN '_userstatus.Status'
      ELSE                                   '_systemstatus.Status' ).

    LOOP AT it_statuscodes ASSIGNING FIELD-SYMBOL(<ls_code>).
*    DATA(lo_cfac) = cl_sadl_cond_prov_factory_pub=>create_simple_cond_factory( ).
*    DATA lo_conditions TYPE REF TO if_sadl_cond_provider_generic.

*    LOOP AT it_statuscodes ASSIGNING FIELD-SYMBOL(<code>).

       DATA(lo_single) = COND #(
        WHEN <ls_code>-statusprofile IS NOT INITIAL
        THEN io_cfac->element( lv_status_path )->equals( <ls_code>-statuscode )->and( io_condition =
                        io_cfac->element( '_userstatus.StatusProfile' )->equals( <ls_code>-statusprofile )
                    )
        ELSE io_cfac->element( lv_status_path )->equals( <ls_code>-statuscode )
      ).

      ro_condition = COND #(
        WHEN ro_condition IS BOUND
        THEN ro_condition->or( lo_single )
        ELSE lo_single
      ).
    ENDLOOP.

  ENDMETHOD.


  method if_sadl_exit_filter_transform~map_atom.
*&=====================================================================*
*&
*& Beschreibung:
*&   EINE Exit-Klasse für alle 12 IH-Status-Views.
*&   Erkennt anhand von Patterns im Feldnamen automatisch:
*&     - Objekttyp (Equipment, Auftrag, Vorgang, ...)
*&     - Status-Typ (System- oder Anwenderstatus)
*&
*& Feldnamen-Erkennung (flexibel - Position egal!):
*&
*&   Pflicht:       Feld muss 'STAT' enthalten
*&
*&   Objekttyp:     Feld muss eines dieser Pattern enthalten:
*&                    ORDER              → ORI
*&                    EQUI               → IEQ
*&                    IFLOC / FUNCLOC / FLOC → IFL
*&                    OPER               → OVG
*&                    NOTIF              → QMI
*&                    CAPA               → O2C
*&
*&   Status-Typ:    Feld muss eines dieser Pattern enthalten:
*&                    SYS / SYSTEM       → Systemstatus
*&                    USR / USER         → Anwenderstatus
*&
*& Beispiele gültige Feldnamen:
*&   OrderSysStatus            ✅  ORDER + SYS  + STAT
*&   MaintenanceOrderSysStatus ✅  ORDER + SYS  + STAT
*&   SysStatusOrder            ✅  ORDER + SYS  + STAT
*&   IHOrderSystemStatus       ✅  ORDER + SYSTEM + STAT
*&   OrderUsrStatus            ✅  ORDER + USR  + STAT
*&   EquiSysStatus             ✅  EQUI  + SYS  + STAT
*&   FlocSystemStat            ✅  FLOC  + SYSTEM + STAT
*&   NotifUserStat             ✅  NOTIF + USER + STAT
*&
*& Beispiele ungültige Feldnamen:
*&   OrderStatus               ❌  kein SYS/USR
*&   SysStatus                 ❌  kein Objekttyp
*&   OrderType                 ❌  kein STAT
*&
*&=====================================================================*
*& Datum:         Name:           Reason:
*& 2025-02-17     Nadine Hand     EAMR-43185_Expensive Statements
*&=====================================================================*

    if iv_entity = '/ETN/C_AC_ORDER_LIST'.


      "*------------------------------------------------------------------*
      "* SADL ruft map_atom für jedes Filter-Element(Atom) separat auf.
      "* Feldname verrät per Pattern alles was wir brauchen.
      "*------------------------------------------------------------------*
      data: lv_operator_adjusted type string,
            lv_value_adjusted    type string.

      data(lo_cfac) = cl_sadl_cond_prov_factory_pub=>create_simple_cond_factory( ).

      "*------------------------------------------------------------------*
      "* Step 1: Feldname analysieren - Objekt, User-/SystemStatus       -*
      "* Je nach Objekt wird ein anderer vorgefilterter View gesetzt     -*
      "* Je nach Statusart werden User/Systemstatus-Codes gelesen        -*
      "*------------------------------------------------------------------*
      data(ls_mapping) = me->parse_field_name( to_upper( iv_element ) ).

      "Aus dem Feldnamen konnte Objekt und Statusart ermittelt werden
      check ls_mapping-is_valid = abap_true.

      "*------------------------------------------------------------------*
      "* Step 2: Operator-Optimierung: *FREI* → FREI (EQUALS)
      "*------------------------------------------------------------------*
      lv_operator_adjusted = iv_operator.
      lv_value_adjusted    = iv_value.

      "Hana kann auf EQ besser lesen als auf *
      if iv_operator = if_sadl_exit_filter_transform~co_operator-covers_pattern
       and strlen( iv_value ) = 6
       and iv_value(1)   = '*'
       and iv_value+5    = '*'
       and iv_value+1(4) ns '*'.
        lv_operator_adjusted = if_sadl_exit_filter_transform~co_operator-equals.
        lv_value_adjusted    = iv_value+1(4).
      endif.

      "*---------------------------------------------------------------------------------------*
      "* Step 3: Operator-Handling - Status anhand Feldnamen aus Methode parse_field_name
      "*---------------------------------------------------------------------------------------*
      data(lv_status_path) = cond string( when ls_mapping-is_userstatus = abap_true
                                            then '_userstatus.Status'
                                            else '_systemstatus.Status' ).

      case lv_operator_adjusted.

        when if_sadl_exit_filter_transform~co_operator-equals.

          " ── Leerstring → NULL-Check ───────────────────────────────────
          if condense( val = iv_value ) = ''.
            ro_condition = lo_cfac->element( 'STATUS' )->is_null( ).

            " ── Zu lang → Kein gültiger Statuscode (max 4 Zeichen) ────────
          elseif strlen( lv_value_adjusted ) > 4.
            ro_condition = lo_cfac->false( ).

            " ── Normaler Filter → Lookup(StatusCode) + Condition ───────────────────────
          else.

            "------------------------------------------"
            "-- Statuscode aus Statustext ermitteln  --"
            "------------------------------------------"
            data(lt_statuscodes) = me->determine_statuscode(
              iv_statusname = lv_value_adjusted    "Bereinigter Statustext aus UI
              is_mapping    = ls_mapping           "mit ObjectTyp (ORI, QMI usw.), Statusart (User/System)
            ).

            if lt_statuscodes is not initial.
              "-----------------------------------------------------------"
              "-- Filter umbiegen auf StatusCode (statt StatusCodeText) --"
              "-----------------------------------------------------------"
              ro_condition = me->build_status_condition(
                iv_is_userstatus = ls_mapping-is_userstatus
                it_statuscodes   = lt_statuscodes
                io_cfac          = lo_cfac
              ).
            else.
              "wenn keine Texte ermittelt werden konnten - raus
              ro_condition = lo_cfac->false( ).
            endif.

          endif.

          "- Wir haben keine Wildcards - oben schon optimiert - StatusCodeText auf DB ist langsam -"
        when if_sadl_exit_filter_transform~co_operator-covers_pattern.
          " Echte Wildcards (FR*, *EI) → kein Lookup möglich
          ro_condition = lo_cfac->false( ).

        when if_sadl_exit_filter_transform~co_operator-is_null.
          ro_condition = lo_cfac->element( lv_status_path )->is_null( ).

        when others.
          " LT, GT, NE und unbekannte Operatoren ergeben bei Status keinen Sinn.
          " NE wird von SADL selbst behandelt: map_atom wird mit EQ aufgerufen,
          " SADL erzeugt daraus NOT EXISTS(...) - kein eigener WHEN-Zweig nötig.
          ro_condition = lo_cfac->false( ).

      endcase.
    endif.
  endmethod.


  method check_cache_loaded.
    "*------------------------------------------------------------------*
    "* Lazy Loading: Status zum Objekttyp nur laden wenn noch nicht geschehen
    "* SORTED TABLE mit UNIQUE KEY → READ TABLE ist O(log n)
    "*------------------------------------------------------------------*

    if not line_exists( gt_cache_loaded[ objecttype     = iv_objecttype
                                         is_userstatus  = iv_is_userstatus ] ).

      if iv_is_userstatus = abap_false.
        me->load_sys_status_by_objtyp( iv_objecttype ).
      else.
        me->load_usr_status_by_objtyp( iv_objecttype ).
      endif.

      insert value #( objecttype    = iv_objecttype
                      is_userstatus = iv_is_userstatus
                     ) into table gt_cache_loaded.

    endif.

  endmethod.


  method if_sadl_exit_calc_element_read~calculate.
    "*------------------------------------------------------------------*
    "* Anzeige von System-/Anwenderstatus als concatenierter String.
    "*
    "* Prinzip (analog map_atom + Cache, aber für Instanz-Daten):
    "*   1. Welche (Objekttyp × Status-Typ)-Kombos werden gebraucht?
    "*      → parse_field_name() wiederverwenden
    "*   2. Alle ObjectKeys aus it_original_data sammeln (eine Abfrage
    "*      für die ganze Seite, kein N+1-Problem)
    "*   3. Pro Kombo: EIN Bulk-SELECT mit STRING_AGG
    "*      → HANA erledigt die Aggregation, kein ABAP-Loop nötig
    "*   4. Ergebnis zeilenweise in ct_calculated_data schreiben
    "*      → ASSIGN COMPONENT: generisch, unabhängig vom Entity-Typ
    "*------------------------------------------------------------------*

    "*--- Schritt 1: Benötigte (Objekttyp × Status-Typ)-Kombos ermitteln ---*
    data lt_needed type sorted table of ty_cache_loaded
      with unique key objecttype is_userstatus.

    loop at it_requested_calc_elements assigning field-symbol(<elem_name>).
      data(ls_mapping) = me->parse_field_name( to_upper( <elem_name> ) ).
      check ls_mapping-is_valid = abap_true.
      if not line_exists( lt_needed[ objecttype    = ls_mapping-objecttype
                                     is_userstatus = ls_mapping-is_userstatus ] ).
        insert value #( objecttype    = ls_mapping-objecttype
                        is_userstatus = ls_mapping-is_userstatus ) into table lt_needed.
      endif.
    endloop.

    check lt_needed is not initial.

    "*--- Schritt 2: ObjectKeys aus it_original_data sammeln ---*
    data lt_keys type rseloption.

    loop at it_original_data assigning field-symbol(<ls_orig>).
      assign component 'OBJECTKEY' of structure <ls_orig> to field-symbol(<lv_objkey>).
      check sy-subrc = 0 and <lv_objkey> is not initial.
      append value #( sign = 'I' option = 'EQ' low = <lv_objkey> ) to lt_keys.
    endloop.

    sort lt_keys by low.
    delete adjacent duplicates from lt_keys comparing low.

    check lt_keys is not initial.

    "*--- Schritt 3: Bulk-SELECT STRING_AGG pro Kombo ---*
    data lt_results type ty_status_result_tab.

    loop at lt_needed assigning field-symbol(<ls_needed>).
      data(lv_view) = me->resolve_cds_view(
        iv_objecttype    = <ls_needed>-objecttype
        iv_is_userstatus = <ls_needed>-is_userstatus ).
      check lv_view is not initial.

      types: begin of ts_concat,
               objectkey     type j_objnr,
               status_concat type string,
             end of ts_concat,
             tt_concat type table of ts_concat.

      data: lt_sel type tt_concat.

      select objectkey,
             string_agg( status, ' ' order by status ) as status_concat
        from (lv_view)
        where objectkey in @lt_keys
        group by objectkey
        into table @lt_sel.


      loop at lt_sel assigning field-symbol(<ls_sel>).
         append value #( objecttype    = <ls_needed>-objecttype
                         is_userstatus = <ls_needed>-is_userstatus
                         objectkey     = <ls_sel>-objectkey
                         status_concat = <ls_sel>-status_concat ) to lt_results.
      endloop.
    endloop.

    "*--- Schritt 4: ct_calculated_data befüllen ---*
    loop at it_original_data assigning <ls_orig>.
      append initial line to ct_calculated_data assigning field-symbol(<ls_result>).
      <ls_result> = <ls_orig>.  " alle Original-Felder kopieren

      assign component 'OBJECTKEY' of structure <ls_result> to field-symbol(<key>).

      loop at it_requested_calc_elements assigning <elem_name>.
        data(ls_elem_map) = me->parse_field_name( to_upper( <elem_name> ) ).
        check ls_elem_map-is_valid = abap_true.

        data(lv_concat) = value #(
          lt_results[ objecttype    = ls_elem_map-objecttype
                      is_userstatus = ls_elem_map-is_userstatus
                      objectkey     = <key> ]-status_concat
          default '' ).

        assign component <elem_name> of structure <ls_result> to field-symbol(<field>).
        check sy-subrc = 0.
        <field> = lv_concat.
      endloop.
    endloop.

  endmethod.


  method IF_SADL_EXIT_CALC_ELEMENT_READ~GET_CALCULATION_INFO.
    "*------------------------------------------------------------------*
    "* SADL muss OBJECTKEY immer in it_original_data mitliefern,
    "* damit calculate den Bulk-SELECT aufbauen kann.
    "*------------------------------------------------------------------*
    APPEND 'OBJECTKEY' TO et_requested_orig_elements.
  endmethod.


  method LOAD_SYS_STATUS_BY_OBJTYP.

    "*------------------------------------------------------------------*
    "* Systemstatus für EINEN Objekttyp laden
    "*
    "* TJ04: Initialstatus beim Anlegen (CRTD, INTF, ...)
    "* TJ05: Business Transactions (REL, TECO, ...)
    "* TJ06: Welche Status durch Transactions gesetzt werden
    "* Kurztexte (I0076 → 'FREI')
    "*------------------------------------------------------------------*

    data lt_status_codes type standard table of j_istat.
    data lr_status_intern type range of j_istat.

    " Initialstatus
    select systemstatus from /ETN/I_INIT_SYS_STATUS
      where objecttype = @iv_objecttype
        into table @data(lt_tj04).
    if sy-subrc = 0.
      lr_status_intern = value #( for <ls_tj04> in lt_tj04 ( sign = 'I' option = 'EQ' low = <ls_tj04>-systemstatus ) ).
    endif.

    " Status aus Business Transactions ergänzen
    select systemstatus from /etn/i_sys_stat_by_objtyp
            into table @data(lt_business_stat)
             where objecttype = @iv_objecttype.
    if sy-subrc = 0.
      lr_status_intern = value #( base lr_status_intern
                                  for <ls_tj05_06> in lt_business_stat ( sign = 'I' option = 'EQ' low = <ls_tj05_06>-systemstatus ) ).
    endif.


    sort lr_status_intern by low.
    delete adjacent duplicates from lr_status_intern.

    " Kurztexte holen + in Cache schreiben
    if lr_status_intern is not initial.
      select systemstatus, systemstatusdesc
        from /etn/i_sys_stat_desc
        where systemstatus in @lr_status_intern
          and language     = @sy-langu
        into table @data(lt_result).

      insert lines of value ty_status_cache_tab(
        for <ls_result> in lt_result ( objecttype      = iv_objecttype
                                       statuscode      = <ls_result>-systemstatus
                                       statusshortname = <ls_result>-systemstatusdesc
                                       is_userstatus   = abap_false
                                       statusprofile   = ''
                                      ) ) into table gt_cache.
    endif.

  endmethod.


  method LOAD_USR_STATUS_BY_OBJTYP.
    "*------------------------------------------------------------------*
    "* Anwenderstatus für EINEN Objekttyp laden
    "*
    "* TJ21: Statusprofile je Objekttyp
    "* TJ30T: Anwenderstatus-Texte je Profil + Sprache
    "*
    "* StatusProfil muss mit in den Cache!
    "*------------------------------------------------------------------*

    select statusprofile,
           UserStatus     as StatusCode,
           UserStatusDesc as statusshortname
      from /etn/i_usr_stat_desc_by_obj
        where objecttype  = @iv_objecttype
           into table @data(lt_result).
      IF sy-subrc = 0.

    insert lines of value ty_status_cache_tab(  for <ls_result> in lt_result ( objecttype      = iv_objecttype
                                                                               is_userstatus   = abap_true
                                                                               statuscode      = <ls_result>-statuscode
                                                                               statusshortname = <ls_result>-statusshortname
                                                                               statusprofile   = <ls_result>-statusprofile
      )
    ) into table gt_cache.

    endif.

  endmethod.


  method RESOLVE_CDS_VIEW.
      "*------------------------------------------------------------------*
    "* Liefert den CDS-View-Namen für Bulk-SELECT in calculate.
    "* Jeder View filtert bereits auf den richtigen OBJNR-Prefix
    "* und den richtigen Status-Typ (I% = System, E% = Anwender).
    "*------------------------------------------------------------------*
    rv_view = COND #(
      WHEN iv_objecttype = gc_objecttype-equipment    AND iv_is_userstatus = abap_false THEN '/ETN/I_EQUI_ACT_SYS_STAT'
      WHEN iv_objecttype = gc_objecttype-equipment    AND iv_is_userstatus = abap_true  THEN '/ETN/I_EQUI_ACT_USR_STAT'
      WHEN iv_objecttype = gc_objecttype-funcloc      AND iv_is_userstatus = abap_false THEN '/ETN/I_FLOC_ACT_SYS_STAT'
      WHEN iv_objecttype = gc_objecttype-funcloc      AND iv_is_userstatus = abap_true  THEN '/ETN/I_FLOC_ACT_USR_STAT'
      WHEN iv_objecttype = gc_objecttype-notification AND iv_is_userstatus = abap_false THEN '/ETN/I_NOTIF_ACT_SYS_STAT'
      WHEN iv_objecttype = gc_objecttype-notification AND iv_is_userstatus = abap_true  THEN '/ETN/I_NOTIF_ACT_USR_STAT'
      WHEN iv_objecttype = gc_objecttype-operation    AND iv_is_userstatus = abap_false THEN '/ETN/I_OPER_ACT_SYS_STAT'
      WHEN iv_objecttype = gc_objecttype-operation    AND iv_is_userstatus = abap_true  THEN '/ETN/I_OPER_ACT_USR_STAT'
    ).
  endmethod.
ENDCLASS.