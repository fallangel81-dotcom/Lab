FUNCTION STATUS_TEXT_EDIT.
*"----------------------------------------------------------------------
*"*"Lokale Schnittstelle:
*"  IMPORTING
*"     VALUE(CLIENT) LIKE  SY-MANDT DEFAULT SY-MANDT
*"     VALUE(FLG_USER_STAT) TYPE  XFELD DEFAULT ' '
*"     VALUE(OBJNR) LIKE  JEST-OBJNR
*"     VALUE(ONLY_ACTIVE) TYPE  XFELD DEFAULT 'X'
*"     VALUE(SPRAS) LIKE  SY-LANGU
*"     VALUE(BYPASS_BUFFER) TYPE  XFELD DEFAULT ' '
*"  EXPORTING
*"     VALUE(ANW_STAT_EXISTING) TYPE  XFELD
*"     VALUE(E_STSMA) LIKE  JSTO-STSMA
*"     VALUE(LINE) LIKE  BSVX-STTXT
*"     VALUE(USER_LINE) LIKE  BSVX-STTXT
*"     VALUE(STONR) LIKE  TJ30-STONR
*"  EXCEPTIONS
*"      OBJECT_NOT_FOUND
*"----------------------------------------------------------------------
  DATA: TABINDEX  LIKE SY-TABIX,
        POS       TYPE I,
        FLG_NEW          ,
        STSMA     LIKE TJ20-STSMA,
        OBTYP     LIKE TJ05-OBTYP,
        LENGTH(2) TYPE N,
        HELP_LINE LIKE BSVX-STTXT,
        LINEP     LIKE TJ04-LINEP,
        LINE0     LIKE TJ04-LINEP VALUE '00',
        LINEM     LIKE TJ04-LINEP VALUE '99',
        STAT0     LIKE TJ04-STATP VALUE '00',
        STATM     LIKE TJ04-STATP VALUE '99',
        RC        LIKE SY-SUBRC.

  MANDT = CLIENT.

  REFRESH: TXT04_TAB, TXT04_TAB_U.

* überhaupt darstellbare Status vorhanden ?
  PERFORM STATUSTAB_READ TABLES STATUS_TAB_TEXT
                         USING  CLIENT OBJNR ONLY_ACTIVE OBTYP STSMA
                                RC BYPASS_BUFFER.
  IF RC NE 0.
    RAISE OBJECT_NOT_FOUND.
  ENDIF.


* Probelesen, ob überhaupt Status vorhanden sind
*  IF jest_buf-objnr NE objnr.
*    READ TABLE jest_buf WITH KEY mandt = mandt objnr = objnr
*                                 BINARY SEARCH.
*    CHECK sy-subrc = 0.
*  ENDIF.

* interne Puffer füllen
  IF NOT STSMA IS INITIAL AND ( FLG_USER_STAT NE SPACE OR
                                        STONR IS REQUESTED ).
      SELECT * FROM TJ30 INTO TABLE TJ30_BUF               "note1464947
               WHERE STSMA = STSMA.                        "note1464947
      SORT TJ30_BUF BY STSMA ESTAT.                        "note1464947

      IF TJ20-STSMA <> STSMA.                              "note1464947
        SELECT SINGLE * FROM TJ20 WHERE STSMA = STSMA.     "note1464947
      ENDIF.                                               "note1464947

      SELECT * FROM TJ30T INTO TABLE TJ30T_BUF             "note1464947
               WHERE STSMA = STSMA AND                     "note1464947
                   ( SPRAS = SPRAS OR                      "note1464947
                     SPRAS = TJ20-PFLSP ).                 "note1464947
      SORT TJ30T_BUF BY STSMA ESTAT SPRAS.                 "note1464947
  ENDIF.                                                   "note1464947

  E_STSMA = STSMA.

  LOOP AT STATUS_TAB_TEXT.

    CASE STATUS_TAB_TEXT-STAT(1).

      WHEN INTERN.
        CLEAR TXT04_TAB.
        READ TABLE TJ02_BUF WITH KEY STATUS_TAB_TEXT-STAT BINARY SEARCH.
        IF SY-SUBRC NE 0.
          TABINDEX = SY-TABIX.
          SELECT SINGLE * FROM TJ02 INTO TJ02_BUF
                                    WHERE ISTAT = STATUS_TAB_TEXT-STAT.
          INSERT TJ02_BUF INDEX TABINDEX.
        ENDIF.

* nur anzuzeigende Status miteinbeziehen
        CHECK TJ02_BUF-NODIS EQ SPACE.
        READ TABLE TJ02T_BUF WITH KEY ISTAT = STATUS_TAB_TEXT-STAT
                                      SPRAS = SPRAS BINARY SEARCH.
        IF SY-SUBRC NE 0.
          TABINDEX = SY-TABIX.
          SELECT SINGLE * FROM TJ02T INTO TJ02T_BUF
                                     WHERE ISTAT = STATUS_TAB_TEXT-STAT
                                     AND   SPRAS = SPRAS.
          IF SY-SUBRC = 0.
            INSERT TJ02T_BUF INDEX TABINDEX.
          ENDIF.
        ENDIF.
        IF SY-SUBRC = 0.
*   Text gefunden
          TXT04 = TJ02T_BUF-TXT04.
        ELSE.
*   Text in Sprache SPRAS nicht gepflegt --> SPRAS = 'D'
          READ TABLE TJ02T_BUF WITH KEY ISTAT = STATUS_TAB_TEXT-STAT
                                        SPRAS = 'D' BINARY SEARCH.
          IF SY-SUBRC NE 0.
            TABINDEX = SY-TABIX.
            SELECT SINGLE * FROM TJ02T INTO TJ02T_BUF WHERE
                                       ISTAT = STATUS_TAB_TEXT-STAT
                                       AND   SPRAS = 'D'.
            IF SY-SUBRC IS INITIAL.
              INSERT TJ02T_BUF INDEX TABINDEX.
            ENDIF.
          ENDIF.

          IF SY-SUBRC = 0.
*     Text gefunden
            TXT04 = TJ02T_BUF-TXT04.
          ELSE.
*     Text nicht gefunden
            TXT04 = SPACE.
          ENDIF.
        ENDIF.
        READ TABLE TJ04_BUF WITH KEY OBTYP = OBTYP
                                     ISTAT = STATUS_TAB_TEXT-STAT
                                     BINARY SEARCH.
        IF SY-SUBRC NE 0.
* Objekttyp im Puffer ?
          READ TABLE TJ04_OBJ WITH KEY OBTYP = OBTYP BINARY SEARCH.
          IF SY-SUBRC NE 0.
            TABINDEX = SY-TABIX.
            SELECT * FROM TJ04 APPENDING TABLE TJ04_BUF
                                               WHERE OBTYP = OBTYP.
            SORT TJ04_BUF BY OBTYP ISTAT.
            MOVE OBTYP TO TJ04_OBJ-OBTYP.
            INSERT TJ04_OBJ INDEX TABINDEX.
            READ TABLE TJ04_BUF WITH KEY OBTYP = OBTYP
                                         ISTAT = STATUS_TAB_TEXT-STAT
                                         BINARY SEARCH.
          ELSE.
* bereits im Puffer, also keine Eintraege
            SY-SUBRC = 4.
          ENDIF.
        ENDIF.
        IF SY-SUBRC = 0.
* niedriger Wert STATP bedeutet hohe Priorität
          IF TJ04_BUF-LINEP IS INITIAL.
            MOVE LINEM TO TXT04_TAB-LINEP.
          ELSE.
            TXT04_TAB-LINEP = TJ04_BUF-LINEP.           "Position 0-9
          ENDIF.
          IF TJ04_BUF-STATP IS INITIAL.
            MOVE LINEM TO TXT04_TAB-STATP.
          ELSE.
            TXT04_TAB-STATP = TJ04_BUF-STATP.           "Statuspriorität
          ENDIF.
        ELSE.
          TXT04_TAB-STATP = TXT04_TAB-LINEP = LINEM.
        ENDIF.
        MOVE STATUS_TAB_TEXT-STAT TO TXT04_TAB-STAT.
        MOVE TXT04 TO TXT04_TAB-TXT04.
        APPEND TXT04_TAB.

      WHEN EXTERN.

* nur wenn Aufbau gefordert
        CHECK FLG_USER_STAT NE SPACE OR STONR IS REQUESTED.
* nur wenn Statusschema sitzt
        CHECK STSMA NE SPACE.
* keine Anwenderstatus mit Ordnungsnummer in Zeile einstellen
        CLEAR TXT04_TAB_U.
* Puffer mit Sicherheit gefüllt
        READ TABLE TJ30T_BUF WITH KEY MANDT = MANDT
                                      STSMA = STSMA
                                      ESTAT = STATUS_TAB_TEXT-STAT
                                      SPRAS = SPRAS BINARY SEARCH.
        IF SY-SUBRC = 0.
*   Text gefunden
          TXT04_U = TJ30T_BUF-TXT04.
        ELSE.
*   Text in Sprache SPRAS nicht gepflegt --> Pflegesprache  aus TJ20
          CLEAR SY-SUBRC.
          IF TJ20-STSMA NE STSMA OR TJ20-MANDT NE MANDT.
            SELECT SINGLE * FROM TJ20 CLIENT SPECIFIED
                                      WHERE MANDT = MANDT
                                      AND   STSMA = STSMA.
          ENDIF.
          IF SY-SUBRC = 0.
            READ TABLE TJ30T_BUF WITH KEY MANDT = MANDT
                                          STSMA = STSMA
                                          ESTAT = STATUS_TAB_TEXT-STAT
                                          SPRAS = TJ20-PFLSP
                                          BINARY SEARCH.
          ENDIF.
          IF SY-SUBRC = 0.
*     Text gefunden
            TXT04_U = TJ30T_BUF-TXT04.
          ELSE.
*     Text nicht gefunden
            CLEAR: TXT04_U.
          ENDIF.
        ENDIF.
        IF TXT04_U NE SPACE.
          MOVE STATUS_TAB_TEXT-STAT TO TXT04_TAB_U-STAT.
          MOVE TXT04_U TO TXT04_TAB_U-TXT04.
        ENDIF.
* Aus TJ30_BUF pro Eintrag der TXT04_TAB_U Position und Priorität holen
        READ TABLE TJ30_BUF WITH KEY MANDT = MANDT
                                     STSMA = STSMA
                                     ESTAT = TXT04_TAB_U-STAT
                                     BINARY SEARCH.
        IF SY-SUBRC = 0 AND ( NOT TJ30_BUF-STATP IS INITIAL ).
          MOVE  TJ30_BUF-STONR TO TXT04_TAB_U-STONR.      "Ordnungsnummer
* niedriger Wert STATP bedeutet hohe Priorität
          IF TJ30_BUF-LINEP IS INITIAL.
            MOVE LINEM TO TXT04_TAB_U-LINEP.
          ELSE.
            MOVE TJ30_BUF-LINEP TO TXT04_TAB_U-LINEP.   "Position 0-9
          ENDIF.
          IF TJ30_BUF-STATP IS INITIAL.
            MOVE LINEM TO TXT04_TAB_U-STATP.
          ELSE.
            MOVE TJ30_BUF-STATP TO TXT04_TAB_U-STATP.   "Statuspriorität
          ENDIF.
        ELSE.
          MOVE LINEM TO TXT04_TAB_U-STATP.
          MOVE LINEM TO TXT04_TAB_U-LINEP.
        ENDIF.
        APPEND TXT04_TAB_U.

    ENDCASE.

  ENDLOOP.

* Status auf gleicher Position bearbeiten
  SORT TXT04_TAB BY LINEP STATP TXT04.
  CLEAR LINEP.
  LOOP AT TXT04_TAB WHERE LINEP NE LINEM.
    IF LINEP = TXT04_TAB-LINEP.
      DELETE TXT04_TAB.
    ELSE.
      LINEP = TXT04_TAB-LINEP.
    ENDIF.
  ENDLOOP.

* System-und Anwenderstatustextzeilen aufbauen
  CLEAR: LINE, POS.

* 1) Zeile der Systemstatus erstellen
  IF NOT TXT04_TAB[] IS INITIAL.
    LOOP AT TXT04_TAB TO 8.
      MOVE TXT04_TAB-TXT04 TO LINE+POS(4).
      ADD 5 TO POS.
    ENDLOOP.
    DESCRIBE TABLE TXT04_TAB LINES SY-TFILL.
    IF SY-TFILL GT 8.
      MOVE '*' TO LINE+39(1).
    ENDIF.
  ENDIF.

* 2) Zeile der Anwenderstatus erstellen

* CHECK NOT TXT04_TAB_U[] IS INITIAL.                  "DEL P30K135597
  IF NOT TXT04_TAB_U[] IS INITIAL.                     "INS P30K135597

    ANW_STAT_EXISTING = 'X'.

    CLEAR USER_LINE.

    SORT TXT04_TAB_U BY STONR DESCENDING LINEP STATP TXT04.

    CLEAR LINEP.

* Status auf gleicher Position bearbeiten (aber nicht die initialen)
    LOOP AT TXT04_TAB_U WHERE LINEP NE LINEM.
      CHECK TXT04_TAB_U-STONR IS INITIAL.
      IF LINEP = TXT04_TAB_U-LINEP.
        DELETE TXT04_TAB_U.
      ELSE.
        LINEP = TXT04_TAB_U-LINEP.
      ENDIF.
    ENDLOOP.

    CLEAR POS.
* Zeile aus Text_tabelle aufbauen.
    LOOP AT TXT04_TAB_U TO 8.
      MOVE TXT04_TAB_U-TXT04 TO USER_LINE+POS(4).
      ADD 5 TO POS.
    ENDLOOP.
    DESCRIBE TABLE TXT04_TAB_U LINES SY-TFILL.
    IF SY-TFILL GT 8.
      MOVE '*' TO USER_LINE+39(1).
    ENDIF.

  ENDIF.                                             "INS P30K135597
* Customer-Exit
  CALL CUSTOMER-FUNCTION '001'                       "#EC *
       EXPORTING
            OBJECT_NUMBER          = OBJNR
            SYSTEM_STATUS_LINE     = LINE
            USER_STATUS_LINE       = USER_LINE
       IMPORTING
            SYSTEM_STATUS_LINE_EXP = LINE
            USER_STATUS_LINE_EXP   = USER_LINE.

* ggf. Statusordnungsnummer ermitteln
  CHECK STONR IS REQUESTED.
  READ TABLE txt04_tab_u INDEX 1.
  CHECK sy-subrc = 0.
  stonr = txt04_tab_u-stonr.
ENDFUNCTION.