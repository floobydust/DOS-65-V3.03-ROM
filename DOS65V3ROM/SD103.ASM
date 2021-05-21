	GLOBALS	ON
	CASE	OFF
	CHIP	W65C02S
	PW	132
	PL	66
;SD.ASM VER 1.03 (WDC Assembler Format)
;DOS/65Super Directory based on CP/M Super Directory by Bruce R. Ratoff
;that was based on DIRS by Keith Petersen, W8SDZ
;
;Displays the directory of a DOS/65 drive, sorted alphabetically,
;with the file size in K, rounded to the nearest DOS/65 block size.
;
;THIS LATEST VARIATION ON A COMMON THEME WILL AUTOMATICALLY ADJUST
;ITSELF FOR ANY BLOCK SIZE AND DIRECTORY LENGTH UNDER DOS/65 2.1X or 3.x.
;PROVISIONS ARE MADE FOR (1) AUTOMATIC PAUSES
;WHEN THE SCREEN FILLS UP; (2) searching individual or multiple
;USER AREAS; (3) summary line output giving
;DRIVE AND USER INFORMATION, # OF FILES MATCHED AND HOW MUCH SPACE THEY
;CONSUME, AND THE AMOUNT OF FREE SPACE REMAINING ON THE DISK; (4) accepting
;ambiguous file names WITH OR WITHOUT A DRIVE NAME.
;
;Released:		27 March 2015 (V1.00) - Rich Leary
;Last Revision:		29 March 2015 (V1.01) - Rich Leary
;				corrected error with $'s in file name
;			30 March 2015 (V1.02) - Rich Leary
;				eliminated duplicate searches
;			4 August 2017 (V1.03) - Rich Leary
;				changed option char to =
;
;NOTE: Simple labels are used when doing some of the various
;6502/65C02 branch instructions. For example note that in
;the following code fragment the label NZ001 is a simple label that
;usually is only referenced within a very small address span.
;		inc	hl
;		bne	nz001
;		inc	hl+1
;	nz001
;In this case the label designates code flow as a result of a simple
;arithmetic operation.
;Several generic versions of such labels are used in this program and
;the follow the general pattern of
;		ccnnn
;where cc denotes a flag condition and nnn is a sequential numerical
;designator. cc's used include:
;	nz	not zero
;	eq	zero
;	cc	carry clear or borrow set
;	cs	carry set or borrow clear
;	pl	plus
;	mi	minus
;Labels used are as follows:
;	nz	nz001,nz004,nz005,nz020,nz021,nz010,nz011,nz013,
;		nz009,nz020
;	eq	eq030
;	cc	cc002,cc004,cc005,cc006,cc050,cc003
;	cs	cs002
;	pl	pl001
;	mi
;
;fixed values
FALSE	EQU	0
TRUE	EQU	1
;ASCII characters
lf	EQU	10			;line feed
cr	EQU	13			;carriage return
DELIM	EQU	7CH			;delimiter - vertical bar
;
;*****************************
;			     *
; USER OPTION SPECIFICATIONS *
;			     *
;*****************************

V3	EQU	TRUE			;True if DOS/65 V3.x vs V2.1
AOPT	EQU	TRUE			;True to allow searching all user areas
NOPT	EQU	TRUE			;True to allow disabling page pause option
OPTION	EQU	TRUE			;True if allowing ANY command line options
PGPAWZ	EQU	TRUE			;True for pause after each page
REPERR	EQU	TRUE			;True to report command line option errors
REPSIZ	EQU	TRUE			;True to report file sizes
REPUSR	EQU	TRUE			;True to report user numbers
UOPT	EQU	TRUE			;True to allow user number option


NPL	EQU	4			;names/line (max of 3 for 64x16)
;						    (MAX OF 4 FOR 80X24)

LPS	EQU	20			;lines/screen (max of 12 for 64x16)
;						      (MAX OF 20 FOR 80X24)
;
;PEM FUNCTION DEFINITIONS
wboot	EQU	0		;do warm boot
RDCHR	EQU	1		;Read char from console
WRCHR	EQU	2		;Write char to console
noecho	EQU	6		;read char from console - no echo
string	EQU	9		;send $-terminated string to console
CONST	EQU	11		;Check console status
SELDSK	EQU	14		;Select disk
SEARCH	EQU	17		;A=$ff if not found
NEXT	EQU	18		;same
CURDSK	EQU	25		;Get currently logged disk name
SETDMA	EQU	26		;Set current buffer addressDMA
GALLOC	EQU	27		;Get address of allocation vector
CurDCB	EQU	34		;Get current disk parameters
CURUSR	EQU	36		;Get or set current user number (3.x only)
;DCB contents are:
;	MAXBLK	.word		maximum block number
;	NRECRD	.word		number 128 byte records per track
;	NSYSTR	.word		number system tracks
;	BLKSCD	.byte		0=1024,1=2048,2=4096,3=8192,4=16384
;	MAXDIR	.word		max directory number
;	ALCMAP	.word		address of allocation map
;	CHKFLG	.byte		check directory flag
;	CHKMAP	.word		address of checksum map
;DOS/65 addresses
pzstrt	EQU	$30		;page zero start
PEM	EQU	$103		;fixed PEM entry point
DflFCB	EQU	$107		;default FCB
DflBuf	EQU	$128		;default disk buffer
TEA	EQU	$800            ;default TEA
;
	page0
;page zero storage
	ORG	pzstrt
oldusr	DEFS	1		;user number upon invocation
newusr	DEFS	1		;user number selected by "$U" option
OLDDSK	DEFS	1		;Holder for currently logged-in drive
curdrv	DEFS	1		;current drive
SCOUNT	DEFS	2		;# to sort
SUPSPC	DEFS	1		;Leading space flag for decimal routine
TOTFIL	DEFS	2		;Total number of files
TOTSIZ	DEFS	2		;Total size of all files
HL	DEFS	2		;16 bit pointer
;next three variables are associated with option scan process
BufInd	DEFS	1		;index into command line buffer
BufCnt	DEFS	1		;number char left in buffer
ScnChr	DEFS	1		;command line chr being compared
TmpDig	DEFS	1		;save digit in scan
COUNT	DEFS	2		;Entry count
counts	DEFS	2		;save as COUNT is modified
FREEBY	DEFS	2		;Contains number of K left on directory	drive
GAP	DEFS	2		;Sort routine storage
I	DEFS	2		;Sort routine storage
J	DEFS	2		;Sort routine storage
JPnt	DEFS	2		;pointer in COMPARE
JG	DEFS	2		;Sort routine storage
JGPnt	DEFS	2		;pointer in COMPARE
LZFLG	DEFS	1		;0 when printing leading zeros
MAXUSR	DEFS	1		;Maximum user # for drive
NEXTT	DEFS	2		;Next table entry
;copy of DCB for selected drive
DCBCPY
MAXBLK	DEFS	2
NRECRD	DEFS	2
NSYSTR	DEFS	2
BLKSCD	DEFS	1
MAXDIR	DEFS	2
ALCMAP	DEFS	2
CHKFLG	DEFS	1
CHKMAP	DEFS	2
;more variables
numblk	DEFS	2		;number of blocks
BlkCnt	DEFS	2		;counter for allocated blocks
AlcPnt	DEFS	2		;pointer used to scan map
BytTmp	DEFS	1		;temp in map scan
nmepnt	DEFS	2		;pointer in setting up ORDER
fldcnt	DEFS	1		;count of fields per line
MsgSav	DEFS	2		;save message pointer
Extent	DEFS	2		;extent number of last directory entry
	        		;and working location for file size
minus	DEFS	2		;save for modulus
remain	DEFS	1		;remainder in K calculation
curext	DEFS	1		;current extent
srchfr	DEFS	1		;first search in extent = 1, else 0
indx	DEFS	2		;index pointer in MSgZer
	ENDS
;
	code
;********************************
;				*
; BEGIN	EXECUTABLE PROGRAM CODE	*
;				*
;********************************

	ORG	TEA
START	lda	#<opnmsg	;point to message
	ldy	#>opnmsg
	jsr	msgout		;send it

	if	v3
	lda	#15
	sta	maxusr
	LDA	#255		;Get current user number if DOS/65 V3
	ldx	#36
	jsr	pem
	else
	lda	#0
	sta	maxusr
	endif

	sta	OLDUSR		;Initialize start up user number
	sta	NEWUSR		;..and make new user match it
	ldx	#CURDSK
	jsr	pem		;Get current disk nr
	sta	OLDDSK		;Save for reset if needed
;IF AT LEAST ONE OPTION IS ALLOWED, SCAN THE COMMAND LINE FOR THE
;OPTION FIELD DELIMITER. THE OPTION FIELD DELIMITER IS CONSIDERED
;VALID ONLY IF IT IS PRECEDED BY AT LEAST 1 SPACE (OTHERWISE, IT
;MAY BE PART OF THE DIRECTORY FILENAME). ANY UNRECOGNIZED OPTIONS
;OR ILLEGAL USER NUMBERS WILL BE FLAGGED OR IGNORED (SEE REPERR).
;WE SCAN THE COMMAND LINE BUFFER RATHER THAN THE 2ND DEFAULT FCB
;BECAUSE ALL OPTIONS PLUS A 2 DIGIT USER NUMBER WON't fit in
;THE FCB NAME FIELD).

	IF	OPTION
	ldx	DflBuf		;get length of command line
	ldy	#0		;Set command line buffer index
;
;SEARCH FOR THE COMMAND LINE DELIMITER. IF NOT FOUND, ASSUME NO OPTIONS.
SCNDOL	iny			;advance index
	dex			;drop count
	bpl	pl001		;continue if positive
	jmp	ckrest		;exit if command line buffer empty
pl001	lda	DflBuf,y	;get character
	cmp	#'='
	bne	SCNDOL		;loop if not found
	dey			;'=' found - make sure space precedes it
	lda	DflBuf,y
	iny
	cmp	#' '
	bne	SCNDOL		;No space - ignore "=" and search again
;VALID DELIMITER FOUND. SCAN THE REST OF THE BUFFER FOR OPTIONS. ERRORS
;PAST THIS POINT WILL CAUSE AN ABORT IF THE COMMAND LINE ERROR OPTION IS
;ENABLED. OTHERWISE, THE DUD OPTION WILL BE IGNORED AND SD WILL ATTEMPT
;TO CONTINUE STUMBLING THROUGH THE REST OF THE FIELD.
scnopt	iny			;bump index into buffer
	sty	Bufind		;save index
	dex			;drop count
	stx	BufCnt		;save for later
	bpl	scnagn		;continue if more
	jmp	ckrest		;if exhausted quit
SCNAGN	lda	DflBuf,y	;Get the next option character
	sta	ScnChr		;save char
	cmp	#' '		;Do we have a space?
	beq	SCNOPT		;Ignore it if so
;scan option table by first setting x & y
	ldx	#OEnd-OTbl+1	;get length
	ldy	#255		;set index to -1
NoMach	iny			;bump index
	dex			;drop count
	beq	Ck4Usr		;if none check battery
	lda	Otbl,y		;get char
	cmp	ScnChr		;compare to command line char
	bne	NoMach		;loop if no match
	lda	#0		;else activate by erasing
	sta	OTbl,y		;option letter
	ldx	BufCnt		;restore count
	ldy	BufInd		;and index
	jmp	ScnOpt		;loop for next command line chr
;IF OPTION CHARACTER DOESN't match the table, see if we have a User
;OPTION.
CK4USR	ldy	BufInd		;get index
	ldx	BufCnt		;and count
	lda	dFLbUF,y	;and character

	IF	UOPT		;Check for user	number option
	cmp	#'U'		;see if U
	bne	CLERR		;Last option, so bad deal if that ain't it
UAGN	iny			;Bump to user number digit
	dex			;DROP COUNT
	BMI	CLERR		;Error if nothing left
	LDA	dFLbUF,Y	;Get decimal digit
	CMP	#' '		;Ignore leading spaces
	BEQ	UAGN
	SEC
	sbc	#'0'		;Subtract ASCII BIAS
;If result requires borrow then error
	bcc	CLERR		;Error if < 0
	cmp	#10
	bcs	CLERR		;Error if > 9
	sta	NEWUSR		;Save user number as it may be only 1 digit
	iny			;Bump to possible 2nd digit of user number
	dex
	bmi	CKREST		;If no more buffer, exit with complete user #
	lda	DflBuf,y	;Else, check for another digit
	sec
	sbc	#'0'
	bcc	SCNAGN		;If next char not numeric not part of
	cmp	#10		;user number so go check for another option
	bcs	SCNAGN
;At this point we have a two digit number but only legal first digit is 1. So
;check that it is 1
	sta	tmpdig		;save low digit
	LDA	newusr		;get it
	cmp	#1		;check it
	bne	clerr		;error if not 1
	clc			;now them all up
	lda	tmpdig		;get low back
	adc	#10		;add 10
;Note that user number could still be > 15 and illegal
	sta	NEWUSR		;Save the total user number
	JMP	SCNOPT		;Continue scanning
	ENDIF			;Balance UOPT

;IF COMMAND LINE ERROR OPTION ENABLED, PLAYBACK THE COMMAND LINE UP
;TO THE CHARACTER THAT WE GAGGED ON AND EXIT. IF REPERR IS NOT ENABLED,
;THEN CONTINUE AS IF NOTHING WERE AMISS TO AVOID ACKNOWLEDGING THAT
;SOME OPTIONS ARE AVAILABLE.
CLERR
	IF	REPERR
	lda	#0		;get ready to flag end
	iny
	sta	DflBuf,y	;do it
	jsr	CRLF
	lda	#<errms2
	ldy	#>errms2
	jsr	MsgOut
	lda	#<errtag
	ldy	#>errtag
	jsr	MsgOut
	ldy	#1		;Playback bad command line to error point
CLELP	lda	dflbuf,y
	beq	CLEX
	sty	BufInd		;save index
	jsr	TYPE
	ldy	BufInd		;get index back
	iny			;bump it
	jmp	CLELP
;identify error point
CLEX	lda	#'?'		;Tag line with a '?' field
	jsr	TYPE
	jsr	CRLF		;Space down 1 more line
	JMP	EXIT		;..and return to DOS/65
	ELSE

	JMP	SCNOPT		;If not reporting errors, ignore the dud
	ENDIF			;Balance REPERR
	ENDIF			;Balance OPTION

;OPTIONS INPUT complete OR none SPECIFIED.
CKREST
;
	lda	DflFCB+1	;point to name
	cmp	#' '		;see if blank
	bne	gotfcb		;if not use
;NO FCB - MAKE	FCB ALL	'?'
	ldx	#11		;FN+FT count
	lda	#'?'		;get ?
QLOOP	sta	DflFCB,x	;Store '?' IN FCB
	dex
	bne	qloop		;loop if more
GOTFCB
;Clear rest of FCB
	lda	#0		;get zero
	ldy	#12
clrfcb	sta	DflFCB,y	;write 0
	iny
	cpy	#33		;see if past end
	bne	clrfcb
	jsr	SETSRC		;Set DMA for PEM media change check
	lda	DflFCB		;get drive code from FCB
	bne	notdfl		;if non-zero not default
	lda	olddsk		;get old
	jmp	setdfl		;set default
notdfl	sec			;Normalize drive code for SELECT
	sbc	#1
	and	#%00000111	;look at three bits only
setdfl	sta	curdrv		;save for later
	ldx	#SELDSK		;Select the directory drive to retrieve
	jsr	PEM		;..the proper allocation vector
	lda	#0		;clear auto
	sta	DflFCB
;DOS/65 disk definition structure is not the same as CP/Ms.
usedfl	ldx	#CurDCB		;request DCB
	jsr	pem
	sta	hl		;save in pointer
	sty	hl+1
;HL points to DCB - make a local copy of the 14 bytes
	ldy	#0
DCBLPE	lda	(hl),y		;get actual
	sta	DCBCPY,y	;save copy
	iny			;bump index
	cpy	#14
	bne	DCBLPE		;loop 14 times
;
;CALCULATE # OF K FREE ON SELECTED DRIVE NOW
FREE	ldy	#0		;clear
	sty	BlkCnt		;block counter
	sty	BlkCnt+1	;low and high
;Get address of allocation vector
	lda	AlcMap		;low then high
	ldy	AlcMap+1
	sta	AlcPnt		;set pointer
	sty	AlcPnt+1
;calculate length of allocation map
	lda	maxblk
	ldy	maxblk+1
	sta	NumBlk		;save max
	sty	NumBlk+1
	inc	NumBlk		;bump by one
	bne	gspbyt		;skip if not roll over
	inc	NumBlk+1
GSPBYT	ldy	#0
	lda	(AlcPnt),y	;get byte
	sta	BytTmp		;save it
	ldx	#8		;Set to process 8 blocks
GSPLUP	asl	BytTmp		;Test bit
	bcs	NOTFRE		;block used if c=1
	INC	BlkCnt		;else bump count
	bne	notfre		;skip if no roll over
	inc	BlkCnt+1	;else bump high
NOTFRE	sec			;drop total left by one
	lda	NumBlk
	sbc	#1
	sta	NumBlk
	lda	NumBlk+1	;get high
	sbc	#0
	sta	NumBlk+1
	ora	NumBlk		;see if now zero
	beq	endalc		;done if zero
	dex			;Count down 8 bits
	bne	GSPLUP		;Do another bit
	inc	AlcPnt		;go to next byte
	bne	nz001		;skip if no roll over
	inc	AlcPnt+1
nz001	jmp	GSPBYT		;Process it
;have now scanned the entire map
ENDALC	lda	BlkCnt		;get free block count
	ldy	BlkCnt+1
	sta	freeby		;and save
	sty	freeby+1
	ldx	BlkSCd		;get block size code from DCB copy
	beq	savfre		;done if 1K
	sta	BytTmp		;set up temp
FREKLP	asl	freeby		;shift low
	rol	freeby+1
	dex			;drop multiplier
	bne	freklp		;loop if more
;Free space has been calculated - now set up search of directory. One
;awkward aspect of that results from fact that DOS/65 does not do
;wild card searches on the EXTENT. What code does is first search for
;EXTENT=0 , then do EXTENT=1, etc. For EXTENT>0 use the first search
;results to terminate searches beyond that point.
SAVFRE
;
;REENTER HERE ON SUBSEQUENT PASSES WHILE IN THE ALL-USERS MODE
SETTBL
	lda	#<name		;of name
	sta	nextt		;and init next table entry pointer
	lda	#>name
	sta	nextt+1
;pointer calculated and saved now

	IF	UOPT
	lda	NEWUSR		;Get user area for directory
	ldx	#CURUSR		;Get the user function

	if	v3
	jsr	pem		;..and set new user number if V3
	endif

	ENDIF

;
;LOOK UP THE FCB IN THE DIRECTORY
SFIRST	lda	#0		;initialize counters
	tay
	sta	COUNT		;Initialize match counter
	sty	count+1
	sta	TOTFIL		;initialize total file counter
	sty	totfil+1
	sta	TOTSIZ		;initialize total size counter
	sty	totsiz+1
	jsr	SETSRC		;Set DMA for directory search
;set FCB for actual search
	lda	#0		;reset current EXTENT to 0
	sta	curext
newext	lda	curext		;get current EXTENT
	sta	DflFCB+12
;set flag so we will know this is first search for this extent
	lda	#1
	sta	srchfr
	ldx	#SEARCH		;Get 'search first' function
	JMP	LOOK		;..and go search for 1st match
;
;READ MORE DIRECTORY ENTRIES
MORDIR	lda	#0		;clear search first
	sta	srchfr
	ldx	#NEXT		;Search next but first
LOOK	lda	#<DflFCB
	LDY	#>DflFCB
	jsr	PEM		;Read directory entry
	cmp	#255		;check for not found
;Check for "not found" (0FFH)
	bne	some		;if not use
;search found nothing so see if it was a first
	lda	srchfr		;read flag
	beq	ntfirs		;not a first so bump EXTENT
;was a first search so done
	bne	sprint		;go sort and print
;was not a first search try new EXTENT
ntfirs	inc	curext		;else bump current
	jmp	newext		;and loop
;
;POINT TO DIRECTORY ENTRY
SOME
	AND	#3		;Make modulus 4
	asl	a		;multiply by 32
	asl	a
	asl	a
	asl	a
	asl	a
;at this point a=0,32,64, or 96
	tax			;make an index
	lda	DflBuf,x	;get user number
	cmp	NEWUSR		;compare to current user
	bne	MORDIR		;Ignore if different
	inx			;go to name field
	ldy	#0		;clear destination index
;MOVE ENTRY TO TABLE
TMOVE	LDA	DflBuf,x	;Get entry char
	AND	#$7F		;Remove attributes
	sta	(nextt),y	;Store in table
	iny			;bump destination index
	inx			;and source
	cpy	#12		;see if destination at 12
	bne	tmove
;at this point y is pointing to the correct destination for
;record count but x is two short so bump x
	inx
	inx
	lda	dflbuf,x	;get record count
	sta	(nextt),y	;and save
;now adjust table pointer to get ready for next match
	clc			;add 16 to address
	lda	nextt		;get low
	adc	#16		;add 16
	sta	nextt		;save low
	bcc	CC002		;if no carry skip high bump
	inc	nextt+1
CC002	inc	count		;bump match counter
	bne	nz004
	inc	count+1
NZ004	JMP	MORDIR		;loop for more
;
;SORT AND PRINT
SPRINT
;

	IF	AOPT OR UOPT
	jsr	SETFOP		;set file & user #
	ENDIF

	lda	COUNT		;Get file name count
	ora	count+1		;any found
	bne	nz005		;yes so keep going
	JMP	PRTOTL		;Exit if no files found
NZ005
	lda	#0		;set A to 0
	sta	SUPSPC		;Enable leading space suppression
	lda	count		;save count as sort count
	ldy	count+1
	sta	scount
	sty	scount+1
;test for only one entry
	cpy	#0		;if high not zero can
	bne	sort		;not be one
	cmp	#1		;test low
	bne	sort		;if not one do sort
	jmp	done		;else done
;
;THIS SORT ROUTINE IS ADAPTED FROM SOFTWARE TOOLS
;BY KERNIGAN AND PLAUGHER. As written it works with an array
;of items numbered from 1 to N (SCOUNT). That is why COMPARE
;and SWAP do a -1 record offset in the start to handle actual
;data addresses of 0 to N-1. The items in this
;case is the table of file names, types, extents, and records.
;While V1.00 only deals with 13 of the 16 bytes in each table record
;that was done because expanding the sort table indices to handle
;16 byte records is a lot easier than handing 13 byte records.
;The extra three bytes are ignored fir now.
SORT	lda	scount		;get number of entries
	ldy	scount+1
	sta	hl		;and put in HL
	sty	hl+1
L0	lsr	hl+1		;gap=gap/2
	ror	hl
	lda	hl		;see if zero
	ora	hl+1
	beq	done		;if so none left
	lda	hl		;make gap odd
	ora	#1
	sta	hl
	sta	gap		;save gap
	lda	hl+1
	sta	gap+1
	inc	hl		;I=GAP+1
	bne	nz020		;skip if no wrap
	inc	hl+1
nz020

L2	lda	hl
	ldy	hl+1
	sta	I		;actually use I
	sty	I+1
	sec			;J=I-GAP
	lda	I
	sbc	gap
	sta	J
	lda	I+1
	sbc	gap+1
	sta	J+1
L3	clc			;JG=J+GAP
	lda	J
	adc	GAP
	sta	JG
	lda	J+1
	adc	GAP+1
	sta	JG+1
;Do the comparison between the two entries in NAME - only compare
;12 bytes. COMPARE returns with CS result if A(J)>A(JG)
;in which case swap is needed. But if A(J)<=A(JG) as CC shows do not swap.
	lda	#12		;compare 12 characters
	jsr	compare		;compare A(J) and A(JG)
	bcc	L5		;do nothing if C clear
	jsr	SWAP		;Exchange A(J) and A(JG)
	sec			;J=J-GAP
	lda	J
	sbc	gap
	sta	J
	lda	J+1
	sbc	gap+1
	sta	J+1
	bmi	L5		;if J<0
	ora	J		;check for zero
	beq	L5		;if J=0
	jmp	L3		;if J>0
L5	inc	I		;I=I+1
	bne	NZ021
	inc	I+1
NZ021
;If I<=N goto L2
	sec			;do as subtract N-I
	lda	scount
	sbc	I
	lda	scount+1
	sbc	I+1
	bcs	CS002		;I<=N
	lda	gap
	ldy	gap+1		;preload gap into hl
	sta	hl
	sty	hl+1
	jmp	L0
CS002	lda	I
	ldy	I+1
	sta	hl		;preload I into HL
	sty	hl+1
	jmp	L2
;SORT IS ALL DONE - PRINT ENTRIES
DONE

NOOUT
	lda	#<name		;initialize table pointer
	ldy	#>name
	sta	nmepnt		;by saving
	sty	nmepnt+1
	JMP	NEWLIN		;Start new line	and output the files

;OUTPUT THE DIRECTORY FILES WE've matched.
ENTRY	sec			;drop file count
	lda	count
	sbc	#1
	sta	count		;and save
	lda	count+1
	sbc	#0
	sta	count+1
	ora	count		;see if last file
	beq	OKPRNT		;If COUNT=0, last file so skip compare
;COMPARE EACH ENTRY TO MAKE SURE THAT IT ISN't part of a multiple
;EXTENT FILE. GO ONLY WHEN WE HAVE THE LAST EXTENT OF THE FILE.
	jsr	CKABRT		;Check for abort code from keyboard
	jsr	COMPR		;Does this entry match next one?
	bne	OKPRNT		;No, print it
	clc			;bump pointer by 16
	lda	nmepnt
	adc	#16
	sta	nmepnt
	bcc	cc004
	inc	nmepnt+1
cc004	JMP	ENTRY		;Loop back for next lowest extent
;VALID ENTRY OBTAINED - SPIT IT OUT.
OKPRNT
;First do name
	ldy	#0		;start at first byte
CNAME	lda	(nmepnt),y	;get name char
	sta	namcpy,y	;save it
	iny
	cpy	#8		;see if past end
	bne	cname		;loop if more
;now do type
	ldx	#0		;use second index for copy
ctype	lda	(nmepnt),y	;get char
	sta	typcpy,x	;save it
	inx
	iny
	cpy	#11		;see if past end
	bne	ctype		;loop if more
;now print
	lda	#<namcpy	;point to name
	ldy	#>namcpy
	jsr	msgzer		;print it
	LDA	#'.'		;Period	after FN
	jsr	TYPE
	lda	#<typcpy	;point to type
	ldy	#>typcpy
	jsr	msgzer		;print it
;COMPUTE THE SIZE OF THE FILE AND UPDATE OUR SUMMARY DATUM.
	ldy	#11		;get extent
	lda	(nmepnt),y
	sta	extent
	lda	#0		;set high to 0
	sta	extent+1
	iny			;point to record count of last extent
	lda	(nmepnt),y	;get it
;now convert whole extents to KB
	ldx	#4		;multiply by 16
extmul	asl	extent
	rol	extent+1
	dex
	bne	extmul		;loop if more
;now convert record count to KB
	stx	remain		;clear remainder
	lsr	a		;divide by 2
	ror	remain		;set remainder if any
	lsr	a
	ror	remain
	lsr	a
	ror	remain
	and	#%00011111
	clc			;add to existing
	adc	extent
	sta	extent
	bcc	cc005
	inc	extent+1
cc005	lda	remain		;test remainder
	beq	norem		;if none ignore
	inc	extent		;else bump by 1K
	bne	norem
	inc	extent+1
norem
;now round up to whole blocks
	ldx	blkscd		;get DCB parameter
	lda	kblkm,x		;get K/BLK mask
	AND	extent		;use as rounding
	beq	noblk		;if result 0 size is correct
	lda	kblkm,x		;get mask again
	eor	#%11111111	;complement
	and	extent		;clear partial
	sta	extent
	clc			;add block size to total
	lda	kblk,x
	adc	extent
	sta	extent		;save
	bcc	noblk
	inc	extent+1
;now add this file size to total
noblk	clc
	lda	totsiz
	adc	extent
	sta	totsiz
	lda	totsiz+1
	adc	extent+1
	sta	totsiz+1
;now bump file count
	inc	totfil
	bne	nz010
	inc	totfil+1
nz010
;IF REPORT SIZE ENABLED, OUTPUT THE SIZE OF THE INDIVIDUAL FILE.

	IF	REPSIZ		;If file size report wanted
	lda	#1		;do not suppress spaces
	sta	supspc
	lda	extent		;get file size
	ldy	extent+1
	sta	hl		;pass in HL
	sty	hl+1
	jsr	DECPRT		;..go print it
	LDA	#'K'		;..and follow with K size
	jsr	TYPE
	ENDIF

;ONE FILE OUTPUT - TEST TO SEE IF WE HAVE TO OUTPUT ANOTHER ONE.
;but first point to next entry in NAME
	clc
	lda	nmepnt
	adc	#16
	sta	nmepnt
	bcc	cc050
	inc	nmepnt+1
cc050	lda	count		;test count
	ora	count+1
	bne	nz011
	jmp	prtotl		;if no more do summary
;AT LEAST ONE MORE FILE TO OUTPUT - CAN WE PUT IT ON THE CURRENT LINE?
nz011	dec	fldcnt		;drop counter
	beq	newlin		;if zero new line
	jsr	FENCE		;If room left, output the fence character
	JMP	ENTRY		;.. and go output another file
;CURRENT LINE FULL, START A NEW ONE.
NEWLIN	lda	#NPL		;Reset names per line counter
	sta	fldcnt		;set counter
	jsr	CRLF		;Space down to next line

	IF	NPL<4		;If printing less than 4 wide ..
	clc
	LDA	curdrv		;.. precede new line with drive name
	ADC	#'A'
	jsr	TYPE

	IF	REPUSR and v3	;If reporting user numbers and running under
				;V3, output the user number too
	jsr	TYPUSR
	ENDIF			;Balance REPUSR and v3

	lda	#':'		;Tag header with a colon and a space
	jsr	FPAD		;..and exit back to ENTRY

	ENDIF			;Balance NPL GT	3

	jmp	ENTRY		;Go back and output another file
;
;PRINT HL IN DECIMAL WITH LEADING ZERO SUPPRESSION
DECPRT	lda	#0		;Clear leading zero flag
	sta	LZFLG
	lda	#<1000
	ldy	#>1000		;do 1000's first
	jsr	DIGIT
	lda	#<100
	ldy	#>100
	jsr	DIGIT
	lda	#<10
	ldy	#>10
	jsr	DIGIT
	clc
	LDA	#'0'		;Get 1's digit
	ADC	hl
	JMP	TYPE
;do decimal digit
DIGIT	LDX	#'0'		;Start off with ASCII 0
	sta	minus		;save modulus
	sty	minus+1
DIGLP	sec			;subtract
	lda	hl		;modulus from hl
	sbc	minus
	sta	hl		;and save
	lda	hl+1
	sbc	minus+1
	sta	hl+1
	bcc	digex		;done if borrow
	INX			;Bump digit
	JMP	DIGLP		;Loop back
;at this point HL reflects the last borrow so add modulus back
DIGEX	clc			;add modulus back
	lda	hl
	adc	minus
	sta	hl
	lda	hl+1
	adc	minus+1
	sta	hl+1
	txa			;move digit to A
	cmp	#'0'		;see if zero
	bne	dignz		;go send it
;we know digit is a 0 - check if leading 0 or not
	LDA	LZFLG		;Leading zero?
	beq	notyp0		;if clear do not type
	LDA	#'0'		;else do type
	JMP	TYPE		;Print digit
notyp0	LDA	SUPSPC		;Get space suppression flag
	beq	nospac		;if clear no space
	JMP	SPACE		;Leading zero...print space
nospac	rts
;print non-zero digit
DIGNZ	sta	LZFLG		;Set leading flag so next zero prints
	JMP	TYPE		;And print digit
;
;SHOW TOTAL SPACE AND FILES USED
PRTOTL	lda	#0		;suppress leading spaces
	sta	supspc
	lda	totfil		;check total file count
	ora	totfil+1
	beq	nxtusr		;skip if nothing found
	sta	fndflg		;set file found flag
	lda	#<totms1	;Print [CR,LF,LF]"DRIVE "
	ldy	#>totms1
	jsr	MsgOut
	clc
	LDA	curdrv
	ADC	#'A'
	jsr	TYPE		;Output	the drive code

	IF	REPUSR and v3
	lda	#<TOTMS2	;Print ", USER "
	ldy	#>totms2
	jsr	MsgOut
	jsr	TYPUSR		;Output	the user number
	ENDIF

NOUSER	lda	#<totms3	;print "CONTAINS "
	ldy	#>totms3
	jsr	msgout
	lda	totsiz		;print total K used by files
	ldy	totsiz+1
	sta	hl
	sty	hl+1
	jsr	decprt
	lda	#<totms4	;print "K IN "
	ldy	#>totms4
	jsr	msgout
	lda	totfil		;print total files
	ldy	totfil+1
	sta	hl
	sty	hl+1
	jsr	DECPRT		;Print number of files matched
	lda	#<TOTMS5	;Print " FILES WITH "
	ldy	#>totms5
	jsr	MsgOut
	jsr	PRTFRE		;Output	free space remaining & " FREE."
;DIRECTORY FOR ONE USER AREA COMPLETED. IF ALL USERS OPTION IS
;SELECTED, THEN GO DO ANOTHER DIRECTORY ON THE NEXT USER NUMBER
;UNTIL WE EXCEED THE MAXIMUM USER # FOR THE SELECTED DRIVE.
NXTUSR
	IF	AOPT		;If all users option enabled
	lda	AOPFLG		;If not all users mode - skip next
	bne	goclz

	if	v3
	jsr	CKABRT		;Check for user abort first
	lda	MAXUSR		;No abort - get maximum	user number
	inc	newusr		;bump user
	cmp	newusr		;compare max to new
	bcc	cc003		;if borrow at end
	jmp	settbl		;else use
cc003
	endif			;balance v3

	ENDIF			;Balance AOPT

; WE've finished all of our outputting.

GOCLZ

;DIRECTORY FOR ALL USER AREAS COMPLETED.
NXTDSK	lda	fndflg		;get flag
	bne	ndsk		;exit if none
	lda	#0		;clear flag
	sta	fndflg
	clc
	LDA	curdrv		;Stash ASCII drive in NO FILE msg
	ADC	#'A'
	sta	NOFMS2
	lda	#<NOFMS1	;Print "NO FILE ON ? - "
	ldy	#>nofms1
	jsr	MsgOut
	jsr	PRTFRE		;Tag with free message
NDSK	JMP	EXIT		;All done - exit to CCP

;PRINT THE USER NUMBER OF THE DIRECTORY IN DECIMAL
TYPUSR
	IF	REPUSR
	LDA	NEWUSR
	CMP	#10		;If user no. > 9 print leading 1
	bcc	DUX
	LDA	#'1'
	jsr	TYPE
	sec
	LDA	NEWUSR		;Print low digit of user no.
	SBC	#10
DUX	clc
	ADC	#'0'
	JMP	TYPE
	ENDIF
;
;FORCE NEW LINE ON console
CRLF	LDA	#cr		;Send CR
	jsr	TYPE
	LDA	#lf		;Send LF
	JMP	TYPE		;Exit to caller from TYPE
;
;SEPARATE THE DIRECTORY OUTPUT ON A LINE WITH A SPACE, THE DELIMITER,
;FOLLOWED BY ANOTHER SPACE.
FENCE	jsr	SPACE
	LDA	#DELIM		;Fence character
FPAD	jsr	TYPE		;Print it, fall into space
SPACE	LDA	#' '		;Fall through to TYPE
;OUTPUT CHARACTER IN A TO CONSOLE - and save char as function
;of options selected
TYPE	pha			;Save the character to output
	jsr	TYPE1		;Send it to console
	pla			;Restore the output character
;TEST PAGE PAUSE TEST IF NOT ACTIVE.
	cmp	#lf		;see if lf
	bne	typret		;done if not

	IF	NOPT AND PGPAWZ
	LDA	NOPFLG		;Is the page pause function disabled?
	beq	TYPRET		;Exit if so
	ENDIF

	IF	PGPAWZ
	inc	LINCNT		;Get line count
	lda	lincnt
	cmp	#lps		;see if at end screen
	bne	NOTEOS		;Skip if not
	lda	#<eosmsg	;Else, display pause message
	ldy	#>eosmsg
	jsr	msgout
	jsr	CINPUT		;Wait for character
	CMP	#'C'-$40
	bne	nz013		;continue if not
	JMP	EXIT		;Abort on CTRL-C
nz013	lda	#0		;reset line count
	sta	lincnt
NOTEOS
	ENDIF

TYPRET	rts			;Exit from TYPE
;
;OUTPUT CHARACTER in A to console
TYPE1	ldx	#WRCHR
	jmp	pem		;Call CONOUT via pem
;
;Print $-terminated message on console
;Message start in AY
MsgOut	ldx	#string
	jmp	pem
;
;Print 0 terminated message on console - start in AY
;at entry.
MsgZer	sta	indx		;save address
	sty	indx+1
MsgZLp	ldy	#0		;clear index
	lda	(indx),y	;get character
	beq	MsgZX		;done if zero
	jsr	type		;else send to console
	inc	indx		;bump address
	bne	MsgZLp		;loop
	inc	indx+1
	jmp	MsgZLp		;loop
MsgZX	rts
;FETCH CHARACTER FROM CONSOLE (WITHOUT ECHO)
CINPUT	ldx	#noecho		;read input w/o echo
	jmp	pem
;
;CHECK FOR A CTRL-C ENTERED FROM THE KEYBOARD. JUMP TO
;EXIT IF CTRL-C. System already checks for and handles ctl-s
;and ctl-q for pause and resume.
CKABRT	ldx	#const		;check console input
	jsr	pem
	beq	eq030		;done if nothing there
	ldx	#noecho		;something there - get
	jsr	pem		;without echo
	cmp	#'C'-$40	;see if ctl-c
	bne	eq030		;if not ignore
	jmp	exit		;else exit
eq030	rts
;
;RETURN TO OLD USER AREA
SETFOP
	IF	UOPT OR AOPT
	lda	OLDUSR		;Get user number at start up
	LDX	#CURUSR

	if	v3
	jsr	pem		;Reset the old user number if V3
	endif

	ENDIF

	rts
;
;MOVE DISK BUFFER DMA TO DEFAULT BUFFER FOR DIRECTORY SEARCH OPERATIONS
;AND BDOS MEDIA CHANGE ROUTINES.
SETSRC	lda	#<DflBuf	;point to default
	ldy	#>DflBuf
	ldx	#SETDMA
	jmp	pem
;
;PRINT THE AMOUNT OF FREE SPACE REMAINING ON THE SELECTED DRIVE
PRTFRE	lda	FreeBy		;get space
	ldy	FreeBy+1
	sta	hl
	sty	hl+1
	jsr	DECPRT		;Print K free
	lda	#<totms6	;point to message
	ldy	#>totms6	;Print " FREE."
	JMP	MsgOut
;
;ROUTINE used to compact tables. This
;routine assumes SORT puts the extents for a given
;file in order such that the last extent will be
;the last entry matching the name and type fields.
;NEXTT is the pointer to the NAME entry.
;At exit EQ (z=1) will be set if a match - NE (z=0)
;will be set if not a match.
compr	lda	nmepnt		;copy pointer
	ldy	nmepnt+1
	sta	nextt		;set second pointer
	sty	nextt+1
;now increase nextt to point to next entry
	clc
	lda	nextt		;bump by 2
	adc	#16
	sta	nextt
	bcc	cc006
	inc	nextt+1
cc006	ldy	#0		;set index too start
	ldx	#11		;compare 11
comprlp	lda	(nmepnt),y	;get first
	cmp	(nextt),y	;do compare
	bne	nz009		;exit if mismatch
	iny
	dex			;drop count
	bne	comprlp		;loop if more
nz009	rts
;
;SWAP ENTRIES IN THE NAME TABLE. Note that COMPARE calculates
;and saves the pointers JPNT and JGPNT and nothing changes them
;between COMPARE and call to SWAP.
SWAP	ldx	#13		;only 13 valid bytes
	ldy	#0
swaplp	lda	(jpnt),y	;get low of j
	sta	byttmp		;save
	lda	(jgpnt),y	;get low of JG
	sta	(jpnt),y	;swap into j
	lda	byttmp		;now swap into jg
	sta	(jgpnt),y
	iny
	dex
	bne	swaplp		;loop if more
	rts
;
;This is the compare routine for the Shell sort.
;Compare A(J) with A(JG) and return with CS if
;A(J) > A(JG) and hence swap required. If CC
;then A(J) <= A(JG) and no swap required.
COMPARE
;First  translate simple counts in J and JG to pointers
;to the NAME table.
;Do JPnt first
	lda	j
	ldy	j+1
	sta	jpnt		;copy to pointer
	sty	jpnt+1		;now do 16x
	ldx	#4
jx16	asl	jpnt
	rol	jpnt+1
	dex
	bne	jx16
;name-16 is used to change start from 1 to 0
	clc			;now add table start
	lda	jpnt
	adc	#(name-16)*256/256	;use actual start
	sta	jpnt
	lda	jpnt+1
	adc	#(name-16)/256
	sta	jpnt+1
;now do jgpnt
	lda	jg
	ldy	jg+1
	sta	jgpnt		;copy to pointer
	sty	jgpnt+1		;now do 16x
	ldx	#4
jgx16	asl	jgpnt
	rol	jgpnt+1
	dex
	bne	jgx16
	clc			;now add table start
	lda	jgpnt
	adc	#(name-16)*256/256	;use actual start
	sta	jgpnt
	lda	jgpnt+1
	adc	#(name-16)/256
	sta	jgpnt+1
;At this point jpnt and jgpnt point to the start of an entry in NAME
	ldx	#12		;compare first 12
	ldy	#0		;get index ready
cmplpe	lda	(jpnt),y	;get a(J)
	cmp	(jgpnt),y	;compare a(jg)
	bne	nz030		;done if not same
	iny			;next byte
	dex			;drop counter
	bne	cmplpe
;At this point all bytes tested and are equal so
;clear carry and return.
	clc
	rts
;at this point we know there is a difference so they
;can not be equal. That means that a(j) must be greater
;if C set (no borrow) or smaller if C clear (borrow). If A(j) is
;smaller then no swap is required so just return. In the
;same path if C is set (no borrow) then swap is required
;so just return.
nz030	rts			;exit
;
;ERROR EXIT
ERXIT	sta	msgsav		;save message address
	sty	msgsav+1
	jsr	CRLF		;Space down
	lda	msgsav		;get message pointer
	ldy	msgsav+1
	jsr	msgout		;Print it
	lda	#<errms1	;print ERROR
	ldy	#>errms1
	jsr	msgout
	jsr	CRLF		;Space down fall into exit
;
;EXIT - ALL DONE
EXIT	ldx	#CONST		;Check console status
	jsr	pem
	beq	L001		;Char waiting?
	ldx	#RDCHR
	jsr	pem		;Gobble	up char
L001	rts
;
;**********************
;		      *
; END OF PROGRAM CODE *
;		      *
;**********************

; INITIALIZED DATA AREA
;messages
opnmsg	defb	'DOS/65 SUPER DIRECTORY V1.03$'

	IF	PGPAWZ
EOSMSG	DEFB	lf,'[ More ]',cr,lf,lf,'$'
	ENDIF

ERRMS1	DEFB	' '
ERRMS2	DEFB	'ERROR$'

	IF	REPERR
ERRTAG	DEFB	' ->$'
	ENDIF

NOFMS1	DEFB	cr,lf,'NO FILE ON '
NOFMS2	DEFB	'  - $'

TOTMS1	DEFB	cr,lf,cr,lf,'DRIVE $'

	IF	REPUSR
TOTMS2	DEFB	', USER $'
	ENDIF

TOTMS3	DEFB	' CONTAINS $'
TOTMS4	DEFB	'K IN $'
TOTMS5	DEFB	' FILES WITH $'
TOTMS6	DEFB	'K FREE',cr,lf,'$'
USRMSG	DEFB	'USER #$'

FNDFLG	DEFB	0		;Flag whether any files matched

	IF	PGPAWZ
LINCNT	DEFB	0		;Count of lines printed	on screen
	ENDIF
;
;OPTION FIELD LOOKUP TABLE.
;NOTE THAT YOU CAN FORCE ANY OF THESE OPTIONS AS A DEFAULT BY
;CHANGING THE LETTER FOR THE OPTION INTO A ZERO (ASSUMING THAT
;ITS ENABLING EQUATE IS TRUE). EACH OPTION THAT YOU HARD-WIRE IN
;THIS MANNER WILL NO LONGER BE RECOGNIZED AS A COMMAND LINE OPTION,
;AND IF YOU REDUNDANTLY KEY IT IN, SD WILL FLAG IT AS UNRECOGNIZED.
OTBL	EQU	*		;Mark start of option table

	IF	AOPT		;All users-option flag
AOPFLG	DEFB	'A'
	ENDIF

	IF	NOPT AND PGPAWZ	;No page-pause option flag
NOPFLG	DEFB	'N'
	ENDIF

OEND	EQU	*		;Mark end of option table

;END OF OPTION LOOKUP TABLE
;Locations to store printing copy of name and type fields
namcpy	defb	'        ',0
typcpy	defb	'   ',0
;table of mask for KB per block - use BLKSCD to index
kblkm	defb	0,1,3,7,15
;table of K to add for partial block
kblk	defb	0,2,4,8,16
;
;UNINITIALIZED DATA AREA
;This area consists of one table - NAME. When SORT is
;executed, the entire value used for the comparison is the first 12 bytes
;entry in NAME containing:
;	name - 8 bytes
;	type - 3 bytes
;	extent - 1 byte
;	records - 1 byte
;	dummy - 3 bytes
;as extracted from each 32 byte directory entry.
;NAME
;	NAME	fixed start of table
;	nmepnt	word pointer used during table set up
;	NEXTT	word pointer to next table entry
;	COUNT	word showing number of actual table entries
;	COUNTS	word holding saved value of COUNT
;	SCOUNT	word showing number entries to sort
;
NAME	EQU	*		;name table starts here
	ends
	end
