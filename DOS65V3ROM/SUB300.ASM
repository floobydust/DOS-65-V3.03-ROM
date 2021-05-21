        globals on
        case    off
        chip    W65C02S
        pw      132
        pl      66
;
;SUBMIT V3.00
;DOS/65 program to create $$$.SUB file from source file of type SUB and with
;parameter substitution. This program is based on the CP/M program of the same
;name.
;SUBMIT will only work with the CCM of DOS/65 V3 or later.
;Rewritten for WDC Tools - KM
; uses CMOS instructions and addressing modes.
; changes as of 14 April 2021 - KM
;
;released:              23 February 2015 (V3.00)
;
;DOS/65 constants
pzstrt  EQU     $30                     ;page zero start
PEM     EQU     $103
DflFCB  EQU     $107
DflBuf  EQU     $128
tea     EQU     $800
BufLng  EQU     4096                    ;output buffer (rbuff) length
;ASCII definitions
lf      EQU     $0A                     ;linefeed
cr      EQU     $0D                     ;carriage return
eof     EQU     $1A                     ;end of file
;
        page0
;page zero variables
        org     pzstrt                  ;start after HW registers
ErrMs                                   ;address of error message
        defs    2
;variables for MOVE
from                                    ;from pointer in MOVE
        defs    2
to                                      ;to pointer in MOVE
        defs    2
bbyte                                   ;b byte value in GetSrc
        defs    1
sbp                                     ;SUB buffer pointer
        defs    1
rbp                                     ;pointer into rbuff
        defs    2
rlen
        defs    1
ss
        defs    1
ssbp
        defs    1
PutRIn
        defs    1
readng                                  ;flag = 255 if reading source, 0 not
        defs    1
b                                       ;character active in fillrbuff
        defs    1
ichar                                   ;single char and index in makefile
        defs    1

        ends
;
        code

;code section
        org     tea
;main code - simple and straightforward
        lda     #<openms                ;send opening message
        ldy     #>openms
        jsr     MsgOut
        jsr     SETUP                   ;get everything ready
        jsr     FillRB                  ;get and process source
        jsr     MkFile                  ;prepare and save $$$.sub
boot    ldx     #0                      ;must end with warm boot
        jmp     pem                     ;using PEM
;messages and strings
OpenMs  .byte   'DOS/65 SUBMIT V3.00$'
CRLFMs  .byte   cr,lf,'$'
ERRLMs  .byte   'Error On Line $'
SUBStr  .byte   'SUB'
NSUBMs  .byte   'No .SUB File Present$'
WrErMs  .byte   'Disk Write Error$'
BfOvMs  .byte   'Command Buffer Overflow$'
ToLnMs  .byte   'Command Too Long$'
PrmEMs  .byte   'Parameter Error$'
IvClMs  .byte   'Invalid Control Character$'
DrFlMs  .byte   'Directory Full$'
NoClMs  .byte   'Cannot Close, Read/Only?$'
;
;send message pointed to by AY to console
MsgOut  ldx     #9                      ;send message out command
        jmp     PEM
;
;open file with FCB at AY
OPEN    ldx     #15
        jmp     PEM
;
;close file with FCB at AY
CLOSE   ldx     #16
        jmp     PEM
;
;delete file with FCB at AY
DELETE  ldx     #19
        jmp     PEM
;
;read from file
READ    ldx     #20
        jmp     PEM
;
;write to file
WRITE   ldx     #21
        jmp     PEM
;
;create file
MAKE    ldx     #22
        jmp     PEM
;
;move(from,to,n)
;source address (from)
;destination address (to)
;count (n)
;Parameters are passed as follows:
;x=n
;a=low of to
;y=high of to
;from must be set by calling routine
move    sta     to                      ;save to
        sty     to+1
        ldy     #0
movelp  lda     (from),y                ;get byte
        sta     (to),y                  ;put byte
        iny
        dex                             ;drop count
        bne     movelp                  ;loop if more
        rts
;
;general error handling routine
;INPUT: Specific message address = AY
;OUTPUT: none
ERROR   sta     ErrMs                   ;save error line
        sty     ErrMs+1
        lda     #<crlfms
        ldy     #>crlfms                ;send CR & LF to console
        jsr     MsgOut
        lda     #<ERRLMs                ;send main error message
        ldy     #>ERRLMs
        jsr     MsgOut
        lda     #<LneNum                ;point to line # structure
        ldy     #>LneNum
        jsr     MsgOut                  ;send to console
        lda     ErrMs                   ;point to specific message
        ldy     ErrMs+1
        jsr     msgout                  ;send to console
        jmp     boot                    ;back to CCM
;
;set up the various pointers, counters, buffers, etc.
SETUP   lda     #<dflbuf+1              ;point to second position
        ldy     #>dflbuf
        sta     from
        sty     from+1
        ldx     #127
        lda     #<sstrng
        ldy     #>sstrng
        jsr     move

        ldx     DflBuf                  ;get first byte = length
        stz     sstrng,x                ;insert 0 to mark end
        lda     #<SUBStr
        ldy     #>SUBStr
        sta     from
        sty     from+1
        ldx     #3                      ;move 3 bytes
        lda     #<dflfcb+9              ;get low
        ldy     #>dflfcb                ;get high
        jsr     move                    ;do the move

        lda     #<DskBuf                ;set disk buffer
        ldy     #>DskBuf                ;to local
        ldx     #26                     ;set buffer address
        jsr     PEM

        lda     #<dflfcb
        ldy     #>dflfcb                ;point to default FCB
        jsr     OPEN                    ;and open file
        cmp     #255                    ;check for error
        bne     STUPOK                  ;jump ahead if none
        lda     #<nsubms                ;no SUB file
        ldy     #>nsubms
        bra     ERROR                   ;do error handler
STUPOK  lda     #128                    ;set buffer pointer to
        sta     sbp                     ;to force read later
        rts
;
;GetSrc - get single byte from source file
GetSrc  ldx     sbp                     ;get buffer index
        bpl     USESBP                  ;use if 0-127
        lda     #<DflFCB                ;else point to FCB
        ldy     #>DflFCB
        jsr     read                    ;get record
        cmp     #0                      ;check return code
        beq     CLRSBP                  ;if OK clear pointer
        lda     #eof                    ;else return end of file
        rts
;start record read at start of buffer
CLRSBP  ; lda     #0                      ;clear sbp
        stz     sbp
;sbp is now 0 to 127 - we are ready to read byte
USESBP  ldx     sbp                     ;get index
        inc     sbp                     ;bump for next
        lda     DskBuf,x                ;get char from buffer
        sta     bbyte                   ;and save
        cmp     #cr                     ;see if carriage return
        bne     BNOTCR                  ;if not skip ahead
        inc     LN3                     ;if is bump LSD of line number
        lda     LN3                     ;get digit
        cmp     #'9'+1                  ;see if over '9'
        bcc     bnotcr                  ;not so use as is
        lda     #'0'                    ;but if is reset to '0'
        sta     ln3
        inc     ln2                     ;bump middle digit
        lda     ln2                     ;then get it
        cmp     #'9'+1                  ;and check it
        bcc     bnotcr                  ;skip ahead if 0 to 9
        lda     #'0'                    ;else reset middle digit
        sta     ln2
        inc     ln1                     ;then bump LSD
BNOTCR  lda     bbyte                   ;get char back
;convert to upper case
        cmp     #'a'                    ;not lower if a <
        bcc     notlc
        cmp     #'z'+1                  ;not lower if a >=
        bcs     notlc
        and     #$5f                    ;convert to upper
        sta     bbyte                   ;save it
NOTLC   lda     bbyte                   ;return it
WRBFOK  rts
;
;WrtBuf - write disk buffer to disk file
WrtBuf  lda     #<OutFCB                ;point to FCB
        ldy     #>OutFCB
        jsr     WRITE
        cmp     #0                      ;check for OK return
        beq     WRBFOK                  ;if 0 OK
        lda     #<WrErMs                ;else say write error
        ldy     #>WrErMs
        jmp     ERROR
;WRBFOK  rts
;
;Routine that reads source file and does parameter replacement
;b is the character being processed
FillRB  ; lda     #0                      ;rbuff(0) <-- 0
        stz     rbuff                   ;put "stopper" in buffer
        lda     #<rbuff
        ldy     #>rbuff                 ;set rbp to start of rbuff
        sta     rbp                     ;rbp <-- rbuff
        sty     rbp+1
        lda     #255                    ;reading <-- TRUE
        sta     readng
;do while reading TRUE
DOLp00  lda     readng                  ;test reading flag
        bne     L01                     ;continue if TRUE
        jmp     XLp00                   ;if FALSE exit
L01     ; lda     #0                      ;rlen <-- 0 that
        stz     rlen                    ;reset cmd length
;do while (b<--getsource) <> eof and b <> cr
DOLp01  jsr     GetSrc                  ;get character from source
        sta     b                       ;save it
;now check if EOF or CR
        cmp     #eof                    ;see if EOF
        bne     L02
        jmp     XLp01                   ;if so done
L02     cmp     #cr                     ;now check for CR
        bne     IfLp02
        jmp     Xlp01                   ;if so done
;if b<>lf then
IFLP02  lda     b                       ;get saved
        cmp     #lf                     ;see if LF
        beq     DoLp01                  ;if so start again
;see if $
        cmp     #'$'
        bne     Else3a                  ;is not so test ^
;if (b<--GetSrc) = $
        jsr     GetSrc                  ;get next
        sta     b                       ;save it
        cmp     #'$'                    ;see if double
        bne     Else3b                  ;jump if not
        jsr     PutRBf                  ;insert single $
        bra     DoLp01
;not double $
Else3b  lda     b                       ;prepare for subtract
;if (b <-- b-'0')
        sec                             ;use subtraction
        sbc     #'0'                    ;subtract ASCII 0
;the previous line made b a parameter counter
        sta     b                       ;save result (1 to 9)
        cmp     #9+1                    ;carry clear if a < 10
;if result <= 9 then OK else a parameter error
        bcc     Else3c                  ;then continue
        lda     #<PrmEMs                ;else parameter error
        ldy     #>PrmEMs
        jmp     ERROR
;looks like parameter so find string b in sstrng
Else3c  ; lda     #0                      ;ssbp <-- 0
        stz     ssbp                    ;start at string start
        jsr     DeBPrm                  ;find next non-blank
;do while b<>0
Else3d  lda     b                       ;get char
        beq     Else3e                  ;end if zero
        dec     b                       ;b <-- b-1
Else3f  jsr     notend                  ;scan
        bne     Else3f                  ;until end
        jsr     DeBPrm                  ;then skip spaces
        bra     Else3d                  ;loop until b=0
;ready to copy substitute string to RBuff
Else3e  jsr     notend                  ;check for end
        beq     DoLp01                  ;done if END
        lda     ss                      ;get char
        jsr     PUTRBF                  ;insert in RBuff
        bra     Else3e                  ;loop for Do While
;Else3g  bra     DoLp01
;
;else if b=^
Else3a  cmp     #'^'                    ;see if control
        bne     Else3j                  ;if not just copy
        jsr     GetSrc                  ;get next char
        sec                             ;b <-- b-'A'
        sbc     #'A'
        sta     b                       ;and save
        cmp     #26                     ;make sure A to Z
        bcc     Else3h                  ;OK if < 26
        lda     #<IvClMs                ;else invalid control char error
        ldy     #>IvClMs
        jmp     error                   ;error exit
Else3h  lda     b                       ;get char back
        clc                             ;bump by one
        adc     #1
        jsr     PutRBf                  ;put in output buffer
        jmp     DoLp01                  ;and loop
;was neither $ nor ^
Else3j  lda     b
        jsr     PutRBf                  ;so just transfer char
        jmp     DOLp01                  ;then loop
;
XLp01   ldx     #255                    ;preset for readng
        lda     b                       ;get character
        cmp     #cr                     ;see if cr
        beq     L05                     ;if so go ahead
        ldx     #0                      ;if not say readng false
L05     stx     readng
        lda     rlen                    ;store length
        jsr     PutRBf
        jmp     DOLp00                  ;loop
;XLp00   rts
;
;notend
;Return true if next char in substitute string not at end of string
;Also returns character in ss and if NOTEND returns tru pointer (ssbp)
;is advanced by one.
NOTEND  ldx     ssbp                    ;get pointer or index
        lda     sstrng,x                ;get character
        sta     ss                      ;save
        cmp     #' '                    ;see if space
        beq     NotEnF                  ;if space is end so notend false
        cmp     #0                      ;see if zero
        beq     NotEnF                  ;if 0 is end so notend false
;NOTEND is true
        inc     ssbp                    ;ssbp <-- ssbp+1
        lda     #255                    ;return true
XLp00   rts
NotEnF  lda     #0                      ;return false
NBChar  rts
;
;DeBPrm - move to next non-blank substitute string char
DeBPrm  ldx     ssbp
        lda     sstrng,x                ;get char
        cmp     #' '                    ;see if space
        bne     NBChar                  ;done if not
        inc     ssbp                    ;else bump index
        bra     DeBPrm                  ;and loop
;NBChar  rts
;
;PutRBf
;INPUT: byte in A
PutRBf  sta     PutRIn                  ;save inout character
        inc     rbp                     ;bump pointer
        bne     rbpok                   ;skip high
        inc     rbp+1                   ;else bump high
rbpok   sec
        lda     rbp                     ;check for too big
        sbc     #<lastrb
        lda     rbp+1
        sbc     #>lastrb
        bcc     RBPLEn                  ;OK if less than end + 1
        lda     #<BfOvMs                ;else buffer overflow
        ldy     #>BfOvMs
        jmp     ERROR
RBPLEn  ldy     #0                      ;clear index
        lda     PutRIn                  ;get character back
        sta     (rbp),y                 ;put in buffer
        inc     rlen
        lda     rlen                    ;bump and get record length
        cmp     #126                    ;compare to max
        bcc     NBChar                  ;OK if <126
        lda     #<ToLnMs                ;else too long error
        ldy     #>ToLnMs
        jmp     ERROR
;CMDLOK  rts
;
;MkFile creates the active command file.
MkFile  lda     #<OutFCB                ;point to FCB
        ldy     #>OutFCB
        jsr     DELETE                  ;delete it
;        lda     #0                      ;clear record number
        stz     drec
        stz     dext                    ;and extent
        lda     #<OutFCB                ;point to FCB
        ldy     #>OutFCB
        jsr     MAKE
        cmp     #255                    ;check for MAKE error
        bne     MAKEOK
        lda     #<DrFlMs                ;error - drive full
        ldy     #>DrFlMs
        jmp     ERROR
MAKEOK  jsr     GetRBf                  ;get character
        beq     LSTCHR                  ;close out if zero
        sta     ichar                   ;save
        sta     DskBuf                  ;also put in disk buffer
; buff(i+1) <-- 0 and buff(i+2) <-- '$'
        tax                             ;make i an index
;        lda     #0                      ;insert 0
        stz     DskBuf+1,x              ;into buffer
        lda     #'$'                    ;get $
        sta     DskBuf+2,x
;do while i>0
DWIGT0  ldx     ichar                   ;see if > 0
        beq     IEq0                    ;i = 0
        jsr     GetRBf                  ;else keep getting
        sta     DskBuf,x                ;and save
        dec     ichar
        bne     DWIGT0                  ;and loop for more
IEQ0    jsr     WrtBuf
        bra     MAKEOK
LSTCHR  lda     #<OutFCB                ;point to FCB
        ldy     #>OutFCB
        jsr     CLOSE
        cmp     #255
        bne     OKCLS
        lda     #<NoClMs                ;close error
        ldy     #>NoClMs
        jmp     ERROR
;OKCLS   rts
;
;GetRBf after rbp <-- rbp-1
GetRBf  sec                             ;prepare for subtraction
        lda     rbp                     ;get low
        sbc     #1                      ;subtract 1
        sta     rbp                     ;save
        lda     rbp+1                   ;do same for high
        sbc     #0
        sta     rbp+1                   ;save
;        ldy     #0                      ;clear index
        lda     (rbp)                   ;get character
OKCLS   rts
;
;line number string
LneNum  .byte   '001 $'
LN1     equ     LneNum
LN2     equ     LneNum+1
LN3     equ     LneNum+2
;Output FCB
OutFCB          .byte   0
                .byte   '$$$     SUB'
;extent
dext            .byte   0
                .byte   0,0,0
                defs    16
;record number for OutFCB
drec            .byte   0
;substitute string
sstrng
                defs    128
;disk buffer - replaces default
DskBuf
                defs    128
;read buffer
;baseline allows 32 command lines at 4096 bytes total
;If desired this can be increased.
rbuff
                defs    BufLng
lastrb
        ends

        end
