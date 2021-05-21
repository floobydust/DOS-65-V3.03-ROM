                globals on
                case    off
;DOS/65 system interface module (SIM)
;Version 1.23
;
;This is the WDC tools version derived from SIM415X.ASM.
;This version is designed to work with the:
;C02 Pocket SBC with RTC/CF-Card adapter.
;
;Disk configuration:
; a CF 8MB (CF.0)
; b CF 8MB (CF.1)
; c CF 8MB (CF.2)
; d CF 8MB (CF.3)
; e CF 8MB (CF.4)
; f CF 8MB (CF.5)
; g CF 8MB (CF.6)
;
;Revision history:
;       29 July 2017 (1.20W)
;               baseline release
;       30 August 2017 (1.21W
;               updated version to match MON change
;
; Updated to 1.23 on 5th April 2021 - KM
;  Three additional drives added, some 65C02 opcodes, etc.
;  Streamline Code, Minor formatting changes.
;
; Note: This SIM version does not require a Monitor module!
; All required code is part of this SIM version and interfaces
; directly with calls to C02BIOS and C02Monitor.
; This saves hundreds of bytes of ROM space and eliminates
; additional JMPs and JSRs that the previous SIM version made.
;
;**************************************************************************************************
        INCLUDE         C02Constants3.asm       ;Constants/Equates - C02 BIOS/Monitor/Hardware
;**************************************************************************************************
;
;**************************************************************************************************
;Fixed parameters
CLREOL                  .EQU     1              ;clear to eol (ctl-a)
CLREOS                  .EQU     2              ;clear to eos (ctl-b)
BS                      .EQU     8              ;backspace (ctl-h)
ESC                     .EQU     $1B            ;escape char
;
;**************************************************************************************************
;
;pem constants on entry to write
wrall           .EQU    0               ;write to allocated
wrdir           .EQU    1               ;write to directory
wrual           .EQU    2               ;write to unallocated
;main program
;start of sim
sim
;opening id message
sim_opnmsg      .DB     CR,LF,"SIM V1.23 for C02 Pocket SBC"
                .DB     CR,LF,"32K ROM DOS/65 V3.03",0
;
IO_ERR_MSG      .DB     CR,LF,"Disk I/O Error!",0
;
;Cold entry from DOS/65 Boot code below
sim_boot        lda     #<sim_opnmsg    ;point to message
                ldy     #>sim_opnmsg
                jsr     mon_txtout      ;send it
;Initialize iostat
                stz     iostat          ;clear I/O status
;set up jumps into dos/65 in page one
; NOTE: changed to absolute indexed using Y register.
;       WDC Tools has a bug using X register when the
;       operand is $0100-1 (should be $00FF, but becomes $FF)
sim_setup
;first clear key de-blocking variables
                stz     sim_hstact      ;set host buffer inactive
                stz     sim_unacnt      ;clear unalloc count
;
                ldy     #6              ;set index to 6
simset_lp       lda     sim_inttbl-1,y  ;get SIM table data
                sta     $0100-1,y       ;store into page $01 PEM area
                dey                     ;decrement index
                bne     simset_lp       ;loop until done
                lda     #<dflbuf        ;get low buffer
                ldy     #>dflbuf        ;and high buffer
                jsr     sim_setdma      ;and set DMA
                jmp     ccmram          ;then go to CCM
;initialization table
sim_inttbl      .DB     $4C
                .DW     sim_wboote
                .DB     $4C
                .DW     pemram
;warm boot-read DOS/65 back except SIM and then
;jump to CCM. IOSTAT and hence the default drive
;and user are not altered by warm boot.
; note: WARM BOOT does not read from any drive
; as it is ROM based, so it's only a refresh of
; ROM data to RAM and set the default drive.
sim_wboot       ldx     #$FF            ;set stack
                txs                     ;pointer
                jsr     mon_warm        ;reresh RAM data from ROM
                lda     iostat          ;set default drive
                jsr     sim_seldsk
                bra     sim_setup       ;go set up

;select disk
sim_seldsk      and     #%00000111      ;eight drives only
                sta     mon_nxtdrv      ;Save active Drive number
                sta     sim_sekdsk      ;save for later
                asl     a               ;multiply by two
                tax                     ;make an index
                lda     sim_dcbtbl,x    ;get address
                ldy     sim_dcbtbl+1,x
                rts
;table of dcb addresses.
; - first seven drives are in use, all eight require entries! - KM
; added a "_" in dcb definitions, as dcbh causes assembly error - KM
sim_dcbtbl      .DW     dcb_a
                .DW     dcb_b
                .DW     dcb_c
                .DW     dcb_d
                .DW     dcb_e
                .DW     dcb_f
                .DW     dcb_g
                .DW     0               ;no drive h

;see if de-blocking required for sekdsk
;returns number of dos/65 records per physical
;sector in a and
;returns z=1 if no de-blocking required else z=0
sim_tstdbl      ldx     sim_sekdsk      ;get desired disk
;see if de-blocking required for disk x
sim_tstdbx      lda     sim_spttbl,x    ;get dos/65 records/host sector
                cmp     #1              ;test for no deblock
                rts                     ;return
;table containing number of DOS/65 records
;per host physical sector.  if entry is 1
;then de-blocking is skipped.
;note that these two tables contain eight
;entries even though only the first seven are used.
sim_spttbl      .DB     4,4,4,4,4,4,4,4
;table of records/block
sim_rbltbl      .DB     16,16,16,16,16,16,16,16
;home the selected disk
sim_home        lda     sim_hstwrt      ;check for pending write
                bne     sim_xlate       ;there is so skip (borrowed RTS)
                stz     sim_hstact      ;else, clear host active flag
sim_xlate       rts                     ;return
;translate record in ay for nxtdrv
; - translation is only done for 8 in, sssd
; - drives - no longer in system.
; Note: use existing RTS in code above, save a byte.
;sim_xlate       rts                     ;do nothing
;
;read the selected dos/65 record.
sim_read        stz     sim_unacnt      ;clear unallocated count
                ldx     #1              ;x <-- 1
                stx     sim_readop      ;say is read operation
                stx     sim_rsflag      ;must read data
                inx                     ;x <-- wrual
                stx     sim_wrtype      ;treat as unalloc
                jmp     sim_rwoper      ;to perform the read
;write the selected dos/65 record.
sim_write       sta     sim_wrtype      ;save param from pem
                jsr     sim_tstdbl      ;see if one rec/sec
                bne     ?B2             ;if not use type passed
                lda     #wrdir          ;if is say directory
                sta     sim_wrtype      ;to force write
?B2             stz     sim_readop      ;say is not a read operation
                lda     sim_wrtype      ;get write type back
                cmp     #wrual          ;write unallocated?
                bne     ?B3             ;check for unalloc
;write to unallocated, set parameters
                ldx     sim_sekdsk      ;get next disk number
                lda     sim_rbltbl,x    ;get records/block
                sta     sim_unacnt
                stx     sim_unadsk      ;unadsk <-- sekdsk
                lda     sim_sektrk
                ldy     sim_sektrk+1
                sta     sim_unatrk      ;unatrk <-- sectrk
                sty     sim_unatrk+1
                lda     sim_seksec
                ldy     sim_seksec+1
                sta     sim_unasec      ;unasec <-- seksec
                sty     sim_unasec+1
;check for write to unallocated record
?B3             lda     sim_unacnt      ;any unalloc remain?
                beq     sim_alloc       ;skip if not
;more unallocated records remain
                dec     sim_unacnt      ;unacnt <-- unacnt-1
                lda     sim_sekdsk
                cmp     sim_unadsk      ;sekdsk = unadsk?
                bne     sim_alloc       ;skip if not
;disks are the same
                lda     sim_unatrk      ;sektrk = unatrk?
                cmp     sim_sektrk
                bne     sim_alloc       ;no so skip
                lda     sim_unatrk+1
                cmp     sim_sektrk+1
                bne     sim_alloc       ;skip if not
;tracks are the same
                lda     sim_unasec      ;seksec = unasec?
                cmp     sim_seksec
                bne     sim_alloc       ;no so skip
                lda     sim_unasec+1
                cmp     sim_seksec+1
                bne     sim_alloc       ;skip if not
;match, move to next sector for future ref
                inc     sim_unasec      ;unasec = unasec+1
                bne     ?B4
                inc     sim_unasec+1
;calculate dos/65 records/track
?B4             lda     sim_sekdsk      ;get disk number
                asl     a               ;mult by two
                tax                     ;make an index
                lda     sim_dcbtbl,x    ;get dcb start
                ldy     sim_dcbtbl+1,x
                sta     sim_dcbpnt      ;set low operand
                sty     sim_dcbpnt+1    ;then high operand
;point has address now get spt at byte 2,3
                ldy     #2              ;start at byte 2
                ldx     #0              ;start save in low
?B5             lda     (sim_dcbpnt),y  ;get value
                sta     sim_d65spt,x    ;and save
                iny
                inx
                cpx     #2              ;see if done
                bne     ?B5             ;loop if not
;check for end of track
                lda     sim_unasec      ;end of track?
                cmp     sim_d65spt      ;count dos/65 sectors
                lda     sim_unasec+1
                sbc     sim_d65spt+1
                bcc     ?B6             ;skip if no overflow
;overflow to next track
                stz     sim_unasec      ;unasec <-- 0
                stz     sim_unasec+1
                inc     sim_unatrk      ;unatrk <-- unatrk+1
                bne     ?B6
                inc     sim_unatrk+1
;match found, mark as unnecessary read
?B6             stz     sim_rsflag      ;rsflag <-- 0
                bra     sim_rwoper      ;to perform the write
;not an unallocated record, requires pre-read
sim_alloc       stz     sim_unacnt      ;unacnt <-- 0
;say preread required
                ldx     #1              ;x <-- 1
                stx     sim_rsflag      ;rsflag <-- 1
;check for single record/sector - and if so
;then say preread not required.
                jsr     sim_tstdbl      ;test
                bne     sim_rwoper      ;more than one
                stz     sim_rsflag      ;say no preread
;common code for read and write follows
;enter here to perform the read/write
sim_rwoper      stz     sim_erflag      ;set no errors (yet)
                lda     sim_seksec      ;compute host sector
                ldy     sim_seksec+1
                sta     sim_sekhst
                sty     sim_sekhst+1
                jsr     sim_tstdbl      ;get records/sector
                lsr     a               ;divide by two
                tax                     ;make a counter
                beq     ?B2             ;done if zero
?L2             lsr     sim_sekhst+1    ;do high
                ror     sim_sekhst      ;then low
                dex
                bne     ?L2             ;loop if more
;active host sector?
?B2             lda     sim_hstact      ;host active flag
                pha                     ;save flag
                inx                     ;x <-- 1
                stx     sim_hstact
                pla                     ;get flag back
                beq     sim_filhst      ;fill host if not active
;host buffer active, same as seek buffer?
                lda     sim_sekdsk
                cmp     sim_hstdsk      ;same disk?
                bne     sim_nmatch
;same disk, same track?
                lda     sim_hsttrk      ;sektrk = hsttrk?
                cmp     sim_sektrk
                bne     sim_nmatch      ;no
                lda     sim_hsttrk+1
                cmp     sim_sektrk+1
                bne     sim_nmatch
;same disk, same track, same sector?
                lda     sim_sekhst      ;sekhst = hstsec?
                cmp     sim_hstsec
                bne     sim_nmatch      ;no
                lda     sim_sekhst+1
                cmp     sim_hstsec+1
                beq     sim_match       ;skip if match
;proper disk, but not correct sector
sim_nmatch      lda     sim_hstwrt      ;host written?
                beq     sim_filhst      ;skip if was
                jsr     sim_writeh      ;else clear host buff
;may have to fill the host buffer
;so set host parameters
sim_filhst      lda     sim_sekdsk
                sta     sim_hstdsk
                lda     sim_sektrk
                ldy     sim_sektrk+1
                sta     sim_hsttrk
                sty     sim_hsttrk+1
                lda     sim_sekhst
                ldy     sim_sekhst+1
                sta     sim_hstsec
                sty     sim_hstsec+1
                lda     sim_rsflag      ;need to read?
                beq     sim_noread      ;no
;read desired physical sector from host
                jsr     sim_hcom        ;set parameters
                jsr     mon_rdesec      ;to rom
                sta     sim_erflag      ;save result
sim_noread      stz     sim_hstwrt      ;clear, no pending write
;copy data to or from buffer
sim_match       stz     sim_movepnt     ;clear pointer, later we'll set read
                stz     sim_movepnt+1
                jsr     sim_tstdbl      ;get records/sector
                beq     sim_endmve      ;done if no deblocking
                dec     a               ;decrement by one
                and     sim_seksec      ;mask sector number
                tax                     ;make a counter
                beq     sim_nooff       ;done if zero
?L2             clc
                lda     sim_movepnt
                adc     #128
                sta     sim_movepnt
                lda     sim_movepnt+1
                adc     #0
                sta     sim_movepnt+1
                dex
                bne     ?L2             ;loop if more
;pointer has relative host buffer address
sim_nooff       clc                     ;add hstbuf
                lda     #<hstbuf
                adc     sim_movepnt
                sta     sim_movepnt
                lda     #>hstbuf
                adc     sim_movepnt+1
                sta     sim_movepnt+1
;at this point pointer contains the address of the
;record of interest in the hstbuf buffer.
                ldy     #127            ;length of move - 1
                ldx     sim_readop      ;which way?
                bne     sim_rmove       ;skip if read
;write operation so move from dmaadr to mvepnt
                inx                     ;x <-- 1
                stx     sim_hstwrt      ;hstwrt <-- 1
?L2             lda     (sim_dmaadr),y
                sta     (sim_movepnt),y
                dey
                bpl     ?L2             ;loop if more
                bmi     sim_endmve      ;else done
;read operation so move from mvepnt to dmaadr
sim_rmove       lda     (sim_movepnt),y
                sta     (sim_dmaadr),y
                dey
                bpl     sim_rmove       ;loop if more
;data has been moved to/from host buffer
sim_endmve      lda     sim_wrtype      ;write type
                cmp     #wrdir          ;to directory?
                bne     ?B2             ;done if not
;clear host buffer for directory write
                lda     sim_erflag      ;get error flag
                bne     ?B2             ;done if errors
                sta     sim_hstwrt      ;say buffer written
                jsr     sim_writeh
?B2             lda     sim_erflag
                rts
;writeh performs the physical write to
;the host disk.
sim_writeh      jsr     sim_hcom        ;set-up params
                jsr     mon_wrtsec      ;to rom
                sta     sim_erflag      ;save result
                rts
;set parameters for host read/write
sim_hcom        lda     sim_hstdsk      ;set disk number
                sta     mon_nxtdrv      ;Save active Drive number
                lda     sim_hsttrk      ;then track
;                ldy     sim_hsttrk+1   ;not used
                sta     mon_nxttrk
                lda     sim_hstsec      ;then sector
;                ldy     sim_hstsec+1   ;not used
                sta     mon_nxtsec
                ldx     sim_hstdsk      ;get host disk
                jsr     sim_tstdbx      ;see if de-blocking
                beq     ?B2             ;branch if none
                lda     #<hstbuf        ;finally address
                ldy     #>hstbuf
                sta     lba_addr_low    ;Save low byte Buffer address
                sty     lba_addr_high   ;Save low byte Buffer address
                rts                     ;Return to Caller
?B2             lda     sim_dmaadr      ;send normal address
                ldy     sim_dmaadr+1    ;for no de-blocking
                sta     lba_addr_low    ;Save low byte Buffer address
                sty     lba_addr_high   ;Save low byte Buffer address
                rts                     ;Return to Caller
;set sector number
sim_selsec      sta     sim_seksec      ;save low and high
                sty     sim_seksec+1
                sta     mon_nxtsec
                rts
;set buffer address
sim_setdma      sta     sim_dmaadr      ;store low
                sty     sim_dmaadr+1    ;and high
                sta     lba_addr_low    ;Save low byte Buffer address
                sty     lba_addr_high   ;Save low byte Buffer address
                rts                     ;Return to Caller
;set track
sim_seltrk      sta     sim_sektrk      ;save number
                sty     sim_sektrk+1
                sta     mon_nxttrk
                rts
;
;**************************************************************************************************
;
;Console Input and Output Routines
; There are three routines for Console I/O
; 1- CONSTS - Console Status: tests to see if there is a character available
; 2- CONRDE - Console Read: waits for a character to be available, then returns with it
; 3- CONWRT - Console Write: sends a character to the console
;
mon_consts
                lda     icnt            ;Load Input Buffer count
                beq     conste          ;Branch if Buffer empty
                dec     a               ;Else, Decrement A (LDA #$FF)
conste          rts                     ;Return to Caller
;
mon_conrde
                jsr     b_chrin         ;Call BIOS for character in (waits)
                and     #$7F            ;Strip off high bit (ASCII only)
                cmp     #bs             ;Check for Backspace character
                bne     conrdx          ;If not, branch
                lda     #delete         ;Else, replace with Delete code
conrdx          rts                     ;Return to Caller
;
mon_conwrt
                pha                     ;Save Character to Stack
                and     #$7F            ;Strip off high bit (ASCII only)
                cmp     #delete         ;Check for Delete code
                bne     notdlt          ;If not, branch
                lda     #' '            ;Else, load ASCII space
notdlt          cmp     #clreol         ;Check for EOL code
                bne     ntceol          ;If not, branch
                lda     #esc            ;Else, load ASCII escape
                jsr     b_chrout        ;Call BIOS for character send
                lda     #'T'            ;Load upper case "T"
                bra     ntceos          ;Branch to send/exit
ntceol          cmp     #clreos         ;Check for CLR code
                bne     ntceos          ;If not, branch
                lda     #esc            ;Load ASCII escape
                jsr     b_chrout        ;Call BIOS for character send
                lda     #'Y'            ;Load upper case "Y"
ntceos          jsr     b_chrout        ;Call BIOS for character send
endvid          pla                     ;Get original Character from Stack
                rts                     ;return to Caller
;
;Send null terminated string to console. note that routine will
; also be terminated if high byte of pointer wraps from $FF to $00.
; Input: A and Y are low and high bytes of string start
; Output: carry clear
mon_txtout      sta     promptl         ;Save text string pointer
                sty     prompth         ;
                ldy     #0              ;Zero Index
txtout_lp       lda     (promptl),y     ;Get character
                beq     txtout_end      ;Quit if zero
                jsr     mon_conwrt      ;Send character
                iny                     ;Increment index
                bne     txtout_lp       ;Loop back if no rollover
                inc     prompth         ;Else, increment high byte of pointer
                bne     txtout_lp       ;Loop back if no rollover
txtout_end      clc                     ;Set Carry for no error
                rts                     ;Return to Caller
;
;**************************************************************************************************
;
;Disk Routines for LBA Read and Write
; There are two routines here
; 1- RDESEC: Read an LBA into the Buffer
; 2- WRTSEC: Write an LBA from the Buffer
; These routines call the C02 BIOS for actual LBA read and write along with the routines
; to set the parameters for LBA requested and buffer address. These are 512-byte block accesses.
;
mon_wrtsec
                jsr     wrlba           ;Calculate CHS to LBA
                jsr     b_ide_write_lba ;Call BIOS to Write LBA
                bra     rd_wr_end       ;Branch to finish up
mon_rdesec
                jsr     wrlba           ;Calculate CHS to LBA
                jsr     b_ide_read_lba  ;Call BIOS to Read LBA
rd_wr_end
                lda     ide_status_ram  ;Get Status from BIOS call
                lsr     a               ;Shift error bit to carry
                bcs     ide_rw_err      ;Branch if error
                lda     #$00            ;Else, clear A reg
                rts                     ;Return to caller
ide_rw_err
                lda     #<io_err_msg    ;Point to error message
                ldy     #>io_err_msg
                jsr     m_promptr       ;Send it
                bra     dos_entry       ;Restart DOS
;
;Calculate the LBA number from the Track and Sector parameters
; The Sector count can be from 0 to 255 (256 total)
; The Track count can be from 0 to 63 (64 total)
;
;24-bit addressing is supported by the C02BIOS V3.03
; The upper 4-bits (28-bit) are always zeroed by the BIOS routines,
; hence BIOS is limited to 8GB size as a result of 24-bit addressing.
;
;Once the Track and Sector values are moved to the LBA parameters,
; an offset must be added which is based on the Drive number (0-7).
; Partition sizes are limited to 8MB
; Number of drives is limited to 8 (A - H)
; Maximum available Data is limited to 64MB
;
;The Offset table is 4 bytes per entry and adds an LBA count to
; shift the absolute LBA numbers to the appropriate drive number
; being acessed (16384 blocks per).
;
; At entry;
; NXTSEC contains 0 to 255
;                       00000000|ssssssss
;
; NXTTRK contains 0 to 63
;                       00000000|0ttttttt
;
;First, copy NXTSEC to LBA0 with end result being:
;Second, copy NXTTRK to LBA1 and clear LBA2
;
; so LBA2|LBA1|LBA0 look like:
;                       00000000|0ttttttt|ssssssss
;
wrlba           lda     mon_nxtsec      ;Get requested Sector number
                sta     ide_lba0        ;Save to LBA lowest order byte
                lda     mon_nxttrk      ;Get requested Track number
                sta     ide_lba1        ;Save to LBA middle order byte
                stz     ide_lba2        ;Zero out the Upper order byte
;
;All LBA data starts as LBA 0 for each drive number.
; So the drive number is used as an index to the Offset table.
; This is then added to the 24-bit LBA address and stored to
; the BIOS variables for the requested LBA for Read or Write.
; Note: "LBA3" is not needed, as the BIOS handles 24-bit input
; and zeros the upper 4-bits of the (28-bit) address!
;
                lda     mon_nxtdrv      ;Get drive number
                asl     a               ;Multiply by two
                asl     a               ;Multiply by two (now = 4)
                tax                     ;Xfer offset to X reg
;
                clc                     ;Clear Carry for Add
                lda     ide_lba0        ;Get Low order LBA
                adc     offset,x        ;Add in low order offset
                sta     lba_low_byte    ;Save to BIOS variable
                inx                     ;Increment index to next offset byte
                lda     ide_lba1        ;Get Middle order LBA
                adc     offset,x        ;Add in high order offset
                sta     lba_high_byte   ;Save to BIOS variable
                inx                     ;Increment index to next offset byte
                lda     ide_lba2        ;Get the High order LBA
                adc     offset,x        ;Add in extended order offset
                sta     lba_ext_byte    ;Save to BIOS variable
                rts                     ;Return to Caller
;
;At this point LBA address is calculated and stored.
; The C02BIOS 3.03 variables are already loaded per the
; routine above. Using the LBA Read or Write function
; will transfer the LBA parameters, so we're done here.
;
;Table of LBA offsets for all drives A thru H
offset
                .LONG   0               ;Drive A CP/M default
                .LONG   16384           ;Drive B
                .LONG   32768           ;Drive C
                .LONG   49152           ;Drive D
                .LONG   65536           ;Drive E
                .LONG   81920           ;Drive F
                .LONG   98304           ;Drive G
                .LONG   114688          ;Drive H
;
;**************************************************************************************************
;DOS/65 ENTRY
; Note: The address here is called from C02Monitor via a CTRL-B command. By default, the address
; is located at $D680 in ROM. If any changes are made to this SIM module, ensure that the code
; is either at the same address or change the address that the monitor calls!
;
dos_entry       ldx     #$FF            ;Set
                txs                     ;Stack pointer
;Initialize all of ram by transferring block from
; ROM location to start of RAM. All monitor and
; DOS/65 non-page 0 RAM is initialized.
                lda     #$00            ;Get length low byte
                ldy     #$02            ;Get length high byte
;
                jsr     memory_move     ;Move Image from ROM to RAM
                jsr     clearmaps       ;Clear out RAM for Disk maps
                jsr     clearbuf        ;Clear out host buffer
                jsr     b_ide_reset     ;Reset IDE Controller
;
;DOS/65 bootstrap from ROM by going to SIM to start
; the process. Code and data that the LINKER placed in ROM at
; ROM address has already been transfered via above.
mon_boot        jmp     sim_boot        ;Jump to SIM start
;
;Warm boot dos/65 CCM & PEM from ROM. this is called from
; SIM and returns where SIM executes refreshed system.
mon_warm        lda     #$80            ;Get length low byte
                ldy     #$01            ;Get length high byte
;
;Memory move routine
; Memory move is used for both cold boot and warm boot.
; the ROM image for cold/warm boot differs in the amount of
; ROM data to be moved. Cold boot requires 512 bytes where
; Warm boot required 384 bytes.
memory_move
                sta     lenl            ;Save length low byte
                sty     lenh            ;Save length high byte
;
                lda     #<romorg        ;Get pointer to ROM start
                ldy     #>romorg        ;
                sta     srcl            ;Store to Page 0 pointer
                sty     srch            ;
                lda     #<ccmram        ;point to destination
                ldy     #>ccmram        ;
                sta     tgtl            ;Store to Page 0 pointer
                sty     tgth            ;
                jmp     m_move_ram      ;Use Monitor routine to move memory
;
;Clearmaps routine
; Only on a coldboot... the disk buffers need to be cleared.
; this saves 3.5KB of empty ROM space that is copied to RAM
; during a cold start. The variables used for start and end
; of RAM are: bufmap and bufmapend
clearmaps
                lda     #<bufmap        ;get start of buffer space
                ldy     #>bufmap
                sta     tgtl            ;save to page zero pointer
                sty     tgth
;
                sec                     ;set carry for subtraction
                lda     #<bufmapend     ;get end of buffer space lo byte
                sbc     tgtl            ;subtract start lo byte
                sta     lenl            ;save it to page zero pointer
                lda     #>bufmapend     ;get end of buffer space hi byte
                sbc     tgth            ;subtract start hi byte
                sta     lenh            ;save it to page zero pointer
fill_mem2
                stz     temp2           ;Zero fill byte value
;
;Memory fill routine: fills a block of memory with any desired fill byte
; based on target and length pointers. The fill byte is stored in TEMP2.
fill_mem        jmp     m_fill_ram      ;Use Monitor routine to fill memory
;
;The Host Buffer has been moved to low RAM. As a safety, this buffer
; is also cleared during a cold boot. The location is the default LBA
; buffer for the C02BIOS and will have Identity Data loaded there
; from booting the C02 Pocket SBC.
clearbuf
                lda     #<hstbuf        ;get the location of the
                ldy     #>hstbuf        ;host buffer
                sta     tgtl            ;save to page zero pointer
                sty     tgth            ;lo/hi bytes
;
                stz     lenl            ;save it to page zero pointer
                ldy     #$02            ;to 512 bytes
                sty     lenh            ;lo/hi bytes
                bra     fill_mem2       ;Go clear it
;
;**************************************************************************************************
;disk control blocks
; Updated to support seven drives by default - KM
;drive a (CF 8MB)
dcb_a           .DW     4095            ;max block number
                .DW     1024            ;records per track
                .DW     0               ;number system tracks
                .DB     1               ;block size = 2048
                .DW     1023            ;max directory
                .DW     almpa           ;address of allocation map
                .DB     128             ;do not do checksums
                .DW     0               ;phony address
;drive b (CF 8MB)
dcb_b           .DW     4095            ;max block number
                .DW     1024            ;records per track
                .DW     0               ;number system tracks
                .DB     1               ;block size = 2048
                .DW     1023            ;max directory
                .DW     almpb           ;address of allocation map
                .DB     128             ;do not do checksums
                .DW     0               ;phony address
;drive c (CF 8MB)
dcb_c           .DW     4095            ;max block number
                .DW     1024            ;records per track
                .DW     0               ;number system tracks
                .DB     1               ;block size = 2048
                .DW     1023            ;max directory
                .DW     almpc           ;address of allocation map
                .DB     128             ;do not do checksums
                .DW     0               ;phony address
;drive d (CF 8MB)
dcb_d           .DW     4095            ;max block number
                .DW     1024            ;records per track
                .DW     0               ;number system tracks
                .DB     1               ;block size = 2048
                .DW     1023            ;max directory
                .DW     almpd           ;address of allocation map
                .DB     128             ;do not do checksums
                .DW     0               ;phony address
;drive e (CF 8MB)
dcb_e           .DW     4095            ;max block number
                .DW     1024            ;records per track
                .DW     0               ;number system tracks
                .DB     1               ;block size = 2048
                .DW     1023            ;max directory
                .DW     almpe           ;address of allocation map
                .DB     128             ;do not do checksums
                .DW     0               ;phony address
;drive f (CF 8MB)
dcb_f           .DW     4095            ;max block number
                .DW     1024            ;records per track
                .DW     0               ;number system tracks
                .DB     1               ;block size = 2048
                .DW     1023            ;max directory
                .DW     almpf           ;address of allocation map
                .DB     128             ;do not do checksums
                .DW     0               ;phony address
;drive g (CF 8MB)
dcb_g           .DW     4095            ;max block number
                .DW     1024            ;records per track
                .DW     0               ;number system tracks
                .DB     1               ;block size = 2048
                .DW     1023            ;max directory
                .DW     almpg           ;address of allocation map
                .DB     128             ;do not do checksums
                .DW     0               ;phony address
;drive h (CF 8MB)
;dcb_h           .DW     4095            ;max block number
;                .DW     1024            ;records per track
;                .DW     0               ;number system tracks
;                .DB     1               ;block size = 2048
;                .DW     1023            ;max directory
;                .DW     almph           ;address of allocation map
;                .DB     128             ;do not do checksums
;                .DW     0               ;phony address

                end
