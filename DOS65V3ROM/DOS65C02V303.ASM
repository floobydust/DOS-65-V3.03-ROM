                pw      132
                pl      66
                globals on
                case    off
                inclist on
;W65C02_DOS.asm
;version 3.03-ROM
;This is the core of the ROM resident version of DOS/65
;and is derived from SYSGEN V3.02.
; The target platform is the C02 Pocket SBC - KM
;
;Changes from V2.1 to V3.0
;include:
;               added USER command and use
;               added ability to input .KIM & .HEX
;               added batch file functions
;               made directory entries per line a parameter
;               implemented use of IOSTAT to save & pass
;               drive number and user code
;               made use of SWITCH always the case
;
;released:      24 February 2015 (3.00S)
;last revised:
;               2 March 2015 (3.01S)
;                       added check of number actual sectors in image write
;                       made trkcnt separate variable
;               21 August 2015 (3.02)
;                       corrected file name parsing error
;                       set dir entries per line to 2
;               2 July 2017 (3.02W ROM)
;                       conversion to ROM
;                       eliminated pem page 0 swap
;                       corrected sysdef location
;                       changed sim references to simram
;                       set 4 wide directory in ccm
;               14 March 2021 - KM
;                       several changes to structure - saves RAM usage
;                       Page Zero start at $80 (Monitor/BIOS uses $A0 - $FF)
;                       condensed defined area - removed all SD related code
;                       removed DEFS for allocation maps, RAM initialized at coldstart
;                       moved SIM to a half-page boundary (frees up another chunk of RAM)
;                       added allocation maps for three additional drives
;                       coldstart requires 2.0 pages of RAM initialized
;                       warmstart requires 1.5 pages of RAM initialized
;                       fixed a problem with invalid drive looping on error output
;                       much reduced ROM image size ~3KB smaller
;
;               11 April 2021 - KM (3.03)
;This new version contains an updated CCM section
; uses CMOS instructions and addressing modes
; is smaller in size, at 2046 bytes
; several performance improvements due to CMOS updates
; no loss of function, but a few minor performance hits
;
;This new version contains an updated PEM section
; uses CMOS instructions and addressing modes
; is smaller in size, at 2776 bytes
; several performance improvements due to CMOS updates
;
;This program contains the complete DOS/65 operating system, including:
; CCM, PEM and SIM. All are assembled and linked to a single Intel HEX file.
; This can be loaded into ROM, but still require that the C02BIOS and C02Monitor
; are also loaded into the ROM as well. Note that the SIM section calls several
; functions from the BIOS/Monitor code via the integrated JMP tables.
; DOS/65 is booted from ROM via the C02Monitor using "Ctrl-B".
;
; ROM size is 6.5KB, which includes 512 bytes allocated for CCM/PEM/SIM RAM.
; This is copied from ROM to RAM during a Cold start for memory usage which is
; dynamic when DOS/65 is running.
;
;base addresses and definitions
pzstrt          equ     $80             ;start of page zero system RAM
btejmp          equ     $100            ;warm boot jump
pemjmp          equ     $103            ;jump to PEM
iostat          equ     $106            ;I/O status
dflfcb          equ     $107            ;default FCB
dflbuf          equ     $128            ;default buffer
tea             equ     $800            ;tea start - KM
;C02 Pocket SBC memory parameters
ramstrt         equ     $7000           ;start of high ram used by system
romstrt         equ     $C000           ;default ROM location - KM
romorg          equ     $D800           ;changed for condensed RAM image - KM
hstbuf          equ     $0600           ;moved host buffer to low RAM - KM
;
;fixed parameters
lf              equ     $0A             ;linefeeed
cr              equ     $0D             ;return
eof             equ     $1A             ;end of file
null            equ     0               ;null
ctlc            equ     3               ;abort
ctle            equ     5               ;physical cr lf
ctli            equ     9               ;tab character
ctlp            equ     $10             ;toggle printer
ctlr            equ     $12             ;repeat line
ctls            equ     $13             ;freeze
ctlx            equ     $18             ;cancel
semico          equ     $3B             ;semicolon
delete          equ     $7F             ;delete character
numcmd          equ     37              ;number of PEM commands

;page zero use
                page0
;ccm
;pem
addinp          equ     pzstrt          ;initialized to a,y
bufadd          equ     addinp+2        ;buffer address
alcpnt          equ     bufadd+2        ;allocation map pointer
chkpnt          equ     alcpnt+2        ;checksum map pointer
msgptr          equ     chkpnt+2        ;message pointer
movptr          equ     msgptr          ;and move pointer
dcbloc          equ     msgptr+2        ;pointer to dcb
;sim
sim_dmaadr      equ     dcbloc+2        ;record buffer
sim_dcbpnt      equ     sim_dmaadr+2    ;pointer into selected dcb
sim_movepnt     equ     sim_dcbpnt+2    ;read or write move host pointer
;mon
wblk_ptr        equ     sim_movepnt+2   ;pointer in write_blk
rblk_ptr        equ     wblk_ptr+2      ;pointer in read_blk
cmd_save        equ     rblk_ptr+2      ;save cmd in send_cmd
stdio_d1        equ     cmd_save+2      ;pointer for txtout

                ends

dosram          section indirect ramstrt

;RAM code and variables
;
;CCM section
;
ccmram          jmp     ccm
;input buffer
cnsbuf
cnsmax          byte    127
cnslng          byte    0
cnstxt          defs    128             ;set to 128 for safety
;fcb one
fcbone          defs    33
;SUBMIT flag = 0 if no submit operation in process
subflg          byte    0               ;=255 if sumbit
;submit FCB
subfcb          byte    0               ;will be drive A
                byte    '$$$     '      ;name field
                byte    'SUB'           ;type field
                byte    0               ;extent
                byte    0,0             ;unused
SUBRC           byte    0               ;number of records
                defs    16              ;block number area
SUBCR           byte    0               ;current record to read
;com type field
typcom          byte    "COM"
;variable storage
cnbfpt          byte    0               ;buffer index
dfldsk          byte    0               ;default drive
tmpdsk          byte    0               ;temporary drive
dsksav          byte    0               ;save default during $$$.sub ops
count           byte    0               ;counter
curpnt          byte    0               ;input parse start
diradd          byte    0               ;directory number
savx            byte    0               ;save x location
savy            byte    0               ;save y location
length          byte    0               ;number pages to save
oldtmp          byte    0               ;temp drive in ren
dskbuf          word    tea             ;disk buffer start
across          byte    0               ;dir count on line
moduls          byte    9               ;modulus-1 for number input
num             word    0               ;input number
tnum            word    0               ;temp in bldnum
sadr            word    tea             ;save start address
DoLoc           word    tea             ;GO destination
;
;PEM section
                org     $/256*256+256
pemram          jmp     pem
;pem variable storage
drvcmd          byte    0               ;new commanded drive
drvflg          byte    0               ;0 = nothing changed,
;                                       255 - drive number destroyed
usrcde          byte    0               ;user code
skpdir          byte    0               ;positive if no change
fcbind          byte    0               ;index to block number
savext          byte    0               ;save extent
frscol          byte    0               ;first col
pndkey          byte    0               ;pending input
lstflg          byte    0               ;printer flag
positn          byte    0               ;print position
cmdinp          byte    0               ;input command
addout          word    0               ;output address
bytout          equ     addout          ;output value
bufpsn          byte    0               ;input buffer position
exrwfl          byte    0               ;extend flag
tmpdrv          byte    0               ;temporary drive flag & number
countr          word    0               ;record counter
                byte    0               ;overflow
lkdown          word    0               ;down pnt. for block search
lookup          word    0               ;up pnt. for block search
olddrv          byte    0               ;old drive number
curdrv          byte    0               ;current drive
lginvc          byte    0               ;log in status
ronlst          byte    0               ;read write status
dirnum          word    0               ;directory number
subrec          byte    0               ;directory offset
recnum          word    0               ;record number
blknum          equ     recnum          ;block number
                byte    0               ;overflow
chrcnt          byte    0               ;character count
cmppnt          byte    0               ;comparison pointer
nxtrec          byte    0               ;next record
numrec          byte    0               ;number records
dirrec          word    0               ;directory record
dirmod          byte    0               ;directory mod 4
index           byte    0               ;buffer index
numcnt          byte    0               ;counter
outflg          byte    0               ;output enable flag
lstcol          byte    0               ;last column
mpdrsy          byte    0               ;save for y in mapdir
mpdrtm          byte    0               ;temp in mapdir
blmode          byte    0               ;<128 if byte else word
maxdrc          word    0               ;max directory record
sab             byte    0               ;mask for block
sxb             byte    0               ;shift for block
rtclk           byte    0,0,0           ;real time clock
gpcnt           word    0               ;gp counter
trkctr          byte    0               ;track counter
;following region is used to capture dcb
dcb
maxblk          word    0               ;maximum block number
sectrk          word    0               ;sectors per track
nsystr          word    0               ;number system tracks
blkscd          byte    0               ;block size code
maxdir          word    0               ;maximum directory number
alcmap          word    0               ;address of allocation map
chkflg          byte    0               ;check flag
chkmap          word    0               ;address of checksum map
wrtype          byte    0               ;write type 0=norm,1=dir,2=unalloc
exm             byte    0               ;extent mask
cexm1f          byte    0               ;exm complemented and 1f
;
;SIM section
; Note: the start of SIM RAM has been changed to a half-page address!
; Nothing "should" require any additional code changes.
; However (there's always one!), The XSBC123 Xmodem utility did
; require a change in the startup, as it was grabbing the jmp
; addresses for monitor routines, but assuming everything was
; on a page boundary (only grabbing the high order byte) - KM
;
                org     $/256*256+128
simram          jmp     sim_boot        ;from cold start
sim_wboote      jmp     sim_wboot       ;from warm boot
                jmp     mon_consts      ;check for input
                jmp     mon_conrde      ;get input
                jmp     mon_conwrt      ;send to terminal
                nop                     ;printer output
                nop
                rts
                nop                     ;punch output
                nop
                rts
                nop                     ;reader input
                nop
                rts
                nop                     ;home drive
                nop
                rts
                jmp     sim_seldsk      ;select disk
                jmp     sim_seltrk      ;set track
                jmp     sim_selsec      ;set sector
                jmp     sim_setdma      ;set buffer address
                jmp     sim_read        ;read sector
                jmp     sim_write       ;write sector
                lda     #1              ;printer always ready
                rts
                ldx     #128            ;clock entry - disable for now
                rts
                jmp     sim_xlate       ;translate (goes to a RTS)
;console definition block
                byte    0               ;scratch
sysdef          byte    8               ;backspace
                byte    1               ;clear to end of line
                byte    $0C             ;forward space
                byte    0               ;normal video
                byte    '^'             ;invert video
                byte    24              ;lines per screen
                byte    80              ;char per line
                byte    $0C             ;form feed
                byte    $1E             ;home
                byte    2               ;clear to end of screen
;sim data area
sim_sekdsk      byte    0               ;seek disk number
sim_hstwrt      byte    0               ;0=written,1=pending host write
;allocate the following data areas to unused ram space
sim_hstact      defs    1               ;host active flag
sim_unacnt      defs    1               ;unalloc rec cnt
sim_sektrk      defs    2               ;seek track number
sim_seksec      defs    2               ;seek sector number
sim_hstdsk      defs    1               ;host disk number
sim_hsttrk      defs    2               ;host track number
sim_hstsec      defs    2               ;host sector number
sim_sekhst      defs    2               ;seek shr secshf
sim_unadsk      defs    1               ;last unalloc disk
sim_unatrk      defs    2               ;last unalloc track
sim_unasec      defs    2               ;last unalloc sector
sim_erflag      defs    1               ;error reporting
sim_rsflag      defs    1               ;read sector flag
sim_readop      defs    1               ;1 if read operation
sim_wrtype      defs    1               ;write operation type
sim_d65spt      defs    2               ;dos/65 records/track

        org     $/256*256+256
;
;Major change here. To conserve ROM space, the allocation maps for the disk
; drives are no longer stored in ROM. Therefore, they don't need to be copied
; to RAM during a cold start. During startup, the map space shown below
; is cleared out by a routine in the SIM module. It uses bufmap and bufmapend
; as start and end addresses. - KM
;
;With other changes, enough RAM space was saved to add access and allocation
; maps for three additional drives, now from: A - G (total of 7)
; Note that the hstbuf has been moved to low RAM at $0600, which is the
; default LBA buffer for the C02BIOS. - KM
;
bufmap

;allocation and checksum maps
;drive a
almpa           equ     bufmap
;drive b
almpb           equ     almpa+512
;drive c
almpc           equ     almpb+512
;drive d
almpd           equ     almpc+512
;drive e
almpe           equ     almpd+512
;drive f
almpf           equ     almpe+512
;drive g
almpg           equ     almpf+512
;
bufmapend       equ     almpg+512

        code
;main program
        org     romstrt
;-------------------------------
;DOS/65 Console Command Module
;-------------------------------
;CCM unique definitions
nbuilt  equ     8               ;number built in commands
dirpln  equ     4               ;number dir listings per line
;entry point
CCM     bra     CCMStr
;$$$.sub related subroutines
;prepare drive A and FCB pointer for $$$.sub operation
PrpSUB  lda     dfldsk          ;get default drive
        sta     dsksav          ;save it
        stz     dfldsk          ;set default to A
        jsr     slctds          ;and select A
;set up submit FCB pointer
setsub  lda     #<subfcb        ;low
        ldy     #>subfcb
        rts
;recover disk assignments after $$$.sub ops
RcvDsk  lda     dsksav          ;return drive to default
        sta     dfldsk
        jmp     slctds          ;and select it
;delete $$$.SUB file and clear flag
delsub  jsr     setsub          ;set up FCB address
        jsr     dltfil          ;do delete
        jsr     rcvdsk          ;restore drives
stpsub  stz     subflg          ;clear submit flag
        rts
;main program
CCMStr  cld                     ;set binary mode
        lda     iostat          ;get drive and user numbers
        lsr     a               ;move user to low nibble
        lsr     a
        lsr     a
        lsr     a
        jsr     setusr          ;tell PEM user number
        lda     iostat          ;get data again
        and     #%00000111      ;mask for drive only
        sta     dfldsk          ;save it
        jsr     slctds          ;select drive
        lda     #<DflBuf        ;set default buffer
        ldy     #>DflBuf
        jsr     setbuf
        jsr     rstdsk          ;initialize system
;now see if $$$.sub file on A
        stz     subflg          ;clear submit flag
        jsr     prpsub          ;get ready for $$$.sub
        jsr     srchfr          ;search for file
;if $$$.sub file present set subflg to use file
        bmi     nosub           ;flag ok if a=255
        lda     #255            ;set flag
        sta     subflg          ;save it
        bra     ccmlpe          ;and go to main loop
nosub   jsr     rcvdsk          ;return to original default
ccmlpe  ldx     #$ff            ;set
        txs                     ;stack
        cld                     ;set binary mode
        lda     #<DflBuf        ;set default buffer
        ldy     #>DflBuf
        jsr     setbuf
        jsr     hdrout          ;send header
        lda     #'>'            ;then print
        jsr     chrout          ;prompt
;at this point we check flag for use of $$$.SUB file
        lda     subflg          ;test it
        bmi     L01
        bra     usecns          ;if clear use console
;we must use $$$.SUB file
L01     jsr     setsub          ;get FCB pointer
        jsr     openfl          ;try to open
        bpl     L02             ;use if OK
        jsr     delsub          ;get rid of file
        bra     usecns          ;use console if no open
L02     ldx     subrc           ;get record count
        dex
        stx     subcr           ;and read last record
        jsr     setsub          ;get ready for sub
        jsr     rdrcrd          ;read record
        beq     L03             ;if OK get data
        jsr     delsub          ;else clean up from EOF
        bra     usecns          ;and use console
;read was OK so move record to command buffer
L03     ldx     #0
movsub  lda     dflbuf,x        ;get char
        sta     cnslng,x        ;move it
        inx                     ;bump index
        bpl     movsub          ;loop until index 128
;now delete record
        dec     subrc           ;drop number records by one
        jsr     setsub          ;get ready for sub
        jsr     clsefl
        bpl     typbuf          ;if OK go type line
        jsr     delsub          ;then delete $$$.SUB
        bra     usecns          ;switch to console if bad
;send command line to console
typbuf  ldx     #0              ;start one past length
print0  lda     cnstxt,x        ;get char
        beq     gotend          ;done if zero
        jsr     cotsxy          ;save x and send to console
        inx
        bpl     print0          ;do next
gotend  jsr     chkcst          ;check for key pressed
        beq     nobrak          ;no break if no key
        jsr     cnsrdx          ;get key without echo
        jsr     delsub          ;stop $$$.SUB use
        jmp     ccm             ;and go back to start
;next line is the entry that stops $$$.SUB processing
usecns  lda     #<cnsbuf        ;point to start
        ldy     #>cnsbuf        ;of buffer
        jsr     rdebuf          ;do buffer read
;next line is the entry point from $$$.SUB read
nobrak  ldy     #0              ;clear index
        ldx     cnslng          ;get length
        bne     lwrupr          ;continue
        bra     ccmlp2          ;loop if empty
lwrupr  lda     cnstxt,y        ;else get char
        cmp     #'a'            ;if less than a
        bcc     nxtchg          ;skip convert
        cmp     #'z'+1          ;if over z
        bcs     nxtchg          ;skip convert
        and     #%01011111      ;else convert
        sta     cnstxt,y        ;put back in buffer
nxtchg  iny                     ;bump index
        dex                     ;count down
        bne     lwrupr          ;loop if more
        txa                     ;set a to zero
        sta     cnstxt,y        ;insert stopper
        sta     cnbfpt          ;initialize pointer
mrecmd  jsr     stdflb          ;set default buffer
        jsr     intdsk          ;get drive number
        sta     dfldsk          ;store as default
        jsr     prslin          ;parse command
        bne     cmderr          ;error if afn
        lda     tmpdsk          ;get temporary
        beq     nodrch          ;if zero ok
        lda     #nbuilt*2       ;else set and
        bra     dotrns          ;do transient
nodrch  ldx     #0              ;zero table index
        stz     count           ;and clear count
tsnxfn  ldy     #1              ;set fcb index
tsnxch  lda     fnctbl,x        ;get table entry
        beq     gotcmd          ;if zero got it
        cmp     fcbone,y        ;else test
        bne     nocmpr          ;no good if not =
        inx                     ;bump
        iny                     ;pointers
        bne     tsnxch          ;and loop
nocmpr  inx                     ;go to end
        lda     fnctbl,x        ;of table
        bne     nocmpr          ;entry
        inx                     ;point to next
        inc     count           ;bump count
        lda     count           ;and if not
        cmp     #nbuilt         ;limit then
        bne     tsnxfn          ;try next
gotcmd  lda     count           ;get count
        asl     a               ;multiply by two
dotrns  tax                     ;use as index
        jsr     ccm_cmd         ;call execute command
extcmd  jsr     rstddr          ;restore default
extwod  jsr     prslin          ;parse more
        lda     fcbone+1        ;if first
        sec                     ;character
        sbc     #' '            ;not a space
        ora     tmpdsk          ;or if temporary
        bne     cmderr          ;then an error
ccmlp2  jmp     ccmlpe          ;else loop
ccm_cmd jmp     (xqfntb,x)      ;execute command
;command error syntax handler
cmderr  jsr     ccrlf           ;do a cr lf
        ldy     curpnt          ;get command pointer
cmerlp  lda     cnstxt,y        ;get char
        beq     cmerex          ;if null then done
        cmp     #' '            ;if space
        beq     cmerex          ;then done
        jsr     cotsxy          ;output with save
        iny                     ;point to next
        bne     cmerlp          ;and loop
cmerex  lda     #'?'            ;send a
        jsr     chrout          ;question mark
        bra     ccmlp2          ;and start over
;execute dir command
; dir <afn>
dir     jsr     prslin          ;find object file
        jsr     clrslt          ;clear auto and select
        lda     #' '            ;if name
        cmp     fcbone+1        ;and
        bne     findfr          ;type are
        cmp     fcbone+9        ;not empty
        bne     findfr          ;then use it
        lda     #'?'            ;else
        ldy     #11             ;fill
fillqu  sta     fcbone,y        ;fcb
        dey                     ;with
        bne     fillqu          ;question marks
findfr  jsr     srchf1          ;search for first match
        bmi     notfnd          ;error if none
fnddir  lda     #dirpln         ;set across
        sta     across          ;to entries per line
        jsr     ccrlf           ;do a crlf
dirl    jsr     hdr             ;do header
        lda     #':'            ;then a
        jsr     chrout          ;colon
        lda     diradd          ;get number
        asl     a               ;and
        asl     a               ;multiply
        asl     a               ;by
        asl     a               ;thirty two
        asl     a               ;then
        and     #%01100000      ;mask out insignificant
        tay                     ;make a pointer
        iny                     ;and bump
        ldx     #1              ;set counter
nmelpe  lda     dflbuf,y        ;get name
        jsr     cotsxy          ;else send to console
noname  iny                     ;bump index
        inx                     ;and count
        cpx     #12             ;if count is 12
        beq     endnme          ;then done
        cpx     #9              ;or if not 9
        bne     nmelpe          ;then loop
        lda     #'.'            ;else send
        jsr     cotsxy          ;a period
        bra     nmelpe          ;and loop
endnme  jsr     chkcst          ;check console status
        bne     extdir          ;if key down quit
        jsr     setone          ;else point to fcb
        jsr     srchnx          ;else search for next
        sta     diradd          ;save number
        bmi     extdir          ;quit if not found
        dec     across          ;drop count
        beq     fnddir          ;new line if 0
        jsr     spcout          ;send one space
        jsr     spcout          ;two spaces
        bra     dirl            ;and stay
extdir  rts                     ;else done
;not found error handler
notfnd  ldy     #ntfnms         ;point to message
        bra     remsg           ;send and exit
;execute ren command
; ren <ufn> <ufn>
;where first ufn is from name and second is to name
ren     jsr     prslin          ;get old name
        bne     renerr          ;error if afn
        jsr     tmpold          ;save drive
        jsr     clrslt          ;clear auto and select
        jsr     srchf1          ;if file does not exist
        bmi     fntfnd          ;then an error
        jsr     frssec          ;move name to second half
        ldy     cnbfpt          ;get pointer
        lda     cnstxt,y        ;and then char
        cmp     #' '            ;if not a space
        bne     rensyn          ;then error
        jsr     prslin          ;get new name
        bne     rensyn          ;error if afn
        lda     tmpdsk          ;get new drive
        beq     nonwdr          ;if zero ok
        cmp     oldtmp          ;compare to old
        beq     nonwdr          ;ok if same
        sec                     ;drop for default check
        sbc     #1
        cmp     dfldsk          ;if not default
        bne     rensyn          ;is error
        lda     oldtmp          ;and then if from not
        bne     rensyn          ;default is error
nonwdr  lda     oldtmp          ;else get old
        sta     tmpdsk          ;and save
        stz     fcbone+16       ;clear fcb offset
        jsr     clrslt          ;reselect
        jsr     srchf1          ;search for old
        bpl     filexs          ;error if found
        jsr     frssec          ;swap names
        jsr     setone          ;point to fcb
        jmp     renmfl          ;and do it
;ren file exists error handler
filexs  ldy     #flexms         ;point to
        bra     remsg           ;and send
;ren syntax error handler
rensyn  jsr     rstddr          ;restore default
renerr  jmp     cmderr          ;do error
;ren source file not found error handler
fntfnd  ldy     #ntfnms         ;point to
remsg   jmp     sndmsg          ;and send
;execute save command
; save <length> <drive:>ufn (<address>)
save    lda     #<tea           ;set start address to tea start
        ldy     #>tea
        sta     sadr
        sty     sadr+1
        jsr     bldnum          ;calculate length
        bne     saverr          ;error if > 255 pages
        sta     length          ;else save low
        ora     length          ;test for zero length
        beq     saverr          ;error if is
        jsr     prslin          ;get file name
        bne     saverr          ;error if afn
        jsr     frssec          ;move name to second half
        jsr     tmpold          ;save drive
        jsr     bldnum          ;it is so find value
        ldx     fcbone+1        ;see if there
        cpx     #' '
        beq     nosadr          ;it is not
        sta     sadr            ;and set address
        sty     sadr+1
        cpy     #2              ;make sure is high enough
        bcc     saverr          ;error if not
nosadr  jsr     secfrs          ;move name back
        jsr     clrslt          ;clear auto and select
        jsr     dlt1            ;delete
        jsr     setone          ;then create
        jsr     cratfl          ;new file
        bmi     noroom          ;say no room if error
        jsr     open1           ;open file
        bmi     noopen          ;if error
        clc                     ;now find end page
        lda     sadr+1
        adc     length
        sta     length
        lda     sadr            ;get start address
        ldy     sadr+1
wrtmre  sta     dskbuf          ;set
        sty     dskbuf+1        ;buffer
        jsr     mv128           ;move data to buffer
        jsr     setone          ;point to fcb
        jsr     wrrcrd          ;write record
        bne     wrterr          ;exit if error
        clc                     ;else
        lda     dskbuf          ;get old
        ldy     dskbuf+1        ;buffer
        adc     #128            ;add 128
        bcc     donotc          ;if carry
        iny                     ;bump upper
        beq     clssav          ;done if page zero
donotc  cpy     length          ;loop if upper
        bne     wrtmre          ;not at limit
clssav  jsr     setone          ;else point to
        jsr     clsefl          ;and close file
        bmi     cantcl          ;say so if error
extera  rts
;save error handler
saverr  bra     typafn          ;do error
;save no room error handler
noroom  ldy     #nospms         ;point to
        bra     temsg           ;and send
;save can not open error handler
noopen  ldy     #cnnoms         ;point to
        bra     temsg           ;and send
;save write error handler
wrterr  ldy     #wrerms         ;point
        bra     temsg           ;to and send
;save can not close error
cantcl  ldy     #ntclms         ;point to
        bra     temsg           ;and send
;execute era command
; era <afn>
era     jsr     prslin          ;get file name
        cmp     #11             ;if not all ?
        bne     nteral          ;then skip verify
        ldy     #alflms         ;else point to
        jsr     sndmsg          ;and send all files
        jsr     cnsrde          ;get an input
        pha                     ;and save
        jsr     ccrlf           ;do a cr lf
        pla                     ;restore char
        and     #$5f            ;convert to upper case
        cmp     #'Y'            ;if not y
        bne     extera          ;then quit
nteral  jsr     clrslt          ;clear auto and select
        jmp     dlt1            ;delete first
;execute type command
; type d:ufn
type    jsr     prslin          ;get file
        bne     typafn          ;error if afn
        jsr     casdo1          ;clear - select - open file 1
        bmi     notype          ;error if not found
        jsr     ccrlf           ;else do cr lf
typmre  jsr     read1           ;read record
        beq     okread          ;if ok continue
        bpl     extera          ;exit if just end
        bmi     typerr          ;else error
okread  ldx     #0              ;clear index
typlpe  lda     dflbuf,x        ;get char
        cmp     #eof            ;if eof
        beq     extera          ;then exit
        jsr     cotsxy          ;else send
        jsr     chkcst          ;if key down
        bne     exttok          ;then exit
        ldx     savx            ;else get index
        inx                     ;bump it
        bpl     typlpe          ;and loop if < 128
        bmi     typmre          ;else read more
exttok  ldx     #6              ;clear console
        jmp     pemjmp          ;with no echo
;exttyp  rts
;type syntax error handler
typafn  jmp     cmderr          ;error return
;type read error handler
typerr  ldy     #rderms         ;point to
        bra     temsg           ;and send
;type not found error handler
notype  ldy     #ntfnms         ;point to
temsg   jmp     sndmsg          ;and send
;execute load command
; load <ufn> (<address>)
load    jsr     setddb          ;set load start to tea start
        jsr     prslin          ;build fcb
        bne     typafn          ;error if afn
        jsr     frssec          ;save in second half
        jsr     tmpold          ;save file
        jsr     bldnum          ;find start address
        ldx     fcbone+1        ;see if number
        cpx     #' '
        beq     usedfl          ;if none use default
        jsr     setdb           ;and set
usedfl  jsr     secfrs          ;move name back
        jsr     casdo1          ;clear - select - open file 1
        bmi     notype          ;exit if not found
        lda     dskbuf          ;get load start
        ldy     dskbuf+1
lcmdlp  jsr     setbuf          ;set as disk buffer
        jsr     read1           ;read record
        bne     loadnd          ;done if not zero
        jsr     adjdb           ;bump address
        bra     lcmdlp          ;and loop
loadnd  bmi     typerr          ;if error say so
        jmp     stdflb          ;back to default buffer
;execute GO command
; go (<address>)
go      jsr     bldnum          ;get address
        ldx     fcbone+1        ;get first char
        cpx     #' '            ;see if nothing
        beq     nolnum          ;nothing so use tea
        jmp     godoit          ;then execute
nolnum  jmp     gotea
;execute USER command
; user (<number>)
user    jsr     bldnum          ;build number
        ldx     fcbone+1        ;get first character
        cpx     #' '            ;see if nothing
        beq     usrext          ;done if nothing
        lda     num+1           ;check high
        bne     usrerr          ;error if too big
        lda     num             ;get low
        cmp     #16             ;see if too big
        bcs     usrerr          ;error if is
        bra     setusr          ;set if 0-15
usrext  rts
;bad user number entered
usrerr  ldy     #userms         ;get error message
        bra     temsg
;user code (usrcde) related routines
;get user code from PEM
getusr  lda     #255            ;query parameter
;set user code to A
setusr  ldx     #36             ;37th function
        jmp     pemjmp          ;execute
;Save user code in A in case of action that may
;destroy or alter it.
savusr  jsr     getusr          ;get usrcde from PEM
        asl     a               ;shift code to high nibble
        asl     a
        asl     a
        asl     a
        ora     dfldsk          ;paste default disk into
        sta     iostat          ;iostat and save
        rts
;execute trns (transient) command
; <ufn> (<fn>) (<fn>)
trns    lda     fcbone+1        ;get first char
        cmp     #' '            ;if not space
        bne     chktyp          ;check type
        lda     tmpdsk          ;else test temp
        beq     skpdrv          ;if none skip
        sec                     ;else convert
        sbc     #1              ;to number
        sta     dfldsk          ;set default
        jsr     slctds          ;and select
skpdrv  jmp     extwod          ;return
chktyp  lda     fcbone+9        ;get type
        cmp     #' '            ;if space
        beq     typemp          ;then ok
        jmp     trnerr          ;else error
typemp  ldx     #2              ;make
setcom  lda     typcom,x        ;type
        sta     fcbone+9,x      ;com
        dex                     ;then
        bpl     setcom          ;continue
        jsr     casdo1          ;clear - select - open file one
        bpl     gottrn          ;jump if ok
        jmp     topner          ;else do error
gottrn  jsr     setddb          ;set start to tea
nxtrcr  jsr     setbuf          ;set address
        jsr     read1           ;read fcb 1
        bne     endlde          ;branch if error or eof
        jsr     adjdb           ;adjust address up by 128
        cmp     #<ccmram        ;if new low
        bcc     tryhig          ;ok try high
        cpy     #>ccmram        ;else if high
        bcc     nxtrcr          ;ok do more
        bcs     chklnd          ;else check for end
tryhig  cpy     #>ccmram        ;if high less
        bcc     nxtrcr          ;then ok
        beq     nxtrcr          ;or ok if same
chklnd  jsr     stdflb          ;set buffer to default
        jsr     read1           ;read (should be eof)
        beq     tlderr          ;error if more
endlde  bmi     tlderr          ;do error
gotea   lda     #<tea           ;set go address to tea start
        ldy     #>tea
godoit  sta     DoLoc           ;set to ay
        sty     DoLoc+1
        jsr     rstddr          ;else restore default
        jsr     prslin          ;parse file
        lda     tmpdsk          ;set auto
        sta     fcbone          ;select position
        ldx     #16             ;do a second
        jsr     prsmre          ;fcb if there
        lda     tmpdsk          ;set auto select
        sta     fcbone+16       ;again
        ldy     #0              ;clear record
        sty     fcbone+32       ;counter
        ldx     #32             ;move
movfcb  lda     fcbone,x        ;all
        sta     dflfcb,x        ;to
        dex                     ;default
        bpl     movfcb          ;fcb
        inx                     ;set x to zero
tstbuf  lda     cnstxt,y        ;get char
        beq     isnull          ;if null jump
        cmp     #' '            ;or if space
        beq     isnull          ;jump
        iny                     ;else bump pointer
        bne     tstbuf          ;and loop
isnull  stz     dflbuf          ;clear count
movbuf  lda     cnstxt,y        ;get char
        sta     dflbuf+1,x      ;and move
        beq     fillov          ;exit if null
        inx                     ;increment
        iny                     ;counters
        inc     dflbuf          ;and length
        bne     movbuf          ;and loop
fillov  jsr     ccrlf           ;do a cr lf
        jsr     stdflb          ;set default
        jsr     savusr          ;save user code
        jsr     jmp_dlc         ;call execute jmp
DoRet   lda     dfldsk          ;get default
        jsr     slctds          ;and set
        jmp     ccmlpe          ;then loop
jmp_dlc jmp     (DoLoc)         ;execute
;trns syntax error handler
topner  jsr     rstddr          ;restore default
trnerr  jmp     cmderr          ;do error
;trns load error
tlderr  ldy     #lderms         ;point to
        jmp     sndmsg          ;and send
;carriage return and linefeed
ccrlf   lda     #cr             ;get a cr
        jsr     chrout          ;send
        lda     #lf             ;get a lf
        bra     chrout          ;and send
;general PEM calls
cnsrdx  ldx     #6              ;console read without echo
        bra     pemgo
cnsrde  ldx     #1              ;console read
        bra     pemgo
spcout  lda     #' '            ;output space
chrout  ldx     #2              ;console output
        bra     pemgo
rdebuf  ldx     #10             ;buffered input
        bra     pemgo
chkcst  ldx     #11             ;check console
        bra     pemgo
rstdsk  ldx     #13             ;initialize system
        bra     pemgo
slctds  ldx     #14             ;select drive
        bra     pemgo
openfl  ldx     #15             ;open file
        bra     pemgo
clsefl  ldx     #16             ;close file
        bra     pemgo
srchfr  ldx     #17             ;first match
        bra     pemgo
srchnx  ldx     #18             ;next match
        bra     pemgo
;delete file one
dlt1    jsr     setone          ;point to fcb
dltfil  ldx     #19             ;delete file
        bra     pemgo
rdrcrd  ldx     #20             ;read record
        bra     pemgo
wrrcrd  ldx     #21             ;write record
        bra     pemgo
cratfl  ldx     #22             ;create file
        bra     pemgo
renmfl  ldx     #23             ;rename file
        bra     pemgo
intdsk  ldx     #25             ;read drive num
        bra     pemgo
setbuf  ldx     #26             ;set buffer add
pemgo   jmp     pemjmp          ;go to pem
;restore default drive
rstddr  lda     tmpdsk          ;if temp drive
        beq     extddr          ;zero then exit
        sec                     ;else
        sbc     #1              ;subtract one
        cmp     dfldsk          ;compare to default
        beq     extddr          ;exit if same
seldfl  lda     dfldsk          ;else get default
        bra     slctds          ;select
;clear auto - select disk - open file at fcbone
casdo1  jsr     clrslt          ;clear auto and select
;open file one
; returns:n=1 if not found
open1   stz     fcbone+32       ;clear record number
        jsr     setone          ;point to fcb
        jsr     openfl          ;open it
        sta     diradd          ;save number
extddr  rts
;read file one
read1   jsr     setone          ;point to fcb
        bra     rdrcrd          ;do read
;search for first file one
; returns:n=1 if not found
srchf1  jsr     setone          ;point to fcb
        jsr     srchfr          ;search for first
        sta     diradd          ;save number
        rts
;header output
hdrout  jsr     ccrlf           ;do cr lf
hdr     jsr     intdsk          ;get drive number
        clc                     ;make
        adc     #'A'            ;a letter
        jsr     cotsxy          ;send drive letter
;drive letter is written now do user
        jsr     getusr          ;get number
        cmp     #10             ;see if < 10
        bcc     usr09           ;if so use as is
        pha                     ;save number
        lda     #'1'            ;else send an ASCII 1
        jsr     cotsxy          ;to console
        pla                     ;get number back
        sec                     ;drop by 10
        sbc     #10             ;and get remainder
usr09   ora     #'0'            ;make ASCII
;
;drop in to cotsxy
;
;output with save of x and y
;this routine calls the pem resident routine
;tstchr to see if a char is a printing char.
;if it is then c=1 upon return from tstchr.
cotsxy  stx     savx            ;save x
        sty     savy            ;and y
        jsr     tstchr          ;see if printing
        bcs     isprnt          ;jump if is
        pha                     ;else save
        lda     sysdef+4        ;get invert
        jsr     chrout          ;send it
        pla                     ;get char
        ora     #'@'            ;make printing
        jsr     chrout          ;send it
        lda     sysdef+3        ;get normal
isprnt  jsr     chrout          ;do output
        ldy     savy            ;get y
        ldx     savx            ;and x
        rts
;set up fcb one pointer
setone  lda     #<fcbone        ;low
        ldy     #>fcbone        ;and high
        rts
;save tmpdsk in oldtmp
tmpold  lda     tmpdsk
        sta     oldtmp
        rts
;parse command line
prslin  ldx     #0              ;clear index
prsmre  phx                     ;save index
        stz     tmpdsk          ;clear temp drive flag
        ldy     cnbfpt          ;get buffer pointer
        jsr     skpspc          ;find first non-space
        sty     curpnt          ;save index
        beq     nulchr          ;jump if null
        and     #%00001111      ;else look at 4 lsbs
        pha                     ;and save
        iny                     ;point to next char
        lda     cnstxt,y        ;and get it
        cmp     #':'            ;if a colon
        beq     drvinp          ;jump and set drive
        pla                     ;else clear stack
        dey                     ;backup index
nulchr  lda     dfldsk          ;set automatic
        sta     fcbone,x        ;to default
        bpl     trynme          ;then parse name
drvinp  pla                     ;get number
        sta     tmpdsk          ;set temp flag
        sta     fcbone,x        ;and fcb
        iny                     ;point past colon
trynme  lda     #8              ;set name count
        sta     count           ;to eight
tstnme  jsr     tstlgl          ;test for illegal
        beq     flnmsp          ;if illegal jump
        inx                     ;bump pointer
        cmp     #'*'            ;if not *
        bne     notafn          ;skip ? fill
        lda     #'?'            ;get a ?
        sta     fcbone,x        ;store
        bra     nxtout          ;and jump
notafn  sta     fcbone,x        ;store char
        iny                     ;bump source
nxtout  dec     count           ;drop counter down
        bne     tstnme          ;and loop
skpmre  jsr     tstlgl          ;if illegal
        beq     trytyp          ;try type
        iny                     ;else bump index
        bne     skpmre          ;and loop
flnmsp  inx                     ;next position
        lda     #' '            ;get a space
        sta     fcbone,x        ;store
        dec     count           ;count down
        bne     flnmsp          ;and loop
        lda     cnstxt,y        ;get char again
trytyp  pha                     ;save char
        lda     #3              ;set count
        sta     count           ;to three
        pla                     ;get char
        cmp     #'.'            ;if not .
        bne     fltysp          ;then fill spaces
        iny                     ;else bump source
tsttyp  jsr     tstlgl          ;if not legal
        beq     fltysp          ;then fill spaces
        inx                     ;else bump index
        cmp     #'*'            ;if not *
        bne     notaft          ;then skip fill
        lda     #'?'            ;else get ?
        sta     fcbone,x        ;move to fcb
        bne     mrtyfl          ;and loop
notaft  sta     fcbone,x        ;move char to fcb
        iny                     ;bump source
mrtyfl  dec     count           ;count down
        bne     tsttyp          ;and loop
nttype  jsr     tstlgl          ;if illegal
        beq     filnul          ;fill out nulls
        iny                     ;else bump source
        bne     nttype          ;and loop
fltysp  inx                     ;bump fcb pointer
        lda     #' '            ;get space
        sta     fcbone,x        ;put in fcb
        dec     count           ;count down
        bne     fltysp          ;and continue
filnul  lda     #3              ;clear
        sta     count           ;three
mrnlty  inx                     ;bump fcb pointer
        stz     fcbone,x        ;clear fcb
        dec     count           ;count down
        bne     mrnlty          ;loop until done
        sty     cnbfpt          ;update start pointer
        stz     count           ;clear count
        ply                     ;restore stack
        ldx     #11             ;counter to 11
tstqus  iny                     ;point to
        lda     fcbone,y        ;and get char
        cmp     #'?'            ;if not a ?
        bne     nxtqus          ;then jump
        inc     count           ;else bump count
nxtqus  dex                     ;loop until
        bne     tstqus          ;11 tested
        lda     count           ;get count
        rts                     ;and return
;skip space
skpspc  lda     cnstxt,y        ;get char
        beq     extskp          ;jump if null
        cmp     #' '            ;if not space
        bne     extskp          ;then exit
        iny                     ;else go to next
        bne     skpspc          ;and test
extskp  rts
;test legal
tstlgl  lda     cnstxt,y        ;get char
        beq     extlgl
        cmp     #' '            ;if space
        bcc     badinp          ;ok - less is error
        beq     extlgl
        cmp     #'='
        beq     extlgl
        cmp     #'.'
        beq     extlgl
        cmp     #':'
        beq     extlgl
        cmp     #semico
        beq     extlgl
        cmp     #'<'
        beq     extlgl
        cmp     #'>'
extlgl  rts
badinp  jmp     cmderr
;set default buffer address
stdflb  lda     #<dflbuf        ;point to
        ldy     #>dflbuf        ;location
        jmp     setbuf          ;and set
;clear automatic and select
clrslt  stz     fcbone          ;clear auto select
slttmp  lda     tmpdsk          ;get temp
        beq     extsnd          ;if zero exit
        sec                     ;else subtract
        sbc     #1              ;one
        cmp     dfldsk          ;if same as default
        beq     extsnd          ;then quit
        jmp     slctds          ;else set
;send message
sndmsg  sty     savy            ;save index
        jsr     ccrlf           ;do cr and lf
        ldy     savy            ;get index
lpesnd  lda     msgtbl,y        ;get char
        beq     extsnd          ;if null quit
        jsr     cotsxy          ;else send
        iny                     ;point to next
        bne     lpesnd          ;and loop
extsnd  rts
;set load start address
setddb  lda     #<tea           ;to tea start
        ldy     #>tea
setdb   sta     dskbuf          ;to ay
        sty     dskbuf+1
        rts
;move first part of fcb to second half
;and move second part to first part.
;only ren depends upon this routine to actually
;swap fcb halves.
;alters:a,x,p
;returns:x=$ff
frssec  ldx     #15             ;set index to last
frsclp  lda     fcbone,x        ;get byte
        ldy     fcbone+16,x
        sta     fcbone+16,x     ;move it
        tya
        sta     fcbone,x
        dex
        bpl     frsclp          ;until 16 moved
        rts
;move second part of fcb to first half
;restore tmpdsk from save location
;alters:a,x,p
;returns:x=$ff
secfrs  ldx     #15             ;set index to last
scfrlp  lda     fcbone+16,x     ;get byte
        sta     fcbone,x        ;move it
        dex
        bpl     scfrlp          ;loop until done
        lda     oldtmp          ;get old flag
        sta     tmpdsk          ;and set
        rts
;build a number from command line and leave in num
;will handle either decimal (e.g., 578) or hexadecimal (e.g., $3f2)
;move parse index past number
;modifies:all
;returns:a,y set to low and high of number
;        flags set according to y which is high part of number
bldnum  lda     #9              ;preset to decimal
        sta     moduls
        jsr     prslin          ;put in fcb
        lda     tmpdsk          ;if temp
        bne     numerr          ;is error
        sta     num             ;else clear num
        sta     num+1
        tay                     ;and index
        lda     fcbone+1,y      ;get first char
        cmp     #'$'            ;see if hex signal
        bne     bnumlp          ;skip if not
        lda     #15             ;set for modulus
        sta     moduls
        iny                     ;bump past $
bnumlp  iny                     ;next char
        lda     fcbone,y        ;get digit
        cmp     #' '            ;see if space
        beq     endnlp          ;done if is
        jsr     tstdec          ;see if decimal
        bcc     usedig          ;use if is
        jsr     tsthex          ;see if hex
        bcs     numerr          ;error if not
        sbc     #6              ;remove offset
        ldx     #15             ;test for hex modulus
        cpx     moduls
        bne     numerr          ;error if not
usedig  and     #%00001111      ;eliminate ascii bias
        pha                     ;save result
        lda     num             ;move number to temp
        sta     tnum
        lda     num+1
        sta     tnum+1
        ldx     moduls          ;get modulus
        clc
addlpe  lda     num             ;add number to itself
        adc     tnum
        sta     num
        lda     num+1           ;modulus times
        adc     tnum+1
        sta     num+1
        bcs     numerr          ;error if carry out
        dex
        bne     addlpe          ;loop if more
        pla                     ;get input back
        adc     num             ;add in
        sta     num
        bcc     bnumlp          ;loop if no carry
        inc     num+1           ;else bump high
        bne     bnumlp          ;and loop for more
;error in bldnum - handle and quit
numerr  jmp     cmderr          ;do general error
;end of use of name part - check type
endnlp  lda     fcbone+9        ;get first
        cmp     #' '            ;see if space
        bne     numerr          ;error if not
        lda     num             ;return with result
        ldy     num+1
        rts
;function entry vector table
xqfntb  .dw     dir
        .dw     save
        .dw     era
        .dw     type
        .dw     ren
        .dw     go
        .dw     load
        .dw     user
        .dw     trns
;Messages
msgtbl
;
nospms  equ     *-msgtbl
        byte    "NO SPACE",0
ntclms  equ     *-msgtbl
        byte    "CAN NOT CLOSE",0
alflms  equ     *-msgtbl
        byte    "ALL FILES (Y/N)?",0
rderms  equ     *-msgtbl
        byte    "READ ERROR",0
ntfnms  equ     *-msgtbl
        byte    "NOT FOUND",0
flexms  equ     *-msgtbl
        byte    "FILE EXISTS",0
lderms  equ     *-msgtbl
        byte    "LOAD ERROR",0
cnnoms  equ     *-msgtbl
        byte    "CAN NOT OPEN",0
wrerms  equ     *-msgtbl
        byte    "WRITE ERROR",0
userms  equ     *-msgtbl
        byte    "INVALID USER",0
;Function name table
fnctbl
        byte    "DIR ",0
        byte    "SAVE ",0
        byte    "ERA ",0
        byte    "TYPE ",0
        byte    "REN ",0
        byte    "GO ",0
        byte    "LOAD ",0
        byte    "USER ",0

        org     $/256*256+256
;---------------------------------------
;DOS/65 Primitive Execution Module (pem)
;---------------------------------------
;main program
; input:x=command,a=value,a&y=address
; returns:a=value,a&y=address
; alters:all
pem     cld                     ;set binary mode
        sta     addinp          ;value and
        sty     addinp+1        ;address
        stx     cmdinp          ;and command
        cpx     #numcmd         ;if invalid
        bcs     noswot          ;then exit without switch
        stz     tmpdrv          ;clear switch flag
        lda     cmdinp          ;get command
        asl     a               ;multiply by two
        tax                     ;and make a pointer
        lda     addinp          ;get input value
        ldy     addinp+1
        jsr     cmd_exe         ;call execute command
;The next line is the exit entry location for
;all PEM function calls.
extexq  sta     bytout          ;save value
        sty     addout+1        ;and address
;First step is to restore original drive
        lda     tmpdrv          ;see if temp drive flag set
        beq     notmpd          ;no so skip following
        lda     olddrv          ;get original number
        sta     drvcmd          ;set up like input
        jsr     chgdrv          ;change drive back
;At this point OLDDRV is mapped with USRCDE in
;byte 0 of FCB. Now clear that byte and restore
;original drive designator.
notmpd  lda     drvflg          ;get drive flag
        beq     skptmp          ;skip ahead if zero
        ldy     #0              ;clear index
        stz     drvflg          ;clear flag
        lda     tmpdrv          ;get temp drive
        sta     (addinp),y      ;put back in fcb
        stz     tmpdrv          ;clear flag
skptmp
noswot  ldy     addout+1        ;get address
        lda     bytout          ;and value (address low)
        rts
cmd_exe jmp     (cmdtbl,x)      ;execute command
;command vector table
cmdtbl  .dw     xwboot          ;warm boot (x=0)
        .dw     xcnsin          ;console input with echo (x=1)
        .dw     sndchr          ;console output (x=2)
        .dw     simram+21       ;tape reader (x=3)
        .dw     simram+18       ;tape punch (x=4)
        .dw     simram+15       ;printer output (x=5)
        .dw     getcon          ;console input w/o echo (x=6)
        .dw     xgtios          ;read i/o status (x=7)
        .dw     xstios          ;set i/o status (x=8)
        .dw     sndstr          ;print buffer (x=9)
        .dw     bufinp          ;read buffer (x=10)
        .dw     kbdsts          ;test console ready (x=11)
        .dw     simram+45       ;read list status (x=12)
        .dw     xintds          ;initialize system (x=13)
        .dw     xchgdr          ;log in drive (x=14)
        .dw     xopen           ;open file (x=15)
        .dw     xclose          ;close file (x=16)
        .dw     xfndfr          ;find first match (x=17)
        .dw     xfndnx          ;find next match (x=18)
        .dw     xdltfl          ;delete file (x=19)
        .dw     xread           ;read record (x=20)
        .dw     xwrite          ;write record (x=21)
        .dw     xmake           ;create file (x=22)
        .dw     xrenme          ;rename file (x=23)
        .dw     xintlg          ;interrogate log in status (x=24)
        .dw     xintdr          ;interrogate current drive (x=25)
        .dw     chgdma          ;set buffer address (x=26)
        .dw     xrdalv          ;read allocation map start (x=27)
        .dw     setron          ;set r/w status (x=28)
        .dw     xrdros          ;read r/w status (x=29)
        .dw     setlst          ;set list echo status (x=30)
        .dw     lststs          ;read list echo status (x=31)
        .dw     xrtclo          ;read low clock (x=32)
        .dw     xrtchi          ;read high clock (x=33)
        .dw     xrddcb          ;read dcb address (x=34)
        .dw     simram+51       ;translate sector ((x=35)
        .dw     xgsusr          ; get or set user code (x=36)
;set list echo status
setlst  sta     lstflg          ;set flag
        rts
;read list echo status
lststs  lda     lstflg          ;read flag
        rts
;execute get or set user code
xgsusr  cmp     #255            ;see if request
        beq     rtnusr          ;is so get
        sta     usrcde          ;is set so
rtnusr  lda     usrcde          ;get code
        rts
;execute warm boot
; ***this command does not return to pem***
; ***instead it jumps to sim, resets    ***
; ***system and stack and jumps to ccm. ***
xwboot  lda     usrcde          ;get user code
        asl     a               ;shift to high nibble
        asl     a
        asl     a
        asl     a
        ora     curdrv          ;add current drive
        sta     iostat          ;save for SIM
        jmp     simram+3        ;go to sim
;execute read real time clock
xrtclo  jsr     simram+48       ;read clock
        sta     rtclk           ;save low
        sty     rtclk+1         ;middle
        stx     rtclk+2         ;high
        txa
        and     #%10000000      ;test for valid
        tay
        lda     rtclk           ;get low
        rts
;execute read real time clock high
xrtchi  lda     rtclk+2         ;get high
        and     #%01111111      ;clear status
        tay
        lda     rtclk+1         ;get middle
        rts
;execute read dcb address
xrddcb  lda     dcbloc          ;get address
        ldy     dcbloc+1
        rts
;execute read i/o status
xgtios  lda     iostat          ;get status byte
        rts
;execute read allocation map starting address
xrdalv  lda     alcmap          ;get
        ldy     alcmap+1        ;starting address
        rts                     ;then return
;execute set i/o status
xstios  sta     iostat          ;set status
        rts
;execute interrogate current drive
xintdr  lda     curdrv          ;get number
        rts
;execute read log in status
xintlg  lda     lginvc          ;get status
        rts
;execute read read/write status
xrdros  lda     ronlst          ;get status
        rts
;execute find next match
xfndnx  jsr     autodr          ;auto drive select
        lda     #13             ;match including
        jmp     search          ;extent
;execute read next record
xread   jsr     autodr          ;auto drive select
        jsr     inrcct          ;initialize record counters
        lda     nxtrec          ;if next record less
        cmp     numrec          ;then number records
        bcc     tryrde          ;then try to read
        cmp     #128            ;but if not and
        beq     tryext          ;is max try to extend
rdeeof  lda     #1              ;else set eof
        rts                     ;code and return
tryext  ldx     #1              ;try for a read
        jsr     extend          ;file extension
        cmp     #0              ;if not ok exit eof
        bne     rdeeof          ;with jump back
        sta     nxtrec          ;clear next record
tryrde  jsr     getblk          ;and get block
        lda     blknum          ;if block not zero
        ora     blknum+1
        bne     dorde           ;do the read
        lda     #2              ;else set unwritten
        rts                     ;code and exit
dorde   jsr     calrcn          ;calculate record number
        jsr     sttrsc          ;set track and sector
        jsr     rdesec          ;do sector read
        jsr     updtrc          ;update counters
        lda     #0              ;return w/o error
extrde  rts
;execute file rename
xrenme  jsr     autodr          ;automatic drive select
        jsr     tstron          ;test for r/o
        lda     #12             ;match name
        jsr     frstsr          ;and type
        bmi     extren          ;exit if not found
doren   ldy     #0              ;copy user code from 0 to 16
        lda     (addinp),y
        ldy     #16             ;in new name
        sta     (addinp),y      ;part of fcb
        lda     #12             ;then move
        ldx     #16             ;new name
        jsr     dirchg          ;to directory
        lda     #12             ;see if
        jsr     search          ;another match
        bpl     doren           ;loop if found
extren  rts                     ;number
;execute delete file
xdltfl  jsr     autodr          ;automatic drive select
        jsr     tstron          ;test for r/o
        lda     #12             ;match name
        jsr     frstsr          ;and type
        bmi     extdlt          ;done if not found
dodlt   ldx     #0              ;else do a
        jsr     mapdir          ;delete
        ldy     subrec          ;then change
        lda     empty           ;byte zero to
        sta     (bufadd),y      ;empty code
        jsr     updtck          ;then update directory
        lda     #12             ;search
        jsr     search          ;for next
        bpl     dodlt           ;loop if found
extdlt  rts                     ;exit
;execute write next record
xwrite  jsr     autodr          ;automatic drive select
        jsr     tstron          ;test for r/o
        jsr     inrcct          ;initialize counters
        lda     nxtrec          ;get next record
        cmp     #128            ;compare to max
        bcc     ntexte          ;continue if less
        lda     #1              ;else flag as extend
        rts                     ;error and exit
ntexte  jsr     getblk          ;calculate block num
        stz     wrtype          ;set normal write for now
        lda     blknum          ;get it and if
        ora     blknum+1
        beq     ?E2             ;zero then get number
        jmp     blkopn          ;else go write
?E2     lda     #2              ;say unalloc write
        sta     wrtype
        lda     fcbind          ;get index from prior
        pha                     ;and save
        cmp     #16             ;if first block
        beq     isfrst          ;then don't change
        tay                     ;else make an index
        dey                     ;point to last
        bit     blmode          ;test mode
        bpl     ?P2             ;done if byte
        dey                     ;else drop for word
?P2     lda     (addinp),y      ;and get that number
        sta     blknum          ;store as starting
        iny                     ;bump for word
        lda     #0              ;preset for byte
        bit     blmode          ;test mode
        bpl     ?P3             ;done if byte
        lda     (addinp),y      ;else get high
?P3     sta     blknum+1        ;then set high
isfrst  lda     blknum          ;get block
        sta     lkdown          ;set lower and
        sta     lookup          ;upper pointers
        lda     blknum+1        ;now set high part
        sta     lkdown+1
        sta     lookup+1
srblag  lda     lookup          ;if upper pointer
        cmp     maxblk          ;not at max
        bne     upnemx          ;then keep going
        ldy     lookup+1        ;now check high
        cpy     maxblk+1
        beq     tstdwn          ;go test down
upnemx  inc     lookup          ;else bump upper
        bne     ?N2
        inc     lookup+1
?N2     lda     lkdown          ;then if lower
        ora     lkdown+1
        beq     dotest          ;is zero start test
        bne     dcdown          ;else drop lower
tstdwn  lda     lkdown          ;if upper & lower at
        ora     lkdown+1
        bne     dcdown          ;drop if not zero
        tay                     ;also set y
        beq     extsbl          ;then exit
dcdown  lda     lkdown          ;drop lower
        bne     ?N2
        dec     lkdown+1
?N2     dec     lkdown
dotest  lda     lkdown          ;get lower
        ldy     lkdown+1
        jsr     tstblk          ;and test
        bne     trylup          ;if full try upper
        lda     lkdown          ;else use lower
        ldy     lkdown+1
        bra     extsbl          ;as result
trylup  lda     lookup          ;get upper
        ldy     lookup+1
        jsr     tstblk          ;if full
        bne     srblag          ;then loop
        lda     lookup          ;else use upper
        ldy     lookup+1
extsbl  sta     blknum          ;then save number
        sty     blknum+1
        ora     blknum+1        ;see if zero
        bne     gtgood          ;then proceed
        pla                     ;clear stack
        lda     #2              ;set end
        rts                     ;of data return
gtgood  lda     blknum          ;get low again
        jsr     setblk          ;set allocation map
        pla                     ;get block
        tay                     ;pointer back
        lda     blknum          ;get number
        sta     (addinp),y      ;and put in fcb
        lda     blknum+1        ;get high
        iny
        bit     blmode          ;test mode
        bpl     blkopn          ;done if byte
        sta     (addinp),y      ;else set high
blkopn  jsr     calrcn          ;calculate record num
        jsr     sttrsc          ;set track and sector
        jsr     wrtsec          ;do write
        ldx     nxtrec          ;get next record
        cpx     numrec          ;if less than max
        bcc     notful          ;then ok
        inx                     ;else bump count
        stx     numrec          ;and save
        dex                     ;back down
notful  cpx     #127            ;if not at max
        bne     noawex          ;skip extending
        jsr     updtrc          ;update record counters
        ldx     #0              ;do write
        jsr     extend          ;file extension
        cmp     #0              ;if not ok
        bne     extwrt          ;exit
        lda     #255            ;else start counter
        sta     nxtrec          ;at one short
noawex  jsr     updtrc          ;then update counters
        lda     #0              ;good return
extwrt  rts                     ;exit
;execute console input
xcnsin  jsr     getcon          ;get input
        jsr     tstchr          ;test it and
        bcc     extxci          ;if control exit
        pha                     ;else save
        jsr     sndchr          ;echo
        pla                     ;restore
extxci  rts                     ;return
;change dma address
; input:addinp=address
; returns:none
; alters:all
chgdma  lda     addinp          ;get low
        ldy     addinp+1        ;and high address
        sta     bufadd          ;then store
        sty     bufadd+1        ;in address
        jmp     simram+36       ;then go to sim
;automatic drive select
; input:(addinp) 0=no change
; 1-8 or 'A'-'H' = change
; returns:none
; alters:all
autodr  ldy     #0              ;get
        lda     (addinp),y      ;first byte of fcb
        beq     qtatdr          ;if 0 skip drive set
        sec                     ;set carry for
        sbc     #1              ;subtract one
        and     #%00000111      ;look at three lsbs
        sta     drvcmd          ;make parameter for CHGDRV
        lda     curdrv          ;get current
        sta     olddrv          ;and save
        lda     (addinp),y      ;get fcb entry
        sta     tmpdrv          ;and save as flag
qtatdr  lda     usrcde          lget user code
        sta     (addinp),y      ;save in byte zero in fcb
        jsr     chgdrv          ;change the drive
        lda     #255            ;set flag
        sta     drvflg
drvsme  rts
;change drive
; input:addinp
; returns:none
; alters:all
xchgdr  lda     addinp          ;get inout
        sta     drvcmd          ;and save
chgdrv  lda     drvcmd          ;get input
        cmp     curdrv          ;if same as current
        beq     drvsme          ;do nothing
        sta     curdrv          ;else change current
        bra     mapdrv          ;then log it in
;drvsme  rts
;execute initialize system
; input:none
; returns:none
; alters:all,lginvc,bufadd
xintds  stz     lginvc          ;clear log in status
        lda     #<dflbuf        ;get default buffer
        ldy     #>dflbuf        ;address
        sta     addinp          ;and set up
        sty     addinp+1        ;parameters
        jsr     chgdma          ;change address
;log in drive and set pointers and maps
; input:curdrv
; returns:none
; alters:all
; patch fix - 11/03/2021
; a fix for invalid drive - loops endlessly showing
; PEM error. Fix is to load "crudrv" to "0" before
; jumping to xwboot. - KM
mapdrv  lda     curdrv          ;if current drive
        cmp     #8              ;is 0 to 7
        bcc     vlddrv          ;then log it in
drserr  jsr     errout          ;send error message
        lda     #<sltmsg        ;point to
        ldy     #>sltmsg        ;select message
        jsr     sndstr          ;and send it
        stz     curdrv          ;reset current drive (*fix)
        jmp     xwboot          ;and abort
vlddrv  jsr     simram+27       ;go to sim to set
        sta     dcbloc          ;save
        sty     dcbloc+1
        ora     dcbloc+1        ;see if invalid
        beq     drserr          ;error if is
;capture dcb
        ldy     #14-1           ;do 14 bytes
cptdcb  lda     (dcbloc),y      ;get value from sim
        sta     dcb,y           ;store it
        dey
        bpl     cptdcb          ;loop for more
        lda     blkscd          ;get block size code
        tay                     ;save in y
        clc
        adc     #3              ;convert to sxb
        sta     sxb             ;and save
        lda     sabtbl,y        ;get sab
        sta     sab             ;and set
        lda     maxdir          ;get max dir
        sta     maxdrc          ;set max dir record
        lda     maxdir+1
        lsr     a               ;divide by 4
        ror     maxdrc
        lsr     a
        ror     maxdrc
        sta     maxdrc+1        ;then save high
        stz     blmode          ;set byte mode
        lda     maxblk+1        ;branch if max block
        beq     ntm255          ;not over 255
;if y=0 when the following line is executed it means
;that the user has put an illegal combination into
;the disk definition table. may want to consider
;putting some error checking here in the future if
;there is space in pem.
        dey                     ;back up index
        sec                     ;else set mode to word
        ror     blmode
ntm255  lda     exmtbl,y        ;get extent mask
        sta     exm
        sec                     ;now calculate cexm1f
        lda     #31
        sbc     exmtbl,y
        sta     cexm1f
        ldx     curdrv          ;get drive as pointer
        lda     bitmap,x        ;get bit
        and     lginvc          ;if logged in
        bne     extstm          ;then exit
        lda     bitmap,x        ;get bit back
        ora     lginvc          ;set in log-in
        sta     lginvc          ;and update
        bra     flinal          ;then fill in maps
extstm  rts                     ;and return
;fill in allocation map
flinal  jsr     setrw           ;set to read/write
        lda     maxblk          ;divide max block by
        sta     gpcnt           ;eight to get max
        lda     maxblk+1
        ldx     #3
clcnab  lsr     a               ;use a for speed
        ror     gpcnt
        dex
        bne     clcnab          ;loop if more
        sta     gpcnt+1         ;save high
        inc     gpcnt           ;bump by one
        bne     *+5
        inc     gpcnt+1         ;with carry
        lda     alcmap          ;get map start
        ldy     alcmap+1
        sta     alcpnt          ;set pointer to start
        sty     alcpnt+1
        ldy     #0              ;clear index
clraml  lda     #0              ;clear byte
        sta     (alcpnt),y      ;put in map
        inc     alcpnt          ;bump pointer
        bne     *+4
        inc     alcpnt+1        ;with carry
        lda     gpcnt           ;get low of count
        bne     *+5             ;skip if not zero
        dec     gpcnt+1         ;else drop high
        dec     gpcnt           ;always drop low
        lda     gpcnt           ;test for zero
        ora     gpcnt+1
        bne     clraml          ;loop if more
;at this point complete map is cleared
        lda     maxdrc          ;get low of max dir record
        sta     gpcnt
        lda     maxdrc+1        ;high in a
        ldx     sxb             ;set x according to block size
clcmdb  lsr     a               ;do division
        ror     gpcnt
        dex
        bne     clcmdb          ;until x is zero
        sta     gpcnt+1         ;set high
        inc     gpcnt           ;then bump by one
        bne     *+5
        inc     gpcnt+1
        stx     blknum          ;clear block number
        stx     blknum+1
fildal  lda     blknum          ;get block number
        ldy     blknum+1
        jsr     setblk          ;set bit
        inc     blknum          ;bump block number
        bne     *+5
        inc     blknum+1
        lda     gpcnt           ;get low of count
        bne     *+5             ;skip if not zero
        dec     gpcnt+1         ;else drop high
        dec     gpcnt           ;always do low
        lda     gpcnt           ;test for zero
        ora     gpcnt+1
        bne     fildal          ;loop if more
;at this point directory space is mapped
        jsr     intdrv          ;initialize drive
        jsr     cldrnm          ;clear directory number
fillpe  ldx     #1              ;parameter for fill
        jsr     nxtdir          ;execute for next directory
        bmi     extfil          ;done if invalid
        ldy     subrec          ;get offset
        lda     (bufadd),y      ;get empty/valid flag
        cmp     #$e5            ;if empty
        beq     fillpe          ;try next
        ldx     #1              ;parameter for fill in
        jsr     mapdir          ;do directory map
        bra     fillpe          ;then loop
extfil  rts                     ;return
;initialize drive
; input:nsystr
; returns:none
; alters:all
intdrv  jsr     simram+24       ;home then
        lda     nsystr          ;get number of system tracks
        ldy     nsystr+1
        jmp     simram+30       ;and set in sim
;directory record set up
; input:dirnum
; returns:none
; alters:all,recnum,dirrec
drrcsu  lda     dirnum+1        ;move high dir number
        sta     recnum+1        ;to record number
        lda     dirnum          ;divide
        lsr     recnum+1        ;directory by four
        ror     a
        lsr     recnum+1
        ror     a
        sta     dirrec          ;and save
        sta     recnum          ;set low record number
        lda     recnum+1        ;get high
        sta     dirrec+1        ;and set
        stz     recnum+2        ;clear top byte
;set track and sector
; input:recnum
; returns:none
; alters:all,countr,trkctr
sttrsc  ldx     #0              ;clear track counter
        stx     trkctr
        stx     countr          ;and record
        stx     countr+1        ;counter
        stx     countr+2
trnxtr  lda     recnum          ;from
        cmp     countr          ;record number
        lda     recnum+1        ;and if a
        sbc     countr+1        ;borrow then
        lda     recnum+2
        sbc     countr+2
        bcc     higher          ;gone too far
        clc                     ;else
        lda     countr          ;get counter
        adc     sectrk          ;add sectors per track
        sta     countr          ;sectors per track
        lda     countr+1
        adc     sectrk+1
        sta     countr+1
        bcc     bumptr          ;done if no carry
        inc     countr+2        ;else bump high
bumptr  inx                     ;increase track count
        bne     trnxtr          ;with carry
        inc     trkctr
        bra     trnxtr          ;then loop
higher  dex                     ;back up track
        cpx     #$ff            ;see if wrap around
        bne     *+5             ;wasn't
        dec     trkctr          ;else drop high
        txa                     ;move to a
        clc                     ;add starting track
        adc     nsystr
        tax                     ;save in x
        lda     trkctr
        adc     nsystr+1
        tay                     ;move to correct registers
        txa
        jsr     simram+30       ;then set in sim
        sec                     ;back
        lda     countr          ;counter down
        sbc     sectrk          ;by sectors per track
        sta     countr          ;and save
        lda     countr+1
        sbc     sectrk+1
        sta     countr+1
        sec                     ;now
        lda     recnum          ;find difference
        sbc     countr          ;as sector
        tax                     ;save in x
        lda     recnum+1
        sbc     countr+1
        tay                     ;move to correct registers
        txa
        jsr     simram+51       ;translate
        jmp     simram+33       ;and set through sim
;get block bit mask and index
; input:a&y=block number
; returns:a=bit mask and y=0
; alters:all and alcpnt
blkmsk  pha                     ;save block number
        sty     alcpnt+1        ;including high
        ldy     #3              ;divide by eight
blkmlp  lsr     alcpnt+1        ;shift high
        ror     a
        dey                     ;loop until done
        bne     blkmlp
        clc                     ;now add map start
        adc     alcmap
        sta     alcpnt
        lda     alcpnt+1
        adc     alcmap+1
        sta     alcpnt+1
        pla                     ;get number back
        and     #%00000111      ;look at 3 lsbs
        tax                     ;get
        lda     bitmsk,x        ;mask
        rts                     ;and return
;test block
; input:a&y=block number
; returns:z=1 if unassigned
;          =0 if assigned and bit in a is set
; alters:all
tstblk  jsr     blkmsk          ;get mask and index
        and     (alcpnt),y      ;mask with map entry
        rts                     ;then return
;alter block status
; input:a&y=block number,x=1 if set
;                         =0 if reset
; returns:none
; alters:all and allocation map
altalc  cpx     #1              ;if set
        beq     setblk          ;go do it
clrblk  jsr     blkmsk          ;else get mask
        eor     #$ff            ;and complement
        and     (alcpnt),y      ;preserve others
        sta     (alcpnt),y      ;and save
        rts                     ;then return
setblk  jsr     blkmsk          ;get mask
        ora     (alcpnt),y      ;set bit
        sta     (alcpnt),y      ;and put back
        rts                     ;then return
;set current drive to read only
; input:curdrv,ronlst,bitmap
; returns:none
; alters:a,x,p and ronlst
setron  ldx     curdrv          ;get number
        lda     bitmap,x        ;and get mask
        ora     ronlst          ;or with status
        sta     ronlst          ;and put back
        rts                     ;then return
;calculate checksum of buffer @ bufadd
; input: buffer@(bufadd)
; returns:a=checksum
; alters:a,y,p
clcchk  lda     #0              ;clear accumulator
        ldy     #127            ;start at end
chkmre  clc                     ;no carry
        adc     (bufadd),y      ;add byte
        dey                     ;count down
        bpl     chkmre          ;and loop until done
        rts                     ;then return
;check read/write status
; input:curdrv,ronlst
; returns:z=0 if r/o or z=1 if r/w
; alters:a,x,p
chkron  ldx     curdrv          ;get current drive
        lda     bitmap,x        ;get mask
        and     ronlst          ;and test status
        rts
;initialize record counters from fcb
; input:fcb@(addinp)
; returns:none
; alters:a,y,p,nxtrec,numrec
inrcct  ldy     #32             ;next record offset
        lda     (addinp),y      ;get next record
        sta     nxtrec          ;and save
        ldy     #15             ;number records offset
        lda     (addinp),y      ;get number
        sta     numrec          ;and save
        rts                     ;and return
;update record counters in fcb
; input:nxtrec,numrec
; returns:none
; alters:all,fcb@(addinp)
updtrc  ldx     nxtrec          ;get next record
        inx                     ;bump it
        txa                     ;transfer
        ldy     #32             ;set offset
        sta     (addinp),y      ;and store in fcb
        lda     numrec          ;get number
        ldy     #15             ;and its offset
        sta     (addinp),y      ;and store
        rts                     ;then return
;execute open file
xopen   jsr     autodr          ;auto drive select
;open file
; input:fcb @ (addinp)
; returns:n=1 if not found,a=dirmod (255 if not found)
; alters:all
opnfle  jsr     fndf13          ;match all including extent
        bmi     extopn          ;done if not found
        lda     #12             ;point to first char
        ora     subrec          ;add offset
        tay                     ;make it a pointer
nxopmv  lda     (bufadd),y      ;get buffer contents
        tax                     ;and save
        tya                     ;save index
        and     #%00011111      ;remove offset
        tay                     ;back to index
        txa                     ;get byte back
        sta     (addinp),y      ;and store in fcb
        tya                     ;get index
        ora     subrec          ;add offset back
        tay                     ;and make index again
        iny                     ;next position
        tya                     ;if index
        and     #%00011111      ;not gone past
        bne     nxopmv          ;end then loop
;now correct extent and max records
        ldy     #12             ;point at extent in fcb
        lda     savext          ;get save from search
        cmp     (addinp),y      ;compare
        beq     extsme          ;jump ahead if same
        sta     (addinp),y      ;else change extent
        lda     #128            ;assume fcb ext < dir ext
        bcc     fcbxls          ;jump ahead if true
        asl     a               ;clear a
fcbxls  ldy     #15             ;point to max
        sta     (addinp),y      ;and set
extsme  lda     dirmod          ;else get number
extopn  rts                     ;and return
;execute close file
xclose  jsr     autodr          ;auto drive select
;close file
;if file is r/o then no actual close
;operation is performed.
; input:fcb @ (addinp)
; returns:n=1 if not valid,a=dirmod (255 if invalid)
; alters:all
clsfle  jsr     fndf13          ;match including extent
        bmi     extcls          ;exit if not found
        jsr     chkron          ;see if r/o
        bne     noclse          ;branch if is
;now set flag to ensure directory extent and number of
;records fields are only changed if necessary.
;The decision to change is determined by whether or
;not the system is closing an extent less than the
;maximum extent in the directory entry. If that is
;the case, the directory extent and number of record
;fields are not changed.
        ldy     #12             ;get extent
        lda     (addinp),y
        pha                     ;save it
        tya                     ;now look in directory
        ora     subrec
        tay
        pla                     ;get extent back
        cmp     (bufadd),y
        ror     skpdir          ;save result
;now go do it
        jsr     updtdr          ;update directory
noclse  lda     dirmod          ;get directory number
extcls  rts                     ;and return
;execute find first match
xfndfr  jsr     autodr          ;auto drive select
fndf13  lda     #13             ;match including extent
;search for first match
; input:a=number char to match
; returns:n=1 if invalid,a=dirmod (255 if invalid)
; alters:all
frstsr  pha                     ;save number to match
        jsr     cldrnm          ;clear directory number to -1
        jsr     intdrv          ;and drive
        pla                     ;get number to match
;search for directory match
; input:a=number char to match
; returns:n=1 if not found,a=dirmod (255 if invalid)
; alters:all
search  sta     chrcnt          ;save number
newtry  ldx     #0              ;set for search - ??
        stx     cmppnt          ;clear pointer
        jsr     nxtdir          ;get next entry
        bmi     exitsr          ;exit if not found
        ldx     chrcnt          ;get count
mremch  ldy     cmppnt          ;get pointer
        inc     cmppnt          ;and bump
        lda     (addinp),y      ;get fcb entry
        cpy     #12             ;see if at extent
        bne     notaex          ;jump if not
        sta     savext          ;save for later use
        pha                     ;save extent
        tya                     ;change to directory
        ora     subrec          ;coordinates
        tay
        pla                     ;get extent back
        eor     (bufadd),y      ;exclusive or with dir
        and     cexm1f          ;and with exm complement + 1f
        beq     trynxt          ;ok if zero
        bne     newtry          ;else get next directory
notaex  cmp     #'?'            ;if a ? then
        beq     trynxt          ;is a match
        pha                     ;save char
        tya                     ;then add
        ora     subrec          ;offset to
        tay                     ;make pointer
        pla                     ;get char back
        cmp     (bufadd),y      ;if not same
        bne     newtry          ;try next directory
trynxt  dex                     ;else count number down
        bne     mremch          ;and loop if more
        lda     dirmod          ;return with directory
exitsr  rts                     ;number mod 4
;calculate logical record number
; input:blknum
; returns:none
; alters:a,x,p,recnum
calrcn  ldx     sxb             ;set x according to blkscd
mulmre  asl     blknum          ;multiply block
        rol     blknum+1        ;number
        rol     blknum+2
        dex                     ;by code
        bne     mulmre
        lda     sab             ;set mask in a
        and     nxtrec          ;and with next record
        ora     recnum          ;or with number
        sta     recnum          ;and save
        rts
;update directory
updtdr  lda     #32             ;change all
        ldx     #0              ;from start
;change directory entry
; input:a=number char to change,x=starting position,fcb@(addinp)
; returns:none
; alters:all,directory,checksums
dirchg  sta     chrcnt          ;save count
        dec     chrcnt          ;back up
mrechg  clc                     ;clear carry
        txa                     ;get offset
        adc     chrcnt          ;compute index
        tay                     ;and set
        cpy     #12             ;see if at extent
        beq     docare          ;if so do special
        cpy     #15             ;see if at number rec
        bne     dntcar          ;if not skip
docare  bit     skpdir          ;check flag
        bpl     nochng          ;skip if ok
dntcar  lda     (addinp),y      ;get char
        pha                     ;save it
        lda     chrcnt          ;get count
        ora     subrec          ;add offset
        tay                     ;make an index
        pla                     ;get char back
        sta     (bufadd),y      ;and put in buffer
nochng  dec     chrcnt          ;count down
        bpl     mrechg          ;and loop
        jsr     drrcsu          ;set it up
        jmp     updtck          ;and do change
;execute create file
xmake   jsr     autodr          ;auto drive select
;create file
; input:fcb@(addinp)
; returns:n=1 if not valid,a=dirmod (255 if not valid)
; alters:dirnum,dirmod,fcb@(addinp)
mkefle  jsr     tstron          ;test for r/o
        lda     addinp          ;save fcb
        pha                     ;address
        lda     addinp+1        ;on
        pha                     ;stack
        lda     #<empty         ;then point
        ldy     #>empty         ;to empty
        sta     addinp          ;dummy
        sty     addinp+1        ;fcb
        lda     #1              ;match only
        jsr     frstsr          ;first char
        pla                     ;restore
        sta     addinp+1        ;fcb
        pla                     ;address
        sta     addinp          ;from stack
        lda     dirmod          ;get number mod 4
        bmi     extmke          ;quit if not found
        ldy     #13             ;else set up
        lda     #0              ;to clear
mkeagn  sta     (addinp),y      ;rest of
        iny                     ;fcb
        cpy     #33             ;including next
        bne     mkeagn          ;record
;the next two lines ensure that the extent and
;number of records fields are updated
        sec
        ror     skpdir
        jsr     updtdr          ;update directory
        lda     dirmod          ;get number
extmke  rts                     ;and quit
;extend file
; input:fcb@(addinp), x=1 read
;                       0 write
extend  stx     exrwfl          ;save parameter
        jsr     clsfle          ;close current extent
        bmi     extext          ;exit if not found
        ldy     #12             ;else
        lda     (addinp),y      ;get extent
        clc                     ;and
        adc     #1              ;add one
        and     #%00011111      ;see if overflow
        beq     exteof          ;eof if so
        sta     (addinp),y      ;and save
        jsr     fndf13          ;see if next extent exists
        bpl     opnext          ;if so open
        lda     exrwfl          ;if not and is write then create
        bne     extext          ;else return as eof
dwrtex  jsr     mkefle          ;create file
        bra     tstext          ;and test
opnext  jsr     opnfle          ;open
tstext  bpl     extnok          ;continue if ok
exteof  lda     #1              ;else set eof
        rts                     ;and return
extnok  jsr     inrcct          ;initialize counters
        lda     #0              ;good
extext  rts                     ;return
;set up next directory block
; input:dirnum,x=1 for update checksum
; returns:a=dirmod (255 if invalid),n=1 if invalid
; alters:alll,dirnum,dirmod
nxtdir  phx                     ;save operation on stack
        inc     dirnum          ;bump directory
        bne     *+5
        inc     dirnum+1
        lda     maxdir          ;if not at limit continue
        cmp     dirnum
        lda     maxdir+1
        sbc     dirnum+1
        bcs     gtnxdr          ;then continue
        plx                     ;else clear stack/set x
        jmp     cldrnm          ;set to invalid
gtnxdr  lda     dirnum          ;get low again
        and     #%00000011      ;look at 2 lsbs
        sta     dirmod          ;save mod 4
        asl     a               ;multiply
        asl     a               ;by
        asl     a               ;32 to
        asl     a               ;get pointer
        asl     a               ;offset
        sta     subrec          ;and save
        beq     getdir          ;if zero read new
        plx                     ;else clear stack/set x
        bra     gotdir          ;and exit
getdir  jsr     drrcsu          ;set up to read
        jsr     rdesec          ;do read
        plx                     ;get operation code
        jsr     chksop          ;do it
gotdir  lda     dirmod          ;and return
exnxdr  rts                     ;with number
;checksum operation
;this routine assumes calling routine has checked for
;valid dirnum and hence valid dirrec
; input:chkflg,dirrec,x (1=update else check)
; returns:none
; alters:map@(chkmap)
chksop  bit     chkflg          ;check flag
        bmi     exnxdr          ;done if set
        dex                     ;dec code
        bne     tstchk          ;if not zero test
        jsr     clcchk          ;else calculate
        jsr     clcckp          ;calculate pointer
        sta     (chkpnt),y      ;and save
        rts                     ;then return
tstchk  jsr     clcchk          ;do calculation
        jsr     clcckp          ;calculate pointer
        cmp     (chkpnt),y      ;compare to old
        beq     exnxdr          ;if equal ok
        jmp     setron          ;else set to r/o
;get block number
; input:nxtrec,blmode,fcb@(addinp),sxb,exm
; returns:none
; alters:all,blknum
getblk  ldx     sxb             ;set x according to blkscd
        lda     nxtrec          ;get next record
gblp    lsr     a               ;divide by 2 x times
        dex
        bne     gblp
        sta     blknum          ;save previous as temp
;use extent as offset but first use sxb to create param
        sec
        lda     #8
        sbc     sxb
        tax
;now get extent from fcb
        ldy     #12
        lda     (addinp),y
        and     exm             ;and with mask
        lsr     a               ;shift with lsb to c
gbxlp   rol     a               ;now go other way
        dex
        bne     gbxlp
        clc                     ;now add saved value
        adc     blknum          ;back
        bit     blmode          ;test mode
        bpl     *+3             ;skip if byte
        asl     a               ;else times two
        clc                     ;then add
        adc     #16             ;offset into fcb
        sta     fcbind          ;save for later
        tay                     ;set index
        lda     (addinp),y      ;get number
        sta     blknum          ;store
        iny
        lda     #0              ;clear
        bit     blmode          ;test mode
        bpl     *+4             ;skip if byte
        lda     (addinp),y      ;else get high
        sta     blknum+1        ;high byte
        rts                     ;and return
;calculate chkpnt as function of dirrec and chkmap
; input:dirrec,chkmap
; returns:y=0
; alters:y,p,chkpnt
clcckp  pha                     ;save a
        clc
        lda     dirrec          ;add record number
        adc     chkmap          ;to start
        sta     chkpnt
        lda     dirrec+1
        adc     chkmap+1
        sta     chkpnt+1
        ldy     #0
        pla                     ;get a back
        rts
;clear directory number to $ffff
; input:none
; returns:a=$ff,n=1,z=0
; alters:a,p,dirnum,dirmod
cldrnm  lda     #$ff            ;set to $ff
        sta     dirnum
        sta     dirnum+1
        sta     dirmod
        rts
;change allocation map
; input:subrec,directory record @ (bufadd)
; returns:none
; alters:all,allocation map
mapdir  clc                     ;add 16 to
        lda     subrec          ;to subrec to point
        adc     #16             ;to block number field
        tay                     ;make index
lpmpdr  sty     mpdrsy          ;save index
        phx                     ;save operation
        lda     (bufadd),y      ;get block number
        sta     mpdrtm          ;save in temp
        iny                     ;bump index for word
        jsr     gthibn          ;get high part of number
mpdrnw  ora     mpdrtm          ;see if zero
        beq     skpedr          ;skip if zero
        jsr     gthibn          ;get high again
        tay                     ;move to y
        lda     mpdrtm          ;get low again
        jsr     altalc          ;else alter map
skpedr  plx                     ;get operation back
        ldy     mpdrsy          ;get index back
        iny                     ;bump it
        tya                     ;if still
        and     #%00001111      ;in field
        bne     lpmpdr          ;then loop
        rts                     ;else quit
;test r/w status
;does warm boot if r/o
; input:curdrv,ronlst
; returns:none
; alters:a,x,p
tstron  jsr     chkron          ;test bit
        beq     exttro          ;exit if r/w
        jsr     errout          ;else send error
        lda     #<romsg         ;point to r/o
        ldy     #>romsg         ;message
        jsr     sndstr          ;send it
        jmp     xwboot          ;then abort
;set current drive to r/w
; input:curdrv,ronlst
; returns:ronlst
; alters:a,x,p,ronlst
setrw   ldx     curdrv          ;get drive
        lda     bitmap,x        ;and mask
        eor     #$ff            ;complement
        and     ronlst          ;and with status
        sta     ronlst          ;save
exttro  rts                     ;return
;read sector
rdesec  jsr     simram+39       ;do read
        bra     chkrwe          ;check for error
;update checksum and directory
updtck  ldx     #1              ;set for update
        jsr     chksop          ;do it
        lda     #1              ;say is directory op
        bne     secwrt          ;do it
;write sector
wrtsec  lda     wrtype          ;get write type
secwrt  jsr     simram+42       ;do write
chkrwe  cmp     #0              ;if not ok
        beq     exttro          ;done if zero
;read/write error
rwerrt  jsr     errout          ;send error message
        lda     #<bdsmsg        ;point to
        ldy     #>bdsmsg        ;bad sector message
        jsr     sndstr          ;and send
        jsr     getcon          ;get input
        cmp     #cr             ;if a cr
        beq     ignerr          ;then continue
        jmp     xwboot          ;else abort
ignerr  jmp     pcrlf           ;crlf and return
;error output routine
; input:curdrv
; returns:none
; alters:all
errout  lda     #<pemmsg        ;point to
        ldy     #>pemmsg        ;error message
        jsr     sndstr          ;send it
        lda     curdrv          ;get drive number
        clc                     ;add
        adc     #'A'            ;ascii a
        jmp     sndchr          ;and send it
;get high part of block number if word (zero if byte)
; input:y=index to high,blmode,directory@(bufadd)+subrec
; returns:a=high part of block number
; alters:a,p,mpdrsy iff word
gthibn  lda     #0              ;preset for byte
        bit     blmode          ;test mode
        bpl     gthiex          ;done if byte
        lda     (bufadd),y      ;get high
        sty     mpdrsy          ;alter y
gthiex  rts                     ;return
;get console input
; input:pndkey
; returns:a=character
; alters:all,pndkey
getcon  lda     pndkey          ;get pending
        stz     pndkey          ;clear pending
        bne     gthiex          ;exit if not null (borrow rts)
        jmp     simram+9        ;else get new
;check keyboard status
;handles <ctl-s> for freeze and <ctl-c> for boot
; input:pndkey
; returns:a=0 if no input or <>0 if input
; alters:all,pndkey
kbdsts  lda     pndkey          ;get pending
        bne     extkbd          ;if there quit
        jsr     simram+6        ;else test
        and     #$ff            ;if zero
        beq     extkbd          ;exit
        jsr     simram+9        ;else get input
        cmp     #ctls           ;if not freeze
        bne     newpnd          ;save input
        jsr     simram+9        ;else wait for more
        cmp     #ctlc           ;if not abort
        bne     nowarm          ;then jump
        jmp     xwboot          ;else do warm boot
nowarm  lda     #0              ;clear
        rts                     ;and return
newpnd  sta     pndkey          ;save
        lda     #$ff            ;set ready
extkbd  rts                     ;and return
;test character
; input:a=character
; returns:c=0 if control or c=1 if printing
; alters:p
tstchr  cmp     #cr             ;if cr
        beq     chtext          ;quit
        cmp     #lf             ;if linefeed
        beq     chtext          ;quit
        cmp     #ctli           ;if tab
        beq     chtext          ;quit
        cmp     #' '            ;see if control
chtext  rts                     ;and return
;send string ending in $
; input:ay=string address
; returns:none
; alters:all,index,sndlpe+1 and +2
sndstr  sta     msgptr          ;set pointer
        sty     msgptr+1
        ldy     #0
sndlpe  lda     (msgptr),y      ;get char
        cmp     #'$'            ;if terminator
        beq     sndext          ;then exit
        iny                     ;else bump
        sty     index           ;and save
        jsr     sndchr          ;send char
        ldy     index           ;get index
        bne     sndlpe          ;and loop
sndext  rts                     ;return
;send char to printer if enabled
; input:a=character,lstflg
; returns:a=character
; alters:x,y,p
lstout  bit     lstflg          ;test flag
        bpl     extlst          ;exit if off
        bit     outflg          ;test output flag
        bmi     extlst          ;done if set
        pha                     ;save char
        jsr     simram+15       ;send
        pla                     ;get char
extlst  rts                     ;and done
;output a character
; input:a=character,console definition block in sim
; returns:none
; alters:all,positn
output  jsr     tstchr          ;test it
        bcs     sndchr          ;if not control jump
        pha                     ;else save
        lda     sysdef+4        ;get invert
        jsr     nolist          ;send to console
        lda     #'^'            ;get arrow
        jsr     lstout          ;send to printer
        pla                     ;get character
        ora     #'A'-1          ;convert to ascii
        jsr     pchrot          ;send to all
        lda     sysdef+3        ;get normal
        bra     nolist          ;to console
sndchr  cmp     #ctli           ;if not tab
        bne     pchrot          ;send
tabspc  lda     #' '            ;else get space
        jsr     pchrot          ;send
        lda     positn          ;get count
        and     #7              ;if not mod 8
        bne     tabspc          ;loop
        rts                     ;else exit
pchrot  pha                     ;save char
        jsr     kbdsts          ;test input
        pla                     ;restore
        jsr     lstout          ;to printer if on
nolist  pha                     ;save again
        bit     outflg          ;test flag
        bmi     *+5             ;done if set
        jsr     simram+12       ;to console
        pla                     ;restore
        inc     positn          ;bump col
        cmp     #' '            ;if space or more
        bcs     extchr          ;is ok
        cmp     sysdef+2        ;also ok
        beq     extchr          ;if forward
        dec     positn          ;else drop back
        cmp     sysdef+0        ;see if bs
        bne     tryotr          ;branch if not
        dec     positn          ;else drop again
        bmi     zrocol          ;zero if <0
        rts                     ;else ok
tryotr  cmp     #cr             ;if a cr
        beq     zrocol          ;clear col
        cmp     sysdef+7        ;if a formfeed
        beq     zrocol          ;also clear
        cmp     sysdef+8        ;if not home
        bne     extchr          ;then done
zrocol  stz     positn          ;column
extchr  rts                     ;and exit
;go to left and space past prompt
; input:frscol,positn
; returns:none
; alters:positn
spcovr  lda     #cr             ;get cr
        jsr     pchrot          ;send to all
        lda     #lf             ;send lf
        jsr     lstout          ;only to printer
mreovr  lda     frscol          ;get first
        cmp     positn          ;see if there
        beq     extchr          ;done if is
        lda     sysdef+2        ;get forward
        jsr     nolist          ;send it
        bra     mreovr          ;and loop
;buffered read
; input:buffer@(addinp)
; returns:none
; alters:all,buffer@(addinp)
bufinp  lda     #0              ;clear
        ldy     #1              ;length
        sta     (addinp),y      ;position in buffer
        sty     bufpsn          ;set point to 1
        lda     positn          ;get current
        sta     frscol          ;and save
nxtinp  jsr     getcon          ;get input
        ldy     bufpsn          ;get index
        cmp     #cr             ;if not a cr
        bne     notcr           ;then jump
        jmp     endlin          ;else done
notcr   cmp     #delete         ;if not delete
        bne     ntdelt          ;then jump
        cpy     #1              ;else if start
        beq     nxtinp          ;then loop
        lda     (addinp),y      ;get last
        pha                     ;save char
        ldy     #1              ;point to count
        sec                     ;set carry
        lda     (addinp),y      ;get count
        sbc     #1              ;decrement
        sta     (addinp),y      ;then save
        pla                     ;restore char
        dec     bufpsn          ;backup pointer
        cmp     #' '            ;if space or more
        bcs     nrmbs           ;just backspace
        cmp     #ctli           ;see if tab
        bne     ctlbs           ;if not is control
        sec                     ;set flag
        ror     outflg
        lda     positn          ;get position and save
        sta     lstcol
        jsr     spcovr          ;else go back
        jsr     rptlne          ;and retype
        lda     positn          ;get new last position
        pha                     ;save on stack
        sec                     ;subtract to get delta
        lda     lstcol
        sbc     positn
        sta     lstcol          ;and save
        asl     outflg          ;clear flag
bstab   jsr     dobs            ;do one
        dec     lstcol          ;drop count
        bne     bstab           ;loop if more
        pla                     ;get position
        sta     positn          ;and set
        bra     nxtinp          ;then loop
ctlbs   lda     sysdef+3        ;get normal
        jsr     chkbs           ;bs if printing
        lda     sysdef+4        ;same for invert
        jsr     chkbs           ;then delete char itself
nrmbs   jsr     dobs            ;do a backspace
        bra     nxtinp          ;and loop
ntdelt  cmp     #ctlp           ;if not ctl-p
        bne     ntctlp          ;then jump
        lda     lstflg          ;else get printer flag
        eor     #$ff            ;complement
        sta     lstflg          ;save
        bra     nxtinp          ;and loop
ntctlp  cmp     #ctlx           ;if not ctl-x
        bne     ntctlx          ;then jump
        jsr     spcovr          ;restart
        lda     sysdef+1        ;get clear to eol
        jsr     nolist          ;send it
        jmp     bufinp          ;and start over
ntctlx  cmp     #ctlr           ;if not ctl-r
        bne     ntctlr          ;then jump
        jsr     spcovr          ;restart
        jsr     rptlne          ;retype line
        jmp     nxtinp          ;and start over
ntctlr  iny                     ;next position
        sta     (addinp),y      ;store char
        pha                     ;and save
        sty     bufpsn          ;index
        ldy     #1              ;point to count
        tya                     ;set a to 1
        clc                     ;then
        adc     (addinp),y      ;add count
        sta     (addinp),y      ;and save
        pla                     ;restore char
dontsv  jsr     output          ;send char
        ldy     bufpsn          ;get index
        lda     (addinp),y      ;get char
        cmp     #ctlc           ;if not ctl-c
        bne     ignrcc          ;ignore
        ldy     #1              ;get count
        lda     (addinp),y      ;from buffer
        cmp     #1              ;if not at start
        bne     ignrcc          ;ignore
        jmp     xwboot          ;else do warm boot
ignrcc  ldy     #1              ;get
        lda     (addinp),y      ;count
        dey                     ;point to max
        cmp     (addinp),y      ;if length
        bcs     lineen          ;at max jump
        jmp     nxtinp          ;else loop
lineen  lda     #cr             ;get a cr
endlin  jmp     pchrot          ;and send
;cr and lf
pcrlf   lda     #cr             ;then a
        jsr     pchrot          ;cr
        lda     #lf             ;and a
        jmp     pchrot          ;lf
;retype line
rptlne  lda     bufpsn          ;save point
        sta     numcnt          ;as count
        lda     #1              ;start position
        pha                     ;save
mrerpt  pla                     ;get position
        dec     numcnt          ;count down
        bne     *+3             ;continue if more
        rts                     ;else done
        tay                     ;else make index
        iny                     ;and bump
        phy                     ;save index on stack
        lda     (addinp),y      ;get char
        jsr     output          ;send
        bra     mrerpt          ;and loop
;check for printing and backspace if needed
chkbs   cmp     #' '            ;compare to space
        bcc     extdec          ;not printing so done
;do a backspace
dobs    lda     sysdef+0        ;get backspace
        pha                     ;save it
        jsr     nolist          ;send
        lda     #' '            ;get space
        jsr     nolist          ;send
        pla                     ;get backspace
        jmp     nolist          ;send it
;test for decimal digit
;if decimal then c=0 else c=1
tstdec  cmp     #'0'            ;if under 0
        bcc     notdec          ;then not decimal
        cmp     #'9'+1          ;if 9 or under is ok
        bcc     extdec
notdec  sec                     ;else not a match
extdec  rts
;test for hexadecimal digit
;if hex then c=0 else c=1
tsthex  jsr     tstdec          ;first try decimal
        bcc     extdec          ;ok if dec
        cmp     #'A'            ;if under A
        bcc     notdec          ;then not hex
        cmp     #'F'+1          ;set c in F compare
        rts
;bump load address by 128 and return in ay
adjdb   lda     dskbuf          ;get old
        ldy     dskbuf+1        ;address
        clc                     ;and bump
        adc     #128            ;by 128
        sta     dskbuf          ;save low
        bcc     *+6             ;then bump
        iny                     ;and save
        sty     dskbuf+1        ;high as needed
        rts
;move record from disk buffer to default buffer
mv128   lda     dskbuf          ;get address
        ldy     dskbuf+1
        sta     movptr          ;and set pointer
        sty     movptr+1
        ldy     #0              ;clear index
mvfrom  lda     (movptr),y      ;get byte
        sta     dflbuf,y        ;move it
        iny
        bpl     mvfrom          ;loop until done
        rts
;messages
romsg   byte    " - R/O$"
bdsmsg  byte    " - BAD SECTOR"
        byte    cr,lf,"<RET> TO IGNORE -- <OTHER> "
        byte    "TO ABORT$"
pemmsg  byte    cr,lf,"PEM ERROR ON $"
sltmsg  byte    " - INVALID DRIVE$"
;dummy fcb
empty   byte    $E5
;bit mask table
bitmsk  byte    128,64,32,16,8,4,2,1
;bit map table
bitmap  byte    1,2,4,8,16,32,64,128
;extent mask table (also uses 3 bytes in sabtbl
exmtbl  byte    0,1,3
;sab table
sabtbl  byte    7,15,31,63,127
;-------------------------------------
;DOS/65 System Interface Module (SIM)
;-------------------------------------
        org     $/256*256+256

        include sim123c02.asm
;
        ends

        data
        byte    $65
        ends

        end
