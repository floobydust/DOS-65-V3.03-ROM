	globals	on
	case	off
	chip	65c02
	pw	132
	pl	44
;ucopy
;Version 3.02-S
;released:	9 February 2015 (3.00-2)
;last revision:
;		2 March 2015 (3.01)
;			changed exit to through PEM
;		13 August 2017 (3.02)
;			changed name
;			cleaned up messages
;Program to copy files from one location to another including user area.
;Syntax is
;	UCOPY FROMUFN TOUFN
;Where the TOUFN may simply be a drive
;specification in which case the destination
;will have the same name as the source.
;Key differences between this and prior COPY versions is
;use of the from to syntax and incorporation of code
;to ensure CCM is preserved so a RTS can be done
;at the end rather than a warm boot. V3.00
;adds the ability to copy a file from one user
;area to another. UCopy will ask for the
;from and to user areas.
;
;fixed parameters
pzstrt	equ	$30		;start of free page zero RAM
cr	equ	$0D		;return
lf	equ	$0A		;linefeed
DFLFCB	equ	$107		;default fcb
PEM	equ	$103		;pem entry
BOOT	equ	$100		;warm boot
TEA	equ	$800		;execution org
ccmlng	equ	2304		;CCM length
;page zero variables

        page0

	org	pzstrt
NAMED			;"to" file named if <128
	defs	1
TOIND		      	;"to" file index
	defs	2
FRMIND		      	;"from" file index
	defs	2
EOFFLG		      	;eof flag if >127
	defs	1
BUFLNG		      	;buffer length
	defs	2
FromUn		      	;from user code
	defs	1
ToUn		      	;to user code
	defs	1
DflUn		      	;default user code
	defs	1
user		      	;user number work area
	defs	1
savex		      	;save x
	defs	1
savey		      	;save y
	defs	1

        ends

        code

	;main program
	org	TEA
;send opening banner
	lda	#<opnmsg
	ldy	#>opnmsg
	jsr	msgout
;capture default user code
	jsr	getusr		;make PEM call
	sta	DflUn		;and save
;now start processing
	SEC			;calculate
	LDA	PEM+1		;amount
	SBC	#<BUFFER	;of free memory
	AND	#$80		;in mod 128
	STA	BUFLNG		;and
	LDA	PEM+2		;save
	SBC	#>BUFFER	;for
	STA	BUFLNG+1	;read/write
	sec			;now back up before SIM
	lda	buflng
	sbc	#ccmlng*256/256
	sta	buflng
	lda	buflng+1
	sbc	#ccmlng/256
	sta	buflng+1
	CLC			;now
	LDA	BUFLNG		;add
	ADC	#<BUFFER	;start
	STA	BUFLNG		;back
	LDA	BUFLNG+1	;to
	ADC	#>BUFFER	;get
	STA	BUFLNG+1	;max index
;check for ambiguous names
	LDA	#'?'		;get a ?
	LDX	#11		;set index
TSTAMB	CMP	DFLFCB,X	;test to
	BNE	OK000		;ok if not
	JMP	BADFIL		;else error
OK000	CMP	DFLFCB+16,X	;now try from
	BNE	OK001		;also ok if not
	JMP	BADFIL		;else error
OK001	DEX			;drop index
	BNE	TSTAMB		;loop if more
;now make sure source is named
	LDA	#' '		;get a space
	CMP	DFLFCB+1	;try name
	BNE	NOTZIP		;ok if different
	CMP	DFLFCB+9	;now try type
	BNE	NOTZIP		;also ok if diff
	JMP	BADFIL		;else error
;now see if destination not named
NOTZIP	STX	NAMED		;say named for now
	CMP	DFLFCB+17	;try name
	BNE	ISNAMD		;ok if diff
	CMP	DFLFCB+25	;now try type
	BNE	ISNAMD		;also ok if diff
	DEC	NAMED		;else make neg
;determine user areas for FROM and TO files
isnamd	lda	#<frmums	;point to from user area message
	ldy	#>frmums
	jsr	msgout		;send message
	jsr	gssun		;get response for FROM
	jsr	bcdbyt		;make a single byte
	cmp	#16		;see if too big
	bcc	frmuok		;no so go to next
	lda	#<iermsg	;bad so say so
	ldy	#>iermsg
	jsr	msgout
	jmp	isnamd		;and loop
frmuok	sta	fromun		;and save
toredo	lda	#<toums		;now do same for TO
	ldy	#>toums
	jsr	msgout		;using same code
	jsr	gssun
	jsr	bcdbyt		;make a single byte
	cmp	#16		;see if too big
	bcc	touok		;no so go to next
	lda	#<iermsg	;bad so say so
	ldy	#>iermsg
	jsr	msgout
	jmp	toredo		;and loop
touok	sta	toun		;save TO user code
;set up fcbs
	LDX	#11		;set index
MOVNME	LDA	DFLFCB,X	;get from
	STA	FRMFCB,X	;and set
	BIT	NAMED		;test flag
	BMI	NMESME		;branch if no name
	LDA	DFLFCB+16,X	;else get to
NMESME	STA	TOFCB,X		;save "to" name
	STA	ENDFCB,X	;and in end
	DEX			;drop count
	BNE	MOVNME		;loop if more
;make sure drives are right
	LDA	DFLFCB+16	;get to
	STA	TOFCB		;and set
	STA	ENDFCB		;both to and end
	LDA	DFLFCB		;and same
	STA	FRMFCB		;for from
;clear rest of fcbs
	TXA			;clear a
	LDX	#32		;set index
CLRFCB	STA	TOFCB,X		;clear
	STA	ENDFCB,X	;all
	STA	FRMFCB,X	;fcbs
	DEX			;drop count
	CPX	#11		;see if at name
	BNE	CLRFCB		;loop if more
;make "to" a temp
	LDX	#3		;set index
	LDA	#'$'		;get byte
TMPLPE	STA	TOFCB+8,X	;insert
	DEX			;drop count
	BNE	TMPLPE		;loop if more
;try to open source
	jsr	SetFmU		;set "FROM" user code
	JSR	SFMFCB		;point to FCB
	JSR	OPNFIL		;open it
	BPL	OK002		;ok
	JMP	BADFIL		;else error
;set up destination
OK002	jsr	SetToU		;set "TO" user code
	JSR	STOFCB		;point to "to"
	JSR	DLTFIL		;delete it
	JSR	STOFCB		;point again
	JSR	CRTFIL		;make it
	BPL	OK003		;ok
	JMP	BADFIL		;else error
OK003	JSR	STOFCB		;one more time
	JSR	OPNFIL		;and open
	BPL	OK004		;ok
	JMP	BADFIL		;else error
;do the move
OK004
	LDA	#0		;clear eof
	STA	EOFFLG		;flag
	lda	#<cpymsg	;announce when copy in process
	ldy	#>cpymsg
	jsr	msgout
DOMOVE	JSR	RDEBUF		;read buffer
	JSR	WRTBUF		;now write it
	BIT	EOFFLG		;test flag
	BPL	DOMOVE		;loop if not
	jsr	SetToU		;set "TO" user code
	JSR	STOFCB		;point to "to"
	JSR	CLSFIL		;close it
	BPL	OK005		;ok
	JMP	BADFIL		;else error
;delete old "end" and rename "to"
OK005	JSR	SENFCB		;point to it
	JSR	DLTFIL		;delete it
	LDX	#11		;now move
RNMLPE	LDA	ENDFCB,X	;"end"
	STA	TOFCB+16,X	;to
	DEX			;"to"
	BNE	RNMLPE		;fcb
	JSR	STOFCB		;point to it
	JSR	RNMFIL		;and rename
	jsr	SetDfU		;set default user
	ldx	#0		;have PEM do warm boot
	jmp	pem		;done
;subroutines
;output with save
charot	pha			;save char
	stx	savex		;save x
	sty	savey		;and y
	jsr	outchr		;send
	ldy	savey		;restore
	ldx	savex		;x and y
	pla			;then char
	rts
;output character in A to console
outchr	ldx	#2		;character output
	jmp	PEM
;Initialize system
INTSYS	ldx	#13
	jmp	PEM
;select drive
SELDRV	ldx	#14
	jmp	PEM
;open file
OPNFIL	LDX	#15
	JMP	PEM
;close file
CLSFIL	LDX	#16
	JMP	PEM
;delete file
DLTFIL	LDX	#19
	JMP	PEM
;read record
RDERCR	LDX	#20
	JMP	PEM
;write record
WRTRCR	LDX	#21
	JMP	PEM
;create file
CRTFIL	LDX	#22
	JMP	PEM
;rename file
RNMFIL	LDX	#23
	JMP	PEM
;set buffer
SETBUF	LDX	#26
	JMP	PEM
;set dest fcb
STOFCB	LDA	#<TOFCB
	LDY	#>TOFCB
	RTS
;set source fcb
SFMFCB	LDA	#<FRMFCB
	LDY	#>FRMFCB
	RTS
;set end fcb
SENFCB	LDA	#<ENDFCB
	LDY	#>ENDFCB
	RTS
;disk error exit
BADFIL	LDA	#<ERRMSG
	LDY	#>ERRMSG
	jsr	msgout
	jsr	SetDfU		;set default user code
	ldx	#0		;do warm boot
	JMP	PEM
;send message to console
msgout	LDX	#9
	jmp	PEM
;set user code to DEFAULT
SetDfU	lda	DflUn
	jmp	SetUsr
;set user code to "FROM"
SetFmU	lda	FromUn
	jmp	SetUsr
;set user code to "TO"
SetToU	lda	ToUn
	jmp	SetUsr
;get user code
GetUsr	lda	#255
;set user code
SetUsr	ldx	#36
	jmp	PEM
;read buffer
;if eof then set flag
RDEBUF	jsr	SetFmU		;set user to "FROM"
	LDA	#<BUFFER	;set
	LDY	#>BUFFER	;index
	STA	FRMIND		;to buffer
	STY	FRMIND+1	;start
RDELPE	LDA	FRMIND		;get index
	LDY	FRMIND+1	;and
	JSR	SETBUF		;set buffer
	JSR	SFMFCB		;point to fcb
	JSR	RDERCR		;read a record
	BEQ	RDEOK		;ok if zero
	BPL	OK006		;eof if positive
	JMP	BADFIL		;else error
OK006	DEC	EOFFLG		;set flag
	RTS			;and quit
RDEOK	CLC			;now
	LDA	FRMIND		;add
	ADC	#128		;128
	STA	FRMIND		;to
	BCC	NOFRMC		;index
	INC	FRMIND+1	;for next
NOFRMC	CMP	BUFLNG		;compare to low
	BNE	RDELPE		;loop if ok
	LDA	FRMIND+1	;get high
	CMP	BUFLNG+1	;compare it
	BNE	RDELPE		;also loop if more
	RTS
;write buffer
WRTBUF	jsr	SetToU		;set user to "TO"
	LDA	#<BUFFER	;set
	LDY	#>BUFFER	;index
	STA	TOIND		;to
	STY	TOIND+1		;start
WRTLPE	LDA	TOIND		;get current
	LDY	TOIND+1		;index
	JSR	SETBUF		;and set
	LDA	TOIND		;compare index
	CMP	FRMIND		;to read
	BNE	DOWRT		;ok if diff
	LDA	TOIND+1		;do same
	CMP	FRMIND+1	;for high
	BNE	DOWRT		;index
	RTS			;else done
DOWRT	JSR	STOFCB		;point to fcb
	JSR	WRTRCR		;write record
	BEQ	OK007		;ok
	JMP	BADFIL		;else error
OK007	CLC			;now
	LDA	TOIND		;add
	ADC	#128		;128
	STA	TOIND		;to index
	BCC	WRTLPE		;with
	INC	TOIND+1		;carry
	jmp	WRTLPE		;and loop always
;get and save user number
gssun
gssagn	jsr	rinclw		;get input
	jsr	chkdec		;see if first is decimal
	bcc	gsserr		;error if not
	cmp	#'0'		;if at least 0 is ok
	bcc	gsserr		;else error
	and	#%00001111	;get low nibble
	tax			;save in x
	sta	user+1		;store in high
	iny			;next char
	lda	ctxt,y		;get it
	bne	not1pg		;if not zero more than one
	stx	user		;else set low to old high
	sta	user+1		;and clear high
	rts
not1pg	jsr	chkdec		;see if decimal
	bcc	gsserr		;error if not
	and	#%00001111	;get nibble
	sta	user		;put in low
	iny			;next char
	lda	ctxt,y		;get it
	bne	gsserr		;error if not end
	rts
gsserr	lda	#<iermsg	;send illegal input message
	ldy	#>iermsg
	jsr	msgout
	jmp	gssagn		;and loop
;do buffered console input
rdeinp	lda	#<cbuf		;read buffer
	ldy	#>cbuf
	ldx	#10
	jmp	pem
;read input and convert lower case to upper
; error if no input or if input is all blanks.
; at exit y is index into ctxt
;         a is character at ctxt,y
rinclw	lda	#<cbuf		;point to
	ldy	#>cbuf		;buffer
	jsr	rdeinp		;read input
	lda	#lf		;send
	jsr	charot		;a lf
	ldy	#0		;clear index
	ldx	clng		;get length
	beq	rdiner		;error if zero
lwrcnv	lda	ctxt,y		;get char
	cmp	#'a'		;if less than a
	bcc	dochg		;is ok
	cmp	#'z'+1		;if over z
	bcs	dochg		;is ok
	and	#%01011111	;else convert
	sta	ctxt,y		;and save
dochg	iny			;bump index
	dex			;drop count
	bne	lwrcnv		;loop if more
	txa			;clear a
	sta	ctxt,y		;insert zero
	tay			;clear index
	jsr	spcskp		;find first non-blank
	beq	rdiner		;error if none
	rts			;else ok
rdiner	lda	#<iermsg	;point to
	ldy	#>iermsg	;input error message
	jsr	msgout		;print it
	jmp	rinclw		;try all over
;skip blanks
spcskp	lda	ctxt,y		;get char
	beq	spcext		;done if none
	cmp	#' '		;if not space
	bne	spcext		;then done
	iny			;else loop
	bne	spcskp		;and try again
spcext	rts
;check for decimal
; if decimal then c=1 else c=0
chkdec	cmp	#'0'		;if less than "0"
	bcc	notdec		;not number
	cmp	#'9'+1		;if less than "9"+1
	bcc	isdec		;is a number
notdec	clc			;not a number
	rts
isdec	sec			;a number
	rts
;pack BCD user into byte
;INPUT: user has low decimal digit, user+1
;holds high digit.
;OUTPUT: binary equivalent in A of user+(user1*10)
bcdbyt	clc			;clear carry
	lda	#0		;and accum
	ldx	#10		;then add high
bcdlpe	adc	user+1		;to accum
	dex			;10
	bne	bcdlpe		;times
	adc	user		;then add low
	rts			;and quit
;messages
ERRMSG	.BYTE	cr,lf,"ERROR - BAD FILE NAME - ABORTING$"
;opening message
opnmsg	.byte	"DOS/65 USER TO USER FILE COPY V3.02S$"
;FROM user area request
frmums	.byte	cr,lf
	.byte	"ENTER USER AREA FOR SOURCE FILE (0 TO 15)? $"
;TO user area request
toums	.byte	cr,lf
	.byte	"ENTER USER AREA FOR DESTINATION FILE (0 TO 15)? $"
;illegal input message
iermsg	.byte	cr,lf
	.byte	"ILLEGAL INPUT - REENTER $"
;copy in process message
cpymsg	.byte	cr,lf
	.byte	"COPY IN PROCESS $"
;console input buffer - small size in this version
cbuf
cmax	.byte	32		;input
clng	.byte	0		;buffer
ctxt
	defs	32
;source fcb
FRMFCB
	defs	33
;destination fcb
TOFCB
	defs	33
;end fcb
ENDFCB
	defs	33
;buffer
BUFFER

        ends

	END
