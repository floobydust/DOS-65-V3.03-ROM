	pw	132
	pl	66
	case	off
	chip	W65C02S
;XSBC123
;When code is configured it is recommended that
;a copy of the executable be named XMODEM.COM
;for consistency with example and help.
;Special version of xmodem for direct communication
;with computer at 115,200 bps using SCC2691 UART interface
;Modified for C02 Pocket SBC
; no need to initialize the hardware.
;Version 1.00 By David Robinson CIS 71505,1172
;Based on MODEM.ASM by Ward Christensen
; Minor modifications by Kevin Maier
;
;last revision:	8 January 1984 by R. Leary (1.01)
;			eliminated msize and pages dependence
;			added const result check and #$ff
;			corrected several errors
;			made easily adaptable
;		13 March 1984 by R. Leary (1.02)
;			added relative user set
;		24 November 1984 by R. Leary (1.03)
;			changed io page
;			clear page zero data area
;		24 May 1986 by R. Leary (1.04)
;			corrected problems in original
;		25 December 1988 by R. Leary (1.05)
;			converted to user 3
;			corrected error near csabor
;			added printer spooling
;		9 March 2008 by R. Leary (1.06)
;			corrected spelling
;			reformatted for TASM & ASM210 & up
;		24 April 2014 by R. Leary (1.07)
;			changed to User 1
;			deleted old printer port info
;			set print to do nothing
;			corrected many spelling errors
;		27 April 2014 by R. Leary (1.08)
;			added lower to upper case routine
;			added call to SIM for printer output
;			made keyboard interaction consistent
;				RETURN (ENTER) --> continue
;				CTRL-C --> abort transfer
;				CTRL-E --> quit a boot
;				R --> retry
;				Y --> yes
;		3 November 2014 by R. Leary (1.10)
;			converted IO to SERIAL IO Port A
;			converted to WDC syntax
;			did some 65C02 opcode conversion
;		6 December 2014 by R.Leary (1.20)
;			corrected one second timing for 2.5 MHz CPU clock
;			started effort to improve speed
;			incorporated V1.11 changes
;		5 March 2016 (1.21) Rich Leary
;			restored check for nulls in RCVSQ
;			corrected timing loop near nochar
;			eliminated view and see sub-options
;			changed wait to bufind in places
;		26 June 2017 (1.22)
;			pasted in sxbbind and stdio
;			changed port calls to WDC
;			changed one second timing
;			changed pzstrt to 5
;			enabled "TRANSFER COMPLETE" IN Q MODE
;		28 July 2017 (1.22S)
;			converted to SBC2
;		29 jULY 2017 (1.23s)
;			ELIMINATED GARBAGE getc CALLS
;               15 March 2021
;                       Modified for C02 Pocket SBC
;user defined parameters - mostly port definitions
;dos/65 parameters
pzstrt	equ	$30		;first usable page zero location
boot	equ	$100		;warm boot jmp
pem	equ	$103		;pem jmp
fcb	equ	$107		;fcb address
fcb2	equ	fcb+16		;fcb #2
fcbsno	equ	fcb+32		;fcb sector number
fcbext	equ	fcb+12		;fcb extent
buffer	equ	$128		;Default buffer address
tea	equ	$800		;execution org
;
;Page zero equates
;
	page0
	org	pzstrt
STROAD	ds	2		;pointer in ilprt
WAIT	ds	1
bufind	ds	1		;buffer index
ERRCNT	ds	1
SECINB	ds	1
RCVSNO	ds	1
EOFLR	ds	1
CSUM	ds	1
EOFLG	ds	1
inner	ds	1		;inner loop timing counter
outer	ds	1		;outer loop timing counter
seconds	ds	1		;time out in seconds
tmpsec	ds	1		;temporary hold for received record number
from	ds	2		;move from pointer
to	ds	2		;move to pointer
tmpchr	ds	1		;temp for received character
seccnt	ds	1		;sector counter
sndcnt	ds	1		;byte counter
tmpcsm	ds	1		;temp checksum
lastzp
	ends
;
;Define some other things (normally not changed)
;
ERRLIM	equ	10		;max # of errors
EXITCH	equ	05		;Exit from T or C
DISCHR	equ	04		;Disconnects modem
;
;Define PEM equates
PRINT	equ	09		;Print till $ in line
OPEN	equ	15		;$FF = Not Found
CLOSE	equ	16		; "	"
SRCHF	equ	17	 	; "	"  (Search first)
SCRHN	equ	18		; "	"  (Search next )
ERASE	equ	19		;No return code
READ	equ	20		;0 = ok, 1 = EOF
WRITE	equ	21		;"	"	$FF=No dir spc
MAKE	equ	22		;$FF = Bad
REN	equ	23		;"	"
STDMA	equ	26		;Set buffer address
;Define ASCII characters used
SOH	equ	01		;Start of header
CTRLC	equ	03		;Control-C
EOT	equ	04		;End of transmission
CTRLE	equ	05		;control-e
ACK	equ	06		;Acknowledge
BS	equ	08		;backspace
TAB	equ	09		;Tab
LF	equ	$0A		;Linefeed
CR	equ	$0D		;Carriage return
NAK	equ	$15		;Neg acknowledge
CAN	equ	$18		;Cancel
space	equ	$20		;blank
;
;Main Program
;
		code
		org	tea
		jmp	start		;jump to main routine
;direct jumps to sim routines
const		jmp	6		;console status
conin		jmp	9		;read console input
conot		jmp	12		;write to console
prnot		jmp	15		;write to printer
;set direct sim jump to correct page
setsim		lda	boot+2		;get upper address
		sta	const+2		;then set
		sta	conin+2
		sta	conot+2
		sta	prnot+2

                lda     boot+1          ;get lower address
                clc                     ;clear carry for add
                adc     #$03            ;add 3 for next jmp
                sta     const+1         ;then set
                adc     #$03
                sta     conin+1
                adc     #$03
                sta     conot+1
                adc     #$03
                sta     prnot+1
		rts
;sxbbind.asm
;print character in A to stdout
;keep X and Y, but not necessarily S
PUTC		JMP     $FF3C           ;Call C02 BIOS
;
;check for character ready at input
;returns a=0 and z=0 if none and a=1 and z-0 if ready
mon_consts
CHKC		LDA     $DF             ;Check BIOS Input count
                BEQ     NO_CHR          ;If zero, exit, no data
		LDA     #$011		;say ready
NO_CHR		RTS

;wait until character ready then get character
;WAITC		jsr	CHKC		;see if character
;		beq	WAITC		;loop if none ekse
;get a character from stdin
;call only after CHKC says character is ready
;keep X and Y, but not necessarily S
;C=0 on return is ok, C=1 on return is eof
GETC		JSR     $FF39           ;Call C02 BIOS
		CLC
		RTS
                ;
;	OUTPUT: Output to console device
output	and	#$7f		;set the high bit to zero
	cmp	#bs		;pass a backspace
	beq	out1
	cmp	#cr		;pass a cr
	beq	out1
	cmp	#lf		;pass a lf
	beq	out1
	cmp	#space		;don't print control codes
	bcc	out2
out1	jsr	conout		;print the char
out2	rts
;main program execution starts here
start	jsr	setsim		;set jump addresses to sim
;clear page zero data area
	ldx	#pzstrt		;set index to start
	lda	#0		;clear accum
clrlpe	sta	$00,x		;clear a byte
	inx			;bump index
	cpx	#lastzp		;see if end
	bne	clrlpe		;loop if not
	jsr	ilprt		;print opening message
	byte	"XSBC123 (XMODEM) - VERSION 1.23",cr,lf
	byte	"FOR UART PORT @ 115,200 BPS"
	byte	cr,lf,lf,0
	lda	fcb+1		;get primary option
	cmp	#'H'
	bne	n1
	jmp	help		;Yes, give help
n1	cmp	#'X'
	bne	n2
	jmp	exam		;Give examples
;
;Save primary option, validate secondary option
;
N2	jsr	procop
;
;move the file name from fcb 2 to fcb 1
;
	jsr	movfcb
;
;initialize the serial port
;
	jsr	intmod		;initialize port and modem
;
;Jmp to appropriate function
;
	lda 	option		;recover the pri option
	cmp	#'C'		;"COMPUTER" term echo
	bne	op1		;look for more
	jmp	trmech		;go to term echo
OP1	cmp	#'E'		;terminal in echo
	bne	op2		;branch if not
	jmp	trmech		;terminal in echo
OP2	cmp	#'T'		;terminal mode?
	bne	op3
	jmp	term		;go to terminal mode
OP3	cmp	#'D'		;disconnect?
	bne	op4		;branch if no
	jmp	discon		;disconnect
OP4	cmp	#'S'		;send a file?
	bne	op5		;no ->
	jmp	senfil		;go send file
OP5	cmp	#'R'		;receive a file?
	bne	op6		;no ->
	jmp	rcvfil		;go receive a file
op6	cmp	#'P'		;print input
	bne	op7		;no ->
	jmp	prndta		;go print file
OP7	jmp	badopt		;none left, error exit
;
;*	TERM: Terminal mode		 *
;
;This program simply sends keyed characters
;down the line, and displays characters
;received from the line. This makes it
;suitable for communication with time sharing
;computers, CBBS's, or another program
;running "XMODEM E" (echo mode)
;
;Type CTRL-E to exit and warm boot.
;
;NOTE: The "DISCCHR" has not been implemented in
;this version of MODEM.
;
term	jsr	chkc		;test for byte ready
	beq	ckkeys		;none ready
	jsr	getc		;get modem byte
	jsr 	output		;output to screen
ckkeys	jsr	const		;look for keys pressed
	and	#$ff		;test result
	beq	term		;no keys, check modem again
	jsr 	coninp		;get the key pressed
	cmp	#ctrle		;check for escape code
	bne	keys1		;branch if not
	jmp	boot		;end
keys1	jsr	putc		;output it to modem
	bra	term		;go back to modem input
;
;prndta: printer spooler
;
;Type CTRL-E to exit and warm boot.
;
prndta	jsr	chkc		;test for byte ready
	beq	chkkey		;none ready
	jsr	getc		;get modem byte
	jsr	prnot		;send char to printer
chkkey	jsr	const		;look for keys pressed
	and	#$ff		;test result
	beq	prndta		;no keys, check modem again
	jsr 	coninp		;get the key pressed
	cmp	#ctrle		;check for escape code
	bne	prndta		;loop if not
	jmp	boot		;end
;
;*	TRMECHO: Terminal with echo  *
;
;Terminal program with echo - see notes
;under "TERM" above
;
;C A U T I O N  Don't run with both computers
;in "ECHO" mode - line errors (or any char)
;will be echoed back and forth ad infinitum.
;
trmech	jsr	chkc		;check input status
	beq	ckkey1		;branch if no input
	jsr	getc		;get modem byte
	pha			;save it
	jsr	putc		;echo it
	pla			;get it back
	jsr	output		;output to screen
CKKEY1	jsr	const		;look for keys pressed
	and	#$ff		;test result
	beq	trmech		;no keys, check modem again
	jsr	coninp		;get the key pressed
	cmp	#ctrle		;check for escape code
	bne	keys2		;branch if not
	jmp	boot		;exit
KEYS2	pha			;save it
	jsr	putc		;output it to modem
	pla			;get it again
	jsr	output		;put it on the screen
	bra	trmech		;go back for modem input
;
;*	SENDFIL: Sends a DOS/65 file	     *
;
;The DOS/65 file specified in the modem command
;is transferred over the phone to another
;computer running XMODEM with the "R"
;(receive) option. The data is sent one sector
;at a time with headers and checksums, and
;re-transmission on errors.
;
SENFIL	jsr	trap		;check for no name or ambig
	jsr	openfi		;open the file
	lda	#255		;wait up to 255 secs for..
	sta	wait		;..initial NAK
	jsr	waitna		;get initial NAK
;
SENDLP	jsr	rdsect		;read a sector
	bcs	seneof		;send EOF if done
	inc	secnum		;bump sector #
	lda	#0		;init error..
	sta	errcnt		;..count
;
SENRPT	jsr	senhdr		;send a header
	jsr	sensec		;send the data sector
	jsr	sencks		;send the checksum
	jsr	getack		;get the ACK
	bcs	senrpt		;repeat if no ACK
	bcc	sendlp		;loop until EOF
;
;
;File sent, send EOT's
;
SENEOF	lda	#EOT		;send..
	jsr	send1		;.. an EOT
	jsr	getack		;get the ACK
	bcs	seneof		;repeat if no ACK
	jmp	done		;all done
;
;*	RCVFIL: Receive a file		     *
;
;Receive a file in block format as sent
;by another person doing "XMODEM S fn.ft".
;
RCVFIL	jsr	trap		;check for no name or ambig name
	jsr	erasfi		;erase the file
	jsr	makefi		;..then make new
	jsr	ilprt		;print
	byte	"FILE OPEN, READY TO RECEIVE",cr,lf,0
;
RCVLP	jsr	rcvsec		;get a sector
	bcs	rcveot		;got end of transmission
	jsr	wrsec		;save the sector
	inc	secnum		;bump the sector number
	jsr	sendac		;send the ack
	jmp	rcvlp		;loop until end of file
;
;Got EOT on sector - flush buffers, end
;
RCVEOT	jsr	wrbloc		;write the last block
	jsr	sendac		;ack the sector
	jsr	closef		;close the file
	jmp	done		;print message & return
;
;*		SUBROUTINES			 *
;convert character in a from lower case to upper case
lwrupr	cmp	#'a'		;if < a
	bcc	notlc		;then ok
	cmp	#'z'+1		;if > z
	bcs	notlc		;then ok
	and	#$5f		;else convert
notlc	rts
;console input and output with msb clear
;input
coninp	jsr	conin		;go to sim
	and	#$7f		;clear msb
	rts
;output
conout	and	#$7f		;clear msb
	jmp	conot		;go to sim
;modem input, output, and status routines
;initialize modem and port
;Initial version leaves just a NOP and a RTS
intmod	nop			;do nothing
	rts
;
;---->	RCVSECT: Receive a sector
;
;Returns with carry set if EOT received
;
RCVSEC	lda	#0		;init error count
	sta	errcnt
;
RCVRPT	lda	qflg		;quiet?
	beq	rcvsq		;yes, no stat msg.
	jsr	ilprt		;print
	byte	"AWAITING #",0
	lda	secnum		;get sector number
	clc			;add 1
	adc	#1		;(real later)
	jsr	hexo		;print in hex
	jsr	crlf		;then cr/lf
;
RCVSQ	lda	#10		;10 sec time out
	sta	seconds		;save it
	jsr	recv		;get SOH/EOT
	bcs	rcvser		;time out
	cmp	#0		;ignore nulls
	beq	rcvrpt
	cmp	#SOH		;got SOH?
	beq	rcv1		;yes, go ->
	cmp	#EOT		;end of transfer?
	bne	r1		;no, go try again
	sec			;yes,.. EOT
	rts			;from rcvsec
;
RCV1	jmp	rcvsoh
;
;Didn't get SOH or EOT -
;
R1	sta	tmpchr		;save char received
	lda	qflg		;quiet mode?
	beq	rcvser		;yes, ->
RCVSEH	lda	tmpchr		;restore char rcvd
	jsr	hexo		;print hex char
	jsr	ilprt		;tell user
	byte	"H$ RECEIVED, NOT SOH",cr,lf,0
;
;Didn't get valid header - purge the line,
;then send NAK.
;
RCVSER	jsr	onesec		;wait one second for character
	bcc	rcvser		;loop until sender done
	inc	errcnt		;abort if we
	lda	errcnt		;have reached
	cmp	#errlim		;the error limit
	bcc	rcvck2		;no, try again
;
;10 errors in a row
;
	lda	qflg		;quiet mode?
	beq	rcvsab		;yes, ->
RCVCKQ	jsr	ckquit		;Quit?
	bne	rcvsab		;yes, quit ->
;
;Line must be purged because sender probably started
;resending while operator answered RETRY/QUIT prompt.
;
RCVCK2	lda	#NAK		;send a NAK
	jsr	send1
	jmp	rcvrpt		;try again ->
;
RCVSAB	jsr	closef		;keep whatever we got
	jsr	ilprt		;abort
	byte	"++UNABLE TO RECEIVE BLOCK "
	byte	"- ABORTING++",cr,lf,0
	jmp	erxit		;quit
;Time out on receive
RCVSTO	lda	qflg		;Quiet mode?
	bne	rcvspt		;no, ->
	jmp	rcvser		;quiet ->
;
RCVSPT	jsr ilprt		;tell about it
	byte	"++TIME OUT++",0
;
RCVPRN	lda	errcnt		;get error count
	jsr	hexo		;print it
	jsr 	crlf		;clean up line
	jmp	rcvser		;try again
;
BLK	byte	0
;
;
;Got SOH - get block #, block # complimented
;
RCVSOH	jsr	onesec		;wait 1 sec for char
	bcs	rcvsto		;time out
	sta	blk		;save block number
	jsr	onesec		;go back for EOR blk #
	bcs	rcvsto		;time out
	sta	tmpsec		;save complemented block #
	lda	#$ff		;do a ones compliment
	eor 	tmpsec		;on it
	cmp	blk		;is it the same?
	beq	rcvdat		;yes, get data
;
;Got bad sector #
;
	lda	qflg		;ck quiet flag
	beq	r2		;yes, ->
;
RCVBSE	jsr	ilprt		;tell story
	byte	"++BAD SECTOR # IN HEADER++",cr,lf,0
R2	jmp	rcvser		;bump error count
;
RCVDAT	lda	blk		;get sector number
	sta	rcvsno		;save it
	lda	#0		;init checksum
	sta	csum		;count
	ldx	#0		;set up buffer pointer
	stx	bufind		;and hold it
;
RCVCHR	jsr	onesec		;wait for a char
	bcs	rcv2		;time out
	ldx	bufind		;restore X pointer
	sta	buffer,x	;save the character
	inc	bufind		;bump the pointer
	inx			;has it been 128 chars?
	cpx	#128
	bne	rcvchr		;no, go get the rest
	lda	csum		;verify checksum
	sta	tmpcsm		;save it for a while
	jsr	onesec		;get the checksum
	bcs	rcv2		;time out
	cmp	tmpcsm		;is it the same?
	bne	rcvcer		;no, try again
;
;Got a sector, it's a dup if = prev,
;	or ok if = 1 + prev sector
;
	lda	rcvsno		;verify the sector number
	sta	tmpsec		;hold it for a while
	lda 	secnum		;compare the two
	cmp	tmpsec
	beq	recvac		;same sector
	inc	a		;add one to it
	cmp	tmpsec		;should be the same
	bne	abt		;no match, abort
	clc			;carry off
	rts			;from rcvsec
;
RCV2	jmp	rcvsto
;
;Got Checksum
;
RCVCER	lda	qflg		;quiet?
	bne	rcvcpr		;no, ->
	jmp	rcvser		;quiet ->
;
RCVCPR	jsr	ilprt		;tell message
	byte	"++CHECKSUM++",0
	jmp	rcvprn		;go ->
;
;Previous sector repeated, due to the last ACK
;being garbage. ACK it so sender will catch up
;
RECVAC	jsr	sendac		;acknowledge the sector
	jmp	rcvsec		;go for more
SENDAC	lda	#ack		;send the
	jsr	send1		;acknowledgement
	rts
ABT	jmp	abort		;abort transfer
;
;---->	OPENFIL: Opens the file to be sent.
;
OPENFI	lda	#<fcb		;point to the file
	ldy	#>fcb		;to open
	ldx	#open		;get the function
	jsr	pem		;open the file
	bpl	openok		;open ok?
	jsr	ilprt		;no, print message..
	byte	"CAN NOT OPEN FILE",cr,lf,0
	jmp	erxit		;get out
OPENOK	jsr	ilprt		;print...
	byte	"FILE OPEN, EXTENT LENGTH: $",0
	lda	fcb+15		;get the number of sectors
	jsr	hexo		;print it
	jsr	crlf		;clean up the line
	rts
;
;---->	WAITNAK: Waits for initial NAK
;3
;To ensure no data is sent until the receiving
;program is ready, this routine waits for
;the first time out-NAK from the receiver.
;(WAIT) contains the # of seconds to wait.
;
WAITNA	lda	qflg		;quiet mode?
	beq	waitnl		;yes, ->
WAITNP	jsr	ilprt		;print...
	byte	"AWAITING INITIAL NAK",cr,lf,0
WAITNL	jsr	onesec		;wait one sec for NAK
	cmp	#NAK		;did we get it?
	bne	nonak		;no, ->
	rts			;yes, return
NONAK	dec	wait		;drop the count
	bne	waitnl		;if not time out, ->
	jmp	abort		;time out, abort ->
;
;---->	RDSECT: Reads a sector.
;
;For speed this routine buffers up 16
;sectors at a time.
;
RDSECT	dec	secinb		;see if any sectors in buffer
	bmi	rdbloc		;get more ->
	lda	secptr		;point to the data buffer
	ldy	secptr+1
	sta	from		;set up for a move
	sty	from+1
	lda	#<buffer	;destination buffer address
	ldy	#>buffer
	sta	to		;for the move
	sty	to+1
	jsr	mov128		;move a sector to buffer
	clc			;set up for an add
	lda	secptr		;to point to the next
	adc	#128		;sector to move
	sta	secptr		;save it
	bcc	rds1		;no carry, ->
	inc	secptr+1	;bump high pointer
	clc			;say ok
RDS1	rts			;from rdsect
RDBLOC	lda	eoflg		;get EOF flag
	cmp	#1		;is it set?
	bne	rdb1		;no, ->
	sec			;carry set for EOF
	rts
RDB1	lda	#0		;initialize sector counter
	sta	seccnt
	lda	#<dbuf		;set up destination address
	ldy	#>dbuf		;for transfer
	sta	to		;save it..
	sty	to+1
RDSECL	lda	to		;get the address for DOS
	ldy	to+1
	ldx	#stdma		;get the function
	jsr	pem		;set the DMA address
	lda	#<fcb		;point to the...
	ldy	#>fcb		;...fcb file
	ldx	#read		;get read function
	jsr	pem		;read sector into memory
	beq	rdseco		;read ok, ->
	bpl	reof		;found EOF, ->
	jsr	ilprt		;file error, print..
	byte	cr,lf,"++FILE READ ERROR++",cr,lf,0
	jmp	erxit		;get out
RDSECO	clc			;add the length..
	lda	to		;..of one sector..
	adc	#128		;..to the next..
	sta	to		;..buffer
	lda	to+1
	adc	#0
	sta	to+1
	inc	seccnt		;increment the counter
	lda	seccnt		;16 yet?
	cmp	#16
	beq	rdbful		;yes, ->
	bne	rdsecl		;no, read some more
REOF	lda	#1		;set the EOF flag
	sta	eoflg
	lda	seccnt		;get the sector load count
RDBFUL	sta	secinb		;save the sector count
	lda	#<dbuf		;initialize the buffer
	ldy	#>dbuf		;pointer
	sta	secptr		;save it
	sty	secptr+1
	lda	#<buffer	;reset the DMA address
	ldy	#>buffer
	ldx	#stdma		;get the DMA function
	jsr	pem		;reset DMA address
	jmp	rdsect		;go, ->
;
;---->	SENHDR: Send record header
;
SENHDR	lda	qflg		;quiet mode?
	beq	sendhn		;yes, ->
	jsr	ilprt		;print...
	byte	"SEND #",0
	lda	secnum		;get sector #
	jsr	hexo		;print it
	jsr	crlf		;clean up
SENDHN	lda	#SOH		;send...
	jsr	send1		;...SOH,
	lda	secnum		;then send..
	jsr	send1		;sector #
	lda	#$FF		;then sector #
	eor	secnum		;complemented
	jsr	send1		;..sector #
	rts			;from SENDHDR
;
;---->	SENDSEC: Send the data sector
;
SENSEC	ldx	#0		;init checksum
	stx	csum		;.. and..
	stx	bufind		;buffer offset
	lda	#128		;set up counter..
	sta	sndcnt		;for # of bytes
SENDC	ldx	bufind		;get offset into buffer
	lda	buffer,x	;get data
	inc	bufind		;bump offset
	jsr	send1		;send data
	dec	sndcnt		;drop counter
	bne 	sendc		;not done, ->
	rts			;from Sendsec
;
;Send the checksum
;
SENCKS	lda	csum		;get the checksum
	jmp	send1		;send it
;
;Time out getting ACK
;
GETTOT	lda	qflg		;quiet mode
	beq	ackerr		;yes, ->
	jsr	ilprt		;print..
	byte	"TIME OUT ON ACK",cr,lf,0
	jmp	ackerr		;abort
;
;---->	GETACK: Get the ACK on the sector
;
;Returns with carry clear if ACK received.
;if an ACK is not received, the error count
;is incremented, and if less than "ERRLIM",
;carry is set and control returns. If the
;error count is at "ERRLIM", the program
;aborts if in "QUIET" mode, or asks the
;user for quit/retry if not.
;
GETACK	lda	#10		;wait ten secs...
	sta	seconds		;..MAX
	jsr	recvdg		;recv w/garbage collect
	bcs	gettot		;timed out, ->
	cmp	#ACK		;ok?
	bne	getak1		;no, error ->
	clc			;carry off
	rts			;ok, ->
GETAK1	pha			;hold char recv'd
	lda	qflg		;quiet mode?
	beq	acker2		;yes, ->
	pla			;get char recv'd
	pha			;save it again
	jsr	hexo		;print it in Hex
	jsr	ilprt		;print mess..
	byte	"H RECEIVED, NOT ACK",cr,lf,0
ACKER2	pla			;clean up stack
ACKERR	inc	errcnt		;bump the error count
	lda	errcnt		;10 errors?
	cmp	#errlim
	beq	acker1		;yes, ->
	sec			;show error,
	rts			;return, not at limit
ACKER1	lda	qflg		;quiet mode?
	beq	csabor		;yes, abort transfer
GACKV	jsr	ckquit		;see if user wants to quit
	bne	csabor		;yes they do
	sec			;no, try again
	rts
CSABOR	jsr	ilprt		;print..
	byte	"TIME OUT ON ACK",cr,lf,0
	jmp	erxit		;abort transfer ->
;
;----> MAKEFILE: Makes the file to be received.
;
MAKEFI	lda	#<fcb		;load a & y with
	ldy	#>fcb		;the fcb address
	ldx 	#make		;set x to make a file
	jsr	pem		;make the file
	bpl	mak1		;ok, file made ->
	jsr 	ilprt		;tell the user the bad news
	byte	"++ERROR - CAN NOT MAKE FILE++",cr,lf
	byte	"++DIRECTORY MAY BE FULL++",cr,lf,0
	jmp	erxit		;get out
MAK1	rts			;done with makefile
;
;----> ERASEFILE: Erase the incoming file.
;
;If it exist, ask if it may be erased.
;
ERASFI	lda	#<fcb		;point a & y to the
	ldy	#>fcb		;fcb address
	ldx	#srchf		;set x to look for file
	jsr	pem		;search for file name
	bmi	er1		;if not found then ->
	jsr 	ilprt		;give the message
	byte	"FILE EXISTS, TYPE Y TO ERASE "
	byte	"OTHER TO QUIT",cr,lf,0
	jsr	coninp		;get the input
	pha			;save it
	jsr	output		;print it
	jsr	crlf		;clean up the line
	pla			;get char back
	jsr	lwrupr		;convert to upper case
	cmp	#'Y'		;was it 'yes'
	beq 	er2		;yes, ->
	jmp	ckdis		;no, get out
ER2	lda	#<fcb		;set a & y to the
	ldy	#>fcb		;fcb address
	ldx	#erase		;set x to erase
	jsr 	pem		;erase the file name
ER1	rts			;from erasefile
;
;----> TRAP: Check for no file name or ambiguous name
;
TRAP	ldx	#1		;point to 1st char in fcb
	lda	fcb,x		;get it
	cmp	#space		;is it blank?
	bne	atrap		;no, the names there
	jsr	ilprt		;tell the user
	byte	"++NO FILE NAME SPECIFIED++",cr,lf,0
	jmp	erxit		;get out
ATRAP	lda	fcb,x		;now look for ambig
	cmp	#'?'		;chars in file name
	beq	trerr		;branch if found
	inx			;bump the pointer
	cpx	#11		;looked at all chars yet?
	bne	atrap		;no ->
	rts			;from TRAP
TRERR	jsr	ilprt		;tell the user
	byte	"++CAN NOT USE WILD CARD"
	byte	" OPTIONS++",cr,lf,0
	jmp	erxit		;bad exit form TRAP
;
;----> CLOSEFILE: Closes the received file.
;
CLOSEF	lda	#<fcb		;a & y point
	ldy	#>fcb		;to the file
	ldx	#close		;set x to close code
	jsr 	pem		;close the file
	bpl	clo1		;if OK ->
	jsr	ilprt		;give error message
	byte	"++CAN NOT CLOSE FILE - ERROR++"
	byte	cr,lf,0
	jmp	erxit		;error exit
clo1	rts			;from closef
;
;---->	WRSEC: Write a sector
;
;Writes the sector into a buffer. When 16
;have been written, writes the block to disk.
;
;entry point "WRBLOC" flushes the buffer at EOF.
;
WRSEC	lda	#<buffer	;set up a & y
	ldy	#>buffer	;for a move to
	sta	from		;track buffer
	sty	from+1
	lda	secptr
	ldy	secptr+1
	sta	to
	sty	to+1
	jsr	mov128		;move 128 bytes
	clc			;bump the sector pointer
	lda	secptr		;ahead 128 bytes
	adc	#128
	sta	secptr		;save it
	bcc	wrs1		;branch if no carry
	inc	secptr+1	;bump the high byte
WRS1	inc	secinb		;bump the sector count moved
	lda	secinb		;check for a full track yet
	cmp	#16		;16 sectors = 1 track
	beq	wrbloc		;yes, ->
	rts			;from WRSEC
;
;---->	WRBLOC: Writes a block to disk
;
WRBLOC	lda	secinb		;see if there is anything
	beq	wrbloc-1	;to write. no, ->
	sta	seccnt		;save the sector count
	lda	#<dbuf		;set the DMA address
	ldy	#>dbuf		;to the track buffer
	sta	to		;save address
	sty	to+1
DKWRLP	ldx	#stdma		;set x = set DMA
	jsr	pem		;set the buffer address
	lda	#<fcb		;set up for a file write
	ldy	#>fcb
	ldx	#write		;x = Write
	jsr 	pem		;write a sector
	bne	wrerr		;error? ->
	clc			;now point to next sector
	lda	to
	adc	#128
	sta	to
	bcc	wrs3
	inc	to+1
WRS3	lda	to		;get new DMA address
	ldy	to+1		;into a & y
	dec	seccnt		;drop the sector count
	bne	dkwrlp		;more to write ->
	lda	#0		;put zero into sector count
	sta	secinb
	lda	#<dbuf		;set pointers to the start
	ldy	#>dbuf		;of the track buffer
	sta	secptr
	sty	secptr+1
RSDMA	lda	#<buffer	;set DMA address to the
	ldy	#>buffer	;default buffer
	ldx	#stdma		;x = set DMA
	jmp	pem		;set default buffer address
;error writing to file
WRERR	jsr	rsdma		;reset buffer address
	jsr	ilprt		;tell the bad news
	byte	"++ERROR WRITING FILE++",cr,lf,0
	jmp	abort		;abort
;Enter RECV and use one second
ONESEC	lda	#1		;set up for a one second
	sta	seconds		;wait on receive char
	bne	recv		;always ->
;
;---->	RECV: Receive a character
;
;Time out time is in SECONDS, in seconds. Entry via
;"RECVDG" deletes garbage characters on the
;line. For example, having just sent a sector,
;calling RECVDG will delete any line-noise-induced
;characters long before the ACK/NAK would
;be received.
;The operations involved in the inner timing
;loop with number of clock cycles required are:
;	jsr	35
;	beq	4
;	jsr	7x12
;	lda	3
;	bne	4
;	dec	5
;	lda	3
;	ora	3
;	bne	4
; TOTAL		145
;With 8 MHz CPU clock this means inner loop can consume
;up to 4640 usec in the inner loop. Adding the small
;outer loop delays says 221 outer loop cycles
;will yield e delay time of 1 second.
;
recvdg
RECV	lda	#0		;set up for a delay loop
	sta	inner		;start inner at 256
	lda	#221		;then outer at 227
	sta	outer
mwti	jsr	chkc		;test input status
	beq	nochar		;not ready, ->
	jsr	getc		;receive a char
	jsr	chksum		;update the checksum count
	clc			;carry clear = got char
	rts			;from RECV
;count down the timers
NOCHAR	jsr	rdelay		;add 12 cycles of delay
	jsr	rdelay		;add 12 cycles of delay
	jsr	rdelay		;add 12 cycles of delay
	jsr	rdelay		;add 12 cycles of delay
	jsr	rdelay		;add 12 cycles of delay
	jsr	rdelay		;add 12 cycles of delay
	jsr	rdelay		;add 12 cycles of delay
	lda	inner		;see if inner 0
	bne	nochrz		;skip if non zero
	dec	outer		;but drop outer if inner 0
nochrz	dec	inner		;always drop inner
	lda	inner		;check for zero result
	ora	outer
	bne	mwti		;loop if not zero
	dec 	seconds		;dec the seconds count
	bne	recv		;wait more? ->
	sec			;carry set = time out
rdelay	rts			;from RECV
;
;---->	SEND: Send a character to the modem
;
;	CTRL-C will abort the transfer and send a CAN
;
SEND1	jsr	chksum		;update the checksum
	jsr	putc		;send the char
	jsr	polkey		;poll for a key pressed
	cmp	#ctrlc		;control-c ?
	bne 	nostop		;no ->
	pla			;yes, pop return address
	pla			;to here
	jmp	abort		;exit
NOSTOP	rts			;from SEND1
;calculate checksum using byte in a while saving A
chksum	php			;save status
	pha			;then byte
	clc			;set up for an add
	adc	csum		;add it to checksum
	sta	csum		;save it
	pla			;get byte
	plp			;then status
	rts			;from CHKSUM
;
;---->	SHOW: Shows chars sent/received
;
;CR, LF, and TAB are shown. All other
;non-printable characters are shown in
;hex as (XX)
;
SHOW	cmp	#lf		;is it a linefeed?
	beq	ctype		;yes, ->
	cmp	#cr		;is it a cr
	beq	ctype		;yes, ->
	cmp	#tab		;Tab?
	beq	ctype		;yes, ->
	cmp	#space		;control char?
	bcc	showhe		;yes, ->
	cmp	#$7f		;ascii?
	bcc	ctype		;yes, ->
SHOWHE	pha			;save char
	lda	#'('		;put it in ()
	jsr	conout		;type
	pla			;get back char
	jsr	hexo		;print hex char
	lda	#')'		;closing ")"
CTYPE	jsr	conout		;print char in a
	rts			;from SHOW
;
;---->	HEXO:  output byte in a as two hex chars to  console
;
HEXO	pha			;hold char
	lsr	a		;get high byte
	lsr	a
	lsr	a
	lsr	a
	jsr	nibbl		;print high nibble
	pla			;get char again
NIBBL	and	#$0f		;mask off high nibble
	cmp	#$0A		;set or clear carry
	sed			;sed for decimal add
	adc	#$30		;make it ascii
	cld			;back to binary add
	jmp	conout		;print it
;
;---->	POLKEY: Scan the keyboard for keys pressed
;
;
;Returns with ZERO if no input.
;
POLKEY	jsr	const		;check console for input
	and	#$ff		;test result
	beq	pol1		;no, ->
	jsr	coninp		;yes, read console
POL1	rts			;from POLKEY
;
;---->	ABORT: Abort the file transfer
;
ABORT	jsr	onesec		;wait 1 sec without chars
	bcc	abort		;loop until sender done
	lda 	#can		;send a cancel
	jsr 	send1
	jsr	ilprt		;exit with abort message
	byte	"XMODEM PROGRAM CANCELLED",cr,lf,0
	jmp	ckdis		;go to exit
;
;---->	DONE: Normal exit
;
DONE
DONETC	jsr	ilprt		;print message
	byte	"TRANSFER COMPLETE",cr,lf,0
DONE1	lda	termfl		;check terminal flag
	bne	done2		;no ->
	jmp	term
DONE2	lda	echofl		;check echo flag
	bne	ckdis		;no, ->
	jmp	trmech		;go to terminal echo
;
;---->	CKDIS: Check for disconnect
;
ERXIT
CKDIS	lda	discfl		;check disconnect flag
	bne	discon		;no, ->
	jsr 	ilprt		;print message
	byte	cr,lf,"PRESS RETURN TO DISCONNECT:",0
	jsr	coninp		;get a key
	jsr	crlf		;print cr,lf
	cmp	#cr		;cr?
	bne	ckdis		;no, ->
;disconnect - this version does nothing
DISCON	jmp	boot		;exit
;
;---->	CRLF:  send cr and lf to console
;
;preserves whatever was in a at entry
CRLF	pha			;save a
	lda	#cr
	jsr	conout
	lda	#lf
	jsr	conout
	pla			;restore a
	rts
;
;---->  CKQUIT: Quit/Retry after multiple errors
;
;Returns w/zero set if retry asked for
;
CKQUIT	lda	#0		;zero out error count
	sta	errcnt
CKQLP	jsr	ilprt		;print:
	byte	"MULTIPLE ERRORS ENCOUNTERED",CR,LF
	byte	"TYPE CTRL-E TO QUIT, R TO RETRY:",0
	jsr	coninp		;get response
	pha			;save it
	jsr	conout		;print it
	jsr 	crlf		;clean up line
	pla			;retrieve response
	jsr	lwrupr		;convert to upper case
	cmp	#'R'		;retry?
	beq	ckq1		;yes, go on
	cmp	#CTRLE		;see if quit
	bne	CKQLP		;loop if not
	lda	#$FF		;set to non-zero
CKQ1	rts			;from CKQUIT
;
;---->	ILPRT: In line print of message
;
;The call to ILPRT is followed by a message,
;binary zero as the end. Binary one may be
;used to pause with message 'PRESS RETURN TO CONTINUE'
;
ILPRT	pla			;move the return
	sta	stroad		;address into
	pla			;zero page
	sta	stroad+1
n6	ldy	#1		;set y for addr+1
	lda	(stroad),y	;get the char
	beq	n3		;branch if done
	cmp	#1		;pause if #1
	bne	n5
	jmp	lpause		;pause
n5	jsr	conout		;print char
lpnext	inc	stroad		;bump the pointer
	bne	n4		;no carry >
	inc	stroad+1	;bump high byte
n4	jmp	n6		;go back for more
n3	inc	stroad		;set return address
	bne	n7
	inc	stroad+1
n7	lda	stroad+1	;put addr back
	pha			;onto stack
	lda	stroad
	pha
	rts			;return past mess.
;pause until return pressed
LPAUSE	lda	#<paumes	;set pointers
	ldy	#>paumes	;for pause message
	ldx	#print		;set pem command
	jsr	pem		;print it
	jsr	coninp		;wait for a key
	cmp	#ctrle		;see if quit
	beq	n8		;is so quit
	cmp	#cr		;continue code?
	bne	lpause		;no ->
	jmp	lpnext		;is so print more
n8	jmp	boot		;EXIT
PAUMES	byte	cr,lf
	byte	"PRESS RETURN TO CONTINUE OR CTRL-E TO EXIT"
	byte	cr,lf,"$"
;
;---->  PROCOP: Process command options
;
;1) Save the primary option in 'OPTION';
;2) Scans the sub-option characters, and for
;each found, zeros the appropriate entry in
;the option table. For example if 'D' is
;coded (DISCONNECT) then the 'D' stored at
;'DISCFL' is set to 0 so it can be tested
;later.
;
PROCOP	ldx	#0		;save the primary
	lda	fcb+1,x		;option
	sta	option
N10	inx			;point to the sec option
	lda	fcb+1,x		;get it
	cmp	#space		;if blank-> end of opts
	beq	endopt
	stx	optbl		;save sec option pointer
	ldx	#1		;point to start op opts table
N11	cmp	optbl,x		;look for a match
	bne	n9		;not this one ->
	lda	#0		;found option
	sta	optbl,x		;put a zero in it
	ldx	optbl		;recover fcb pointer
	bne 	n10		;always branch
N9	inx			;bump opt tbl pointer
	cpx	#optbe-optbl	;option table length
	bne	n11		;if more ->
	jmp	badopt		;bad option -> error mess
ENDOPT	rts			;from procop
;
;Sub-option table. If an option is in effect,
;the character is set to binary 0
;
OPTION	byte	0		;pri option saved here
OPTBL	byte	0		;secondary option table
ANSWFL	byte	"A"		;answer mode
DISCFL	byte	"D"		;disconnect when done
ECHOFL	byte	"E"		;to echo after xfer
ORIGFL	byte	"O"		;originate mode
QFLG	byte	"Q"		;quiet transfer (no msgs)
TERMFL	byte	"T"		;to term after xfer
OPTBE
SECPTR	word	Dbuf		;Start of the block buffer
SECNUM	byte	0		;sector number storage
;move FCB
MOVfcb	lda	#<fcb2		;set up 'from'
	ldy	#>fcb2		;address
	sta	from
	sty	from+1
	lda	#<fcb		;set up 'to'
	ldy	#>fcb		;address
	sta	to
	sty	to+1
	ldx	#16		;length to move
	jsr	move		;do the move
	lda	#0		;get a zero
	sta	fcbsno		;set sector #
	sta	fcbext		;and the extent
	sta 	fcbext+1
	rts
;move 128 bytes from (from) to (to) using x as counter
MOV128	ldx	#128		;set up to move 128
;move x bytes from (from) to (to)
MOVE	ldy	#0		;set index to zero
movelp	lda	(from),y	;get byte
	sta	(to),y		;put byte
	iny			;bump index
	dex			;decrement the length
	bne	movelp		;go back for more
	rts			;from move
;
;Invalid command
;
BADOPT	jsr	ilprt		;exit w/error
	byte	":INVALID OPTION ON XMODEM "
	byte	"COMMAND -",cr,lf
	byte	"PRESS RETURN FOR HELP, OR "
	byte	"CTRL-E TO EXIT",cr,lf,0
	jsr	coninp		;get key
	cmp	#cr		;see if RETURN
	beq	HELP		;if so do HELP
	cmp	#CTRLE		;see if ctrl-e
	bne	badopt		;loop if not
	jmp	boot		;but boot if is
;e5xecute HELP option
HELP	jsr	ilprt
	byte	cr,lf
	byte	"Format for command is:",cr,lf
	byte	"XMODEM # FILENAME",cr,lf,cr,lf
	byte	"Where # is a 1 character "
	byte	"primary option,",cr,lf
	byte	" which may be followed by "
	byte	"sub-options"
	byte	cr,lf,1
	byte	"Primary options",cr,lf
	byte	"   S to send a file",cr,lf
	byte	"   R to receive a file",cr,lf
	byte	"   T to act as a terminal",cr,lf
	byte	"   E to act as a computer "
	byte	"(echo data)",cr,lf
	byte	"   P to send input to printer",cr,lf
	byte	"   D to disconnect the line",cr,lf
	byte	"   H to print this help file"
	byte	cr,lf,1
	byte	"Secondary options:",cr,lf
	byte	"   A answer mode",cr,lf
	byte	"   O originate mode",cr,lf
	byte	"   D disconnect after "
	byte	"execution",cr,lf
	byte	"   T to go to terminal mode "
	byte	"after xfer",cr,lf
	byte	"   E to go to echo mode "
	byte	"after file xfer",cr,lf
	byte	"   Q quiet mode - no status "
	byte	"msgs",cr,lf
	byte	cr,lf,"FOR EXAMPLES, TYPE: XMODEM X"
	byte	cr,lf,0
	jmp	exit
EXIT	jmp	boot
EXAM	jsr	ilprt
	byte	"Send a file, originate mode",cr,lf
	byte	"   XMODEM SO fn.ft",cr,lf
	byte	"Send another file:",cr,lf
	byte	"   XMODEM S fn.ft",cr,lf
	byte	"Send a third file and "
	byte	"disconnect:",cr,lf
	byte	"   XMODEM SD fn.ft",cr,lf
	byte	"Act as a terminal, originate"
	byte	"mode:",cr,lf
	byte	"   XMODEM TO",cr,lf
	byte	"   (Use ctrl-E to disconnect)",cr,lf
	byte	"Receive a file, answer mode"
	byte	", view it:",cr,lf
	byte	"   XMODEM RA fn.ft",cr,lf,0
	jmp	exit
;block storage buffer
dbuf	ds	16*128		;16 records
	ends
	end
