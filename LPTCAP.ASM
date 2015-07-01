; LPTCAP.ASM -- DOS parallel printer data capture - k@heidenstrom.gen.nz
;
;		     (c) Copyright 1996-2000 K. Heidenstrom
;
;      May be freely used provided that copyright information is retained
;
; KH.19960731.001  Started
; KH.19960801.002  More work
; KH.19960803.003  More work
; KH.19960804.004  More work on lptcap_port()
; KH.19960805.005  Started work on lptcap_test()
; KH.19960806.006  More work on lptcap_test()
; KH.19960825.007  Updated for hardware with HC132
; KH.19961006.008  Added better diagnostics for lptcap_test()
;		   Added lptcap_test_fail_data()
; KH.19961009.009  Added check for zero PortNum in lptcap_test()
;		   Added 1-to-2-tick delay in first lptcap_test() call per port
; KH.19971004.010  Working lptcap_autodetect_irq()
; KH.19971010.011  Moved function documentation out to LPTCAP.TXT
; KH.19971012.012  Work on interrupt-driven receive
; KH.19971013.013  More work
; KH.19971015.014  More work
; KH.19971016.015  Found 'long strobe' problem causing bogus data captures
; KH.19971017.016  Started structural design changes
; KH.19971018.017  Working system - version 1.0.0
; KH.19971220.018  Release version - release 1.
; KH.20000402.019  Email address kheidens@clear.net.nz -> k@heidenstrom.gen.nz

FileRevision	EQU	019
VersionNum	EQU	1
SubVersion	EQU	0
ModVersion	EQU	0
VerDate		EQU	20000402
VerDateStr	EQU	"20000402"

; LEGAL
; -----
;
; This code and the LPTCAP hardware design are Copyright (c) 1996-2000 by Kris
; Heidenstrom, k@heidenstrom.gen.nz.  See the accompanying files LPTCAP.TXT
; or LPTCAP.HTM for further information.
;
; INTRODUCTION
; ------------
;
; This file is the LPTCAP interface module.  It provides a set of services
; which interface with an LPTCAP capture adapter, a circuit which allows a PC
; to capture data from another PC or any device that prints to a Centronics
; parallel printer.
;
; This file can be assembled with Borland's TASM (version 3.1 tested) or
; Microsoft's MASM (version 5.00 tested).  It uses 8086/8088 instructions only,
; and will run on any member of the PC family.	It supports all common memory
; models.  It assembles into an object module which can be linked into an
; MS-DOS real-mode program written in C or assembly language.
;
; Sample assembler command line:  tasm /ml /w2 /dMODEL_SMALL lptcap;
;
; These functions should not be called from interrupt handlers, as some of
; them make MS-DOS function requests.  This modules provides functions to
; implement interrupt-driven (background) print capturing, if required.
;
; Refer to the accompanying files LPTCAP.TXT or LPTCAP.HTM for general
; information about the LPTCAP system.
;
; FUNCTIONS IN THIS MODULE
; ------------------------
;
; The following functions are provided in this module:
;
; lptcap_version()
; lptcap_port()
; lptcap_test()
; lptcap_test_fail_data()
; lptcap_adjust()
; lptcap_get_cont()
; lptcap_set_stat()
; lptcap_send_ack()
; lptcap_poll_new()
; lptcap_next_char()
; lptcap_wait_char()
; lptcap_autodetect_irq()
; lptcap_intmode_install()
; lptcap_intmode_uninstall()
;
; IMPORTANT NOTE:  lptcap_port() and lptcap_test() set up global variables
;		   which are used by other functions, and must be called and
;		   return a successful result before other functions are used.
;
; Refer to the accompanying files LPTCAP.TXT or LPTCAP.HTM for detailed
; descriptions of these functions.
;
; SLOW AND VERY-SLOW OPTIONS
; --------------------------
;
; Two assembly-time options are available to force the hardware accessing code
; to run slowly - the SLOW and VERYSLOW options.
;
; The SLOW option may be needed if the machine running the LPTCAP software is
; very fast and/or is running with very few I/O wait states, if the parallel
; port outputs do not pull up strongly, or if the cable from the Capture PC
; to the LPTCAP adapter is long or has too much capacitance.  It will reduce
; data throughput.
;
; The VERYSLOW option may be used to slow down hardware accesses during
; development but should not be used with production code.  If the LPTCAP
; adapter works with VERYSLOW but not with SLOW, there is probably a hardware
; problem which should be investigated.
;
; These two options are specified on the command line to the assembler in the
; following forms:
;
;	/dSLOW			(slight slow-down),
;	/dVERYSLOW		(considerable slow-down).
;
; MEMORY MODEL SUPPORT
; --------------------
;
; Memory models are supported via an equate which can be defined on the command
; line when this module is assembled, using the /Dsymbol option (for example,
; /dCOMPACT).  Valid model names are TINY, SMALL, COMPACT, MEDIUM, LARGE and
; HUGE.  If none of the above equates are specified, SMALL model is used.
;
; The memory model affects whether calls are long or short, and whether data is
; near or far.	All data local to this module is placed in the code segment,
; for simplicity.  Memory models determine code and data size as follows:
;
; Model		Code	Data	Notes
; -----		----	----	-----
;
; TINY		Near	Near	Code and data are in same segment
; SMALL		Near	Near
; COMPACT	Near	Far
; MEDIUM	Far	Near
; LARGE		Far	Far
; HUGE		Far	Far	Data pointers are huge (normalised) pointers
;
; In this module, whether data is near or far is irrelevant except within the
; functions that use the interrupt-driven receive buffer, where this determines
; whether the pointer to the buffer descriptor structure, and the pointer
; within that structure to the start of the buffer area, are near or far.
; Whether code is near or far is relevant to the function definitions (the
; functions must end with a near or far return as appropriate) and this also
; has an effect on parameter indexing for functions which accept parameters,
; because the return address (which is 16 bits for near, 32 bits for far) is
; on the stack between the base pointer and the parameters.
;
; ==============================================================================

; Memory model setup

		IFDEF	MODEL_TINY
		 %OUT	--------  Using TINY memory model (single-segment)
CALLSIZE	 EQU	2
CODEFAR		 EQU	0
DATAFAR		 EQU	0
ModelKnown	 EQU	1
		ENDIF

		IFDEF	MODEL_SMALL
		 %OUT	--------  Using SMALL memory model (near code, near data)
CALLSIZE	 EQU	2
CODEFAR		 EQU	0
DATAFAR		 EQU	0
ModelKnown	 EQU	1
		ENDIF

		IFDEF	MODEL_MEDIUM
		 %OUT	--------  Using MEDIUM memory model (far code, near data)
CALLSIZE	 EQU	4
CODEFAR		 EQU	1
DATAFAR		 EQU	0
ModelKnown	 EQU	1
		ENDIF

		IFDEF	MODEL_COMPACT
		 %OUT	--------  Using COMPACT memory model (near code, far data)
CALLSIZE	 EQU	2
CODEFAR		 EQU	0
DATAFAR		 EQU	1
ModelKnown	 EQU	1
		ENDIF

		IFDEF	MODEL_LARGE
		 %OUT	--------  Using LARGE memory model (far code, far data)
CALLSIZE	 EQU	4
CODEFAR		 EQU	1
DATAFAR		 EQU	1
ModelKnown	 EQU	1
		ENDIF

		IFDEF	MODEL_HUGE
		 %OUT	--------  Using HUGE memory model (far code, far data)
CALLSIZE	 EQU	4
CODEFAR		 EQU	1
DATAFAR		 EQU	1
ModelKnown	 EQU	1
		ENDIF

		IFNDEF	ModelKnown
		 %OUT	-------- No memory model specified - assuming SMALL (near code, near data)
CALLSIZE	 EQU	2
CODEFAR		 EQU	0
DATAFAR		 EQU	0
		ENDIF

		IF	CODEFAR
LPTCAP_TEXT	 SEGMENT WORD PUBLIC 'CODE'
		 ASSUME	cs:LPTCAP_TEXT,ds:nothing,es:nothing,ss:nothing
		ELSE
_TEXT		 SEGMENT WORD PUBLIC 'CODE'
		 ASSUME	cs:_TEXT,ds:nothing,es:nothing,ss:nothing
		ENDIF

; Delay type (normal, SLOW, VERYSLOW)

		IFDEF	VERYSLOW
		 %OUT	--------  Generating VERYSLOW delays
DelayType	 EQU	2
		ELSE
		 IFDEF	SLOW
		  %OUT	--------  Generating SLOW delays
DelayType	  EQU	1
		 ELSE
DelayType	  EQU	0
		 ENDIF
		ENDIF

; @Delay macro
;
; In many I/O access sequences, short delays may be used to give attached
; hardware time to respond.  In normal speed mode, no explicit delays are
; generated, and the software relies on the delays inherent in the I/O
; accesses themselves to slow the software execution.  If the assembly-time
; parameter SLOW was defined, then delays are implemented with an OUT to
; I/O address 80h, the temporary BIOS diagnostic tracepoint register (which
; should be safe to write arbitrary data to on all machines).
; If the assembly-time parameter VERYSLOW was defined, the @Delay macro
; expands into a CALL to the InsertDelay function, which implements a longer
; delay using several I/O locations.

		IF	DelayType EQ 0
@Delay		 MACRO			; Normal - no delay
		 ENDM
		ENDIF

		IF	DelayType EQ 1
@Delay		 MACRO
		 out	80h,al		; SLOW - output to POST trace register
		 ENDM
		ENDIF

		IF	DelayType EQ 2
@Delay		 MACRO
		 call	InsertDelay	; VERYSLOW - call InsertDelay function
		 ENDM
		ENDIF

; Equates

Data_DDATA	EQU	10000000b	; DDATA: Should always be set to 1
Data_RESETB	EQU	01000000b	; -RESETB: 0 to hold BUSY latch clear
Data_NOPAPER	EQU	00100000b	; -NOPAPER: 0 signals PAPEROUT to sender
Data_SELCTD	EQU	00010000b	; SELCTD: 1 signals SELECTED to sender
Data_ERROR	EQU	00001000b	; -ERROR: 0 signals ERROR to sender
Data_DACK	EQU	00000100b	; -DACK: 1-0 edge triggered
Data_SCL	EQU	00000010b	; -SCL: 1-0 edge triggered
Data_SDO	EQU	00000001b	; SDO: data into shift reg and loopback
Data_Idle	EQU	11000111b	; Value to OR with to set controls idle
Data_Dflt	EQU	11111111b	; Default (initial) value for Data reg.

Stat_ACKP	EQU	10000000b	; !-ACKP: goes to 1 during ack pulse
Stat_DRDY	EQU	01000000b	; +-DRDY: data ready (jumper sets sense)
Stat_SDI	EQU	00100000b	; SDI: data out of shift register
Stat_NOTSDI	EQU	00010000b	; -SDI: inverse of Stat_SDI
Stat_LOOPIN	EQU	00001000b	; LOOPIN: looped from Data_SDO

Cont_IRQEN	EQU	00010000b	; IRQEN: 1 enables port interrupt
Cont_SELECT	EQU	00001000b	; !-SELECT: 1= Sender's -SELECT active
Cont_INIT	EQU	00000100b	; -INITIALIZE: 0= Sender's -INIT active
Cont_AUTOFD	EQU	00000010b	; !-AUTOFEED: 1= Sender's -AUTOFD active
Cont_STROBE	EQU	00000001b	; !-STROBE: 1= Sender's -STROBE active
Cont_DFLT	EQU	00000100b	; Default (initial) value for Cont. reg.

LA_PRESENT	EQU	0		; Values returned by lptcap_test()
LA_NO_PORT	EQU	1
LA_MISSING	EQU	2
LA_INTMODE	EQU	3
LA_NO_DRDY	EQU	4
LA_ACKSTUK	EQU	5
LA_NO_DACK	EQU	6
LA_ACKLONG	EQU	7
LA_BSYSTUK	EQU	8
LA_STRSTUK	EQU	9
LA_SDISERR	EQU	10
LA_DATAERR	EQU	11

BD_TAIL		EQU	0		; Offsets into bufdescriptor
BD_HEAD		EQU	2
BD_SIZE		EQU	4
BD_PTR		EQU	6		; Either near or far pointer

IDETLOOPS	EQU	8		; Number of loops for IRQ detection

; Data (in code segment; makes things easier)

Signature	DB	13,10,13,10,"LPTCAP interface module",13,10,13,10
		DB	"(c) Copyright 1996-2000 K. Heidenstrom "
		DB	"(k@heidenstrom.gen.nz)",13,10,13,10
		DB	"May be freely used provided that this "
		DB	"copyright notice is retained"
		DB	13,10,13,10,"Version ",VersionNum+"0","."
		DB	SubVersion+"0",".",ModVersion+"0",", ",VerDateStr,13,10,13,10,26

PortNumber	DW	0		; LPT port number (1-4 or 0 for none)
PortBase	DW	0		; LPT port base I/O address
WasInited	DB	0,0,0,0,0	; Flags for hardware init, per LPT port
DataValue	DB	11111111b	; Value for data register: 11xxx111b
ContValue	DB	00000100b	; Value for control register: 000i0100b
DRDYPolarity	DB	0		; XOR mask; depends on IRQ polarity sw.
TestFailData	DW	0		; Values of failed data loopthrough test
PIC0IMRSave	DB	0		; Saved IMR value for primary PIC
PIC1IMRSave	DB	0		; Saved IMR value for secondary PIC
IRQMask		DW	0		; Mask and working flags for IRQ detect
InvIRQMask	DW	0		; Mask and working flags for inv. IRQs
LPTIntOff	DW	0		; Old IRQ handler offset
LPTIntSeg	DW	0		; Old IRQ handler segment
BufDescOff	DW	0		; Offset of 'bufdescriptor'
BufDescSeg	DW	0		; Segment of 'bufdescriptor'
IRQNum		DB	0,0		; IRQ number for interrupt receive or 0
IntHndFlag	DB	0		; Flag set by interrupt handler
LongStrobe	DB	0		; Flag for -STROBE held low by Sender
OldPIC0IMR	DB	0		; Primary PIC IMR before intmode install
OldPIC1IMR	DB	0		; Secondary PIC IMR before same

VersionData	DW	VersionNum
		DW	SubVersion
		DW	ModVersion
		DW	FileRevision
		DD	VerDate
		DW	(DelayType SHL 2) + (DATAFAR SHL 1) + CODEFAR
VersDataEnd	LABEL	BYTE

PortFunction	DW	PortFunc0
		DW	PortFunc1
		DW	PortFunc2
PortFuncEnd	LABEL	BYTE

;=============================== START OF CODE =================================

; GetTickCount - Returns loword of tick count in AX
; Destroys AX

GetTickCount	PROC	near
		push	ds		; Preserve DS
		xor	ax,ax
		mov	ds,ax		; Address BIOS data with DS
		mov	ax,ds:[46Ch]	; Get loword of BIOS tick count
		pop	ds
		ret			; Return tick count in AX
GetTickCount	ENDP

;-------------------------------------------------------------------------------

; ReadT2 - this function reads the Timer 2 output readback signal on port C
; (I/O address 62h) of a PC or PC/XT machine, or port B (I/O address 61h) of
; an AT or later machine.  The I/O address at the 'T2Port' label is modified
; by the DetectT2Port subroutine, which checks whether T2Port has been set up
; and if not, determines the machine type and sets T2Port.  This function is
; used by lptcap_test() to implement a short timeout for testing the -ACK
; pulse generator and by lptcap_adjust() for regulating the speed of the
; calibration signal.

ReadT2		PROC	near
		DB	0E4h		; IN AL,xx
T2Port		DB	0		; Timer 2 readback register
		test	al,00100000b	; Isolate timer 2 readback bit
		ret			; Return not zero if time expired
ReadT2		ENDP

;-------------------------------------------------------------------------------

; DetectT2Port - this function determines whether the machine is a PC/XT or an
; AT or later, and sets the value at T2Port accordingly.  For a PC/XT, timer 2
; readback is on I/O address 62h, for an AT it is on I/O address 61h.  In both
; cases it is on bit 5.  If T2Port is already non-zero, the port has already
; been detected, so this function does nothing.
; Destroys AX, CX.

DetectT2Port	PROC	near		; Detect timer 2 readback port (61h/62h)
		cmp	T2Port,0	; Have we already detected it?
		jnz	AlreadyT2	; If so, don't do it again
		pushf			; Keep interrupt flag
		mov	cx,400h		; Six attempts (top bits of CH)
		cli			; Lock out interrupts during this stuff
		in	al,61h		; Get Port B contents
		mov	ah,al		; Original value to AH
		in	al,21h		; Short delay
Flip61Loop:	xor	ah,10000000b	; Flip top bit
		mov	al,ah		; Get value to AL
		out	61h,al		; Write value to port
		in	al,21h		; Short delay
		in	al,61h		; Read it back
		xor	al,ah		; Set bit 7 if value didn't stay
		shl	al,1		; Shift bit into carry
		rcl	cx,1		; Shift bit into bottom of CX
		jnc	Flip61Loop	; Loop if more flips (six in total).
		popf			; Restore interrupt flag
		cmp	cl,1		; Was port read/write?	Set carry if so
		adc	T2Port,61h	; If R/W - carry set - PC/XT - addr 62h
AlreadyT2:	ret			; If R/O - carry clear - AT - addr 61h
DetectT2Port	ENDP

;-------------------------------------------------------------------------------

; InsertDelay - insert a delay.  This function is used if the assembly-time
; conditional parameter VERYSLOW was defined.  See notes on DelayType.

		IF	DelayType EQ 2
InsertDelay	 PROC	near		; No registers modified
		 push	ax		; Preserve AX register
		 in	al,21h		; Read primary PIC IMR
		 jmp	SHORT $+2	; Flush prefetch queue
		 in	al,0Dh		; Read primary DMAC temporary register
		 jmp	SHORT $+2	; Flush prefetch queue
		 in	al,21h		; Read primary PIC IMR
		 jmp	SHORT $+2	; Flush prefetch queue
		 in	al,0Dh		; Read primary DMAC temporary register
		 pop	ax
		 ret
InsertDelay	 ENDP
		ENDIF

;-------------------------------------------------------------------------------

; EnableLPTInt - enable parallel port interrupt in the PIC(s).
; Assumes IRQNum = interrupt request line number (0-15 on ATs, 0-7 on PCs)
; Destroys AX, CX.

EnableLPTInt	PROC	near
		mov	cx,WORD PTR IRQNum ; Get IRQ number or zero
		jcxz	EnableIntRet	; If zero, no IRQ number specified
		mov	ax,101h		; Set bit 0 in each byte
		shl	ax,cl		; Shift bit according to IRQ
		not	ah		; Convert to AND-mask
		cmp	cl,8		; Low or high IRQ?
		pushf			; Preserve interrupt flag
		cli			; Disable interrupts
		jb	LowIRQ2		; If IRQ0-7
		in	al,0A1h		; Get secondary PIC IMR
		and	al,ah		; Enable appropriate IRQ
		out	0A1h,al		; Store it back
		mov	ah,11111011b	; Also enable IRQ2 in primary PIC
LowIRQ2:	in	al,21h		; Get current interrupt mask reg value
		and	al,ah		; Zero mask bit for desired IRQ
		out	21h,al		; Desired IRQ is now enabled in the PICs
		popf
EnableIntRet:	ret
EnableLPTInt	ENDP

;-------------------------------------------------------------------------------

; GetPortAddr - returns parallel port I/O base address in DX, also sets zero
; flag according to whether any port is present.  Zero means no port.

GetPortAddr	PROC	near		; Returns port I/O address in DX
		mov	dx,PortBase
		cmp	PortNumber,0	; Set zero flag if non-existent port
		ret
GetPortAddr	ENDP

;-------------------------------------------------------------------------------

; DetectLoopback - detects the loopback from Data_SDO to Stat_LOOPIN.
; Assumes DX = port base address on entry.
; Returns zero if loopback was detected, not-zero if not.
; Leaves data register in its original state.
; Destroys AX, CX.

DetectLoopback	PROC	near		; On entry DX = port base I/O address
		mov	cx,8		; Number of loops (must be even!)
		pushf			; Preserve interrupt flag
		cli			; Lock out interrupts
		in	al,dx		; Get data register
Loopback_Loop:	xor	al,Data_SDO	; Toggle loopback output
		out	dx,al		; Set opposite value
		mov	ah,al		; Keep value in AH
		@Delay			; Wait a moment
		inc	dx		; To status register
		in	al,dx		; Read it
		dec	dx		; Back to data register
		push	ax		; Preserve AX
		and	ax,Stat_LOOPIN + 256 * Data_SDO ; Isolate those bits
		xor	al,ah		; Get difference in the same byte
		pop	ax		; Restore data value in AH
		jpe	LoopMatched	; If matched
		inc	ch		; Increment error flag
LoopMatched:	mov	al,ah		; Get data register value back
		dec	cl		; Count down
		jnz	Loopback_Loop	; Loop and try other state
		popf			; Restore interrupt flag
		test	ch,ch		; Did LOOPIN match LOOPOUT?
		ret			; Return ZF=1 (Zero) if loop found
DetectLoopback	ENDP

;-------------------------------------------------------------------------------

; TestShift - used by lptcap_test() for data loopthrough test.	Accepts a byte
; value in AL.	Sends the byte to the adapter and reads it back.  The adapter
; must be in shifting mode (-STROBE should have been driven active by the
; software, to set the busy latch).  Stores values in TestFailData in case a
; data mismatch occurs.  See notes on lptcap_test() for the algorithm.
;
; Assumes interrupts locked out on entry.
; Assumes DX = parallel port base I/O address.
; Returns zero-flag set ('zero') if no error.
; If an error occurred, AX will contain LA_SDISERR or LA_DATAERR.
; If no error occurred, AL contains its value on entry.
; Destroys AX (see above), BX.

TestShift	PROC	near
		mov	TestFailData,ax	; Keep test value here
		mov	bx,8		; Set up bit count
		mov	ah,al		; Get to-be-sent value to AH
		mov	al,DataValue	; Get data register value
SendBitLoop:	or	al,Data_SCL	; Set -SCL high
		shr	al,1		; Shift bits down
		shr	ah,1		; Shift data bit into carry
		IF	Data_SDO NE 1
		 .ERR
		 %OUT	Code here assumes Data_SDO is bit 0
		ENDIF
		rcl	al,1		; Set bit 0 (SDO) to data bit value
		out	dx,al		; Assert data value, -SCL high
		@Delay
		and	al,NOT Data_SCL	; Set -SCL low - clocks data into reg.
		out	dx,al
		@Delay
		dec	bx		; Count down bit counter
		jnz	SendBitLoop	; Loop for eight bits
		or	al,Data_SDO OR Data_SCL ; Raise SDO and -SCL
		out	dx,al
		@Delay

		mov	ah,80h		; Set up bit flag for bit counting
LoadBitLoop:	inc	dx		; To status register
		in	al,dx		; Read it
		dec	dx		; Back to data register
		and	al,Stat_SDI OR Stat_NOTSDI ; Get SDI bits
		jpo	SDIsValid	; If SDI and -SDI are opposite
		mov	bx,LA_SDISERR	; If same, flag error
SDIsValid:	and	al,Stat_NOTSDI	; Get negative data
		cmp	al,1		; Set carry if negative data is 0
		rcr	ah,1		; Shift bit into result value
		jc	LoadBitsDone	; If we have shifted the last bit in
		mov	al,DataValue	; Get data register value
		and	al,NOT Data_SCL	; Set -SCL low - clock data through SR
		out	dx,al		; Write it
		@Delay
		or	al,Data_SCL	; Raise -SCL to idle state
		out	dx,al		; Write it
		@Delay
		jmp	SHORT LoadBitLoop ; Loop for all bits

LoadBitsDone:	mov	BYTE PTR TestFailData+1,ah ; Store the value we read
		xchg	ax,bx		; Get error indication to AX
		test	ax,ax		; Did we have SDI/-SDI error?
		jnz	ShiftDone	; If so
		mov	al,LA_DATAERR	; Prepare for data error
		cmp	bh,BYTE PTR TestFailData ; Check for data match/mismatch
		jne	ShiftDone	; If error
		mov	al,bh		; Restore up-to value in AL
ShiftDone:	ret
TestShift	ENDP

;-------------------------------------------------------------------------------

; SendAckPulse - generate an Ack pulse and wait for it to disappear.  If
; -STROBE is not active, the BUSY latch will be cleared part-way through
; the ACK pulse.  ASSUMES INTERRUPTS LOCKED OUT.  ASSUMES DX = PORTBASE.
; Destroys AL and CX.

SendAckPulse	PROC	near
		mov	al,DataValue	; Get DataValue
		and	al,NOT Data_DACK ; Drop -DACK - acknowledge data byte
		out	dx,al
		@Delay
		or	al,Data_DACK
		out	dx,al		; Return -DACK high
		inc	dx
		mov	cx,100
WaitDAck:	@Delay
		in	al,dx
		test	al,Stat_ACKP
		loopnz	WaitDAck	; Wait until timeout or -ACKP completes
		dec	dx		; Back to data register.
		ret
SendAckPulse	ENDP

;-------------------------------------------------------------------------------

; SendResetB - generate a reset signal via -RESETB.
; ASSUMES INTERRUPTS LOCKED OUT.  ASSUMES DX = PORTBASE.
; Destroys AL.

SendResetB	PROC	near
		mov	al,DataValue	; Get DataValue
		and	al,NOT Data_RESETB ; Drop -RESETB
		out	dx,al
		@Delay
		or	al,Data_RESETB
		out	dx,al		; Return -RESETB high
		ret
SendResetB	ENDP

;-------------------------------------------------------------------------------

; CaptureByte - receive a byte from the hardware and send an acknowledge
; signal to the sender.  THIS FUNCTION ASSUMES THAT INTERRUPTS ARE LOCKED OUT.
; Returns AL = captured byte; AH = 0.  Destroys AX, BX, DX.

CaptureByte	PROC	near
		mov	dx,PortBase	; Get port I/O base address
		mov	bx,80h		; Set bit 7 of BL; zero BH
		mov	al,DataValue	; Get data register value
		mov	ah,al		; Keep it in AH
		out	dx,al
CaptReadLoop:	@Delay
		inc	dx
		in	al,dx		; Read status register
		and	al,Stat_SDI OR Stat_NOTSDI
		jpo	GotBit		; If SDI and -SDI are different
		@Delay			; If same, wait a moment and try again
		in	al,dx		; Read status register again
GotBit:		dec	dx		; Back to data register
		and	al,Stat_NOTSDI	; Get -SDI
		cmp	al,1		; Set carry if data active
		rcr	bl,1		; Rotate new bit in, shift 1-bit down
		jc	GotBits		; If the 1-bit popped out, we're done
		mov	al,ah
		and	al,NOT Data_SCL	; Clock a bit through
		out	dx,al
		@Delay
		mov	al,ah		; Raise -CLK back again
		out	dx,al
		jmp	SHORT CaptReadLoop ; Loop for all bits

GotBits:	push	cx		; Don't destroy CX
		inc	dx
		inc	dx
		in	al,dx
		dec	dx
		dec	dx
		test	al,Cont_STROBE	; Is sender still holding -STROBE low?
		jz	StrobeGone	; If not, continue
		mov	LongStrobe,1	; Flag strobe held low by sender
		jmp	SHORT CaptureExit ; Don't send ack yet - leave busy

StrobeGone:	call	SendAckPulse	; Send acknowledgement, clear BUSY
CaptureExit:	pop	cx		; Restore CX
		xchg	ax,bx		; Return byte value in AX
		ret
CaptureByte	ENDP

;-------------------------------------------------------------------------------

; TestLatched - tests whether new data has been captured and latched by the
; LPTCAP adapter - returns zero if not, non-zero if so.  If LongStrobe flag
; is set, will always return 'no data available'.  This condition must be
; unlatched by calling Background repeatedly until it clears.
; Must not be called if there is no LPTCAP port (i.e. it assumes PortBase is
; valid).
; Destroys AL, DX.

TestLatched	PROC	near
		cmp	LongStrobe,1	; Test for -STROBE held low by Sender
		jz	TestLatchRet	; If so, say 'no data ready'.
		mov	dx,PortBase
		inc	dx
		in	al,dx		; Read status register
		xor	al,DRDYPolarity
		test	al,Stat_DRDY	; Is there data ready?
TestLatchRet:	ret
TestLatched	ENDP

;-------------------------------------------------------------------------------

; StuffBuf - check whether there is space in the interrupt-driven receive
; buffer, and if so, call CaptureByte to capture the byte, and add the byte
; to the interrupt-driven receive buffer.
; Assumes DX = PortBase+1.
; ASSUMES INTERRUPTS ARE LOCKED OUT.
; ASSUMES THAT THERE IS A BYTE READY TO BE CAPTURED.
; Returns carry set if buffer was full, otherwise returns carry clear.
; Destroys AX, BX, DX.

StuffBuf	PROC	near
		push	es
		les	bx,DWORD PTR BufDescOff ; Point to bufdescriptor
		mov	ax,es:[bx+BD_TAIL]
		push	ax		; Keep tail pointer
		inc	ax		; Bump tail pointer
		cmp	ax,es:[bx+BD_SIZE] ; Time to wrap?
		jb	NoWrap3		; If not
		xor	ax,ax
NoWrap3:	cmp	ax,es:[bx+BD_HEAD] ; Is the buffer already full?
		stc			; Prepare for error
		je	BufferFull	; If so
		mov	es:[bx+BD_TAIL],ax ; Store new tail pointer
		pop	ax		; Get previous tail pointer back
		add	ax,es:[bx+BD_PTR+0] ; Add offset to index
		IF	DATAFAR
		 mov	es,es:[bx+BD_PTR+2] ; Get segment
		ENDIF
		push	ax		; Keep combined offset
		call	CaptureByte	; Get the byte
		pop	bx		; Restore combined offset
		mov	es:[bx],al	; Store character in buffer
		DB	34h		; XOR AL,xx - clears carry - successful
BufferFull:	pop	ax		; Fix up stack
		pop	es
		ret
StuffBuf	ENDP

;-------------------------------------------------------------------------------

; Background - Housekeeping function.
;
; This function checks for and handles certain conditions which can occur as
; a result of improper behaviour of the Sender or resident software in the
; Capture PC.  These conditions are the LongStrobe condition and the lost
; IRQ condition.
;
; The LongStrobe condition occurs when the Sender drives -STROBE low for a much
; longer time than the Centronics specification calls for, usually due to an
; interrupt, DMA burst or other gap in CPU activity occurring at the Sender
; between the time it drives -STROBE low and the time it drives -STROBE high.
; This prevents the LPTCAP adapter from acknowledging the byte and returning
; to its normal state.	This software handles this condition by leaving the
; adapter in the latched (BUSY) state and setting the LongStrobe variable.
; While LongStrobe is true, the TestLatched function will always return 'zero'
; (i.e. no data ready) because there is no new data.  This function unlatches
; the condition, by checking for LongStrobe set and if so, checking whether
; -STROBE has gone inactive.  If so, this function calls SendAckPulse to send
; an acknowledgement pulse and reset the adapter to its normal condition, and
; clears LongStrobe.
;
; The lost IRQ condition occurs when badly behaved TSRs or other resident
; software disables the LPTCAP IRQ (usually IRQ7) or send a bogus EOI command.
; In this state, the LPTCAP hardware says it has a new character latched but
; the interrupt controller(s) report that no IRQ is pending.  This condition
; is applicable only in interrupt-driven receive mode.
;
; Destroys AX, BX, CX.

Background	PROC	near
		push	dx		; Preserve DX
		mov	dx,PortBase
		cmp	LongStrobe,0	; Is hardware in the LongStrobe state?
		jz	NoLongStrobe	; If not

; Handle unlatching of LongStrobe state if possible

		inc	dx
		inc	dx		; If so, see whether it has cleared
		pushf
		cli
		mov	al,ContValue
		out	dx,al		; Make sure we aren't driving it active!
		@Delay
		in	al,dx
		popf
		dec	dx
		dec	dx		; Back to data register
		test	al,Cont_STROBE	; Strobe still active?
		jnz	NoLongStrobe	; If so, we can't do anything yet

; Strobe was previously stuck and has now gone away - send an acknowledgement
; pulse (which will also clear the BUSY latch) and clear the LongStrobe flag.

		pushf
		cli
		call	SendAckPulse
		mov	LongStrobe,0	; Clear LongStrobe
		popf			; Restore interrupt flag

; If operating in interrupt-driven mode, and not in LongStrobe state, check for
; lost interrupt.

NoLongStrobe:	cmp	IRQNum,0	; Are we operating in interrupt mode?
		jz	NoLostIRQ	; If not
		cmp	LongStrobe,0	; Stuck waiting for Strobe?
		jnz	NoLostIRQ	; If so

		pushf
		sti
		mov	IntHndFlag,0	; Reset interrupt handler flag
		call	TestLatched	; New data ready?
		jz	NoDRDY		; If not
		cmp	IntHndFlag,0	; Had an interrupt?
		jnz	NoDRDY		; If so, alright
		call	EnableLPTInt	; Enable interrupt in PIC(s)
		mov	IntHndFlag,0	; Reset interrupt handler flag again
		call	TestLatched	; Data still waiting?
		jz	NoDRDY		; If not
		cmp	IntHndFlag,0	; Had an interrupt?
		jnz	NoDRDY		; If so, alright
		cli			; Lock out interrupts for StuffBuf
		call	StuffBuf	; If stuck, get the character now
NoDRDY:		popf
NoLostIRQ:	pop	dx		; Restore DX
		ret
Background	ENDP

;-------------------------------------------------------------------------------

; LPTCAP_IRQHnd - interrupt handler for LPTCAP parallel port interrupts

LPTCAP_IRQHnd	PROC	far
		push	dx
		push	bx
		push	ax
		pushf
		cli			; In case we are chained by naughty code
		mov	IntHndFlag,1	; Flag an interrupt occurred
		call	TestLatched
		jz	FalseAlarm	; If not
		call	StuffBuf	; Get character and stuff it in buffer
		mov	al,20h
		cmp	IRQNum,8	; IRQ 8-15?
		jb	SendEOI		; If not
		out	0A0h,al		; Send EOI to secondary PIC
SendEOI:	out	20h,al		; Send EOI to primary PIC
		popf
		pop	ax
		pop	bx
		pop	dx
		iret
FalseAlarm:	popf
		pop	ax
		pop	bx
		pop	dx
		jmp	DWORD PTR LPTIntOff ; Jump to old handler
LPTCAP_IRQHnd	ENDP

;-------------------------------------------------------------------------------

; unsigned int lptcap_version(int request)

		PUBLIC	_lptcap_version
		IF	CODEFAR
_lptcap_version	 PROC	far
		ELSE
_lptcap_version	 PROC	near
		ENDIF

		push	bp
		mov	bp,sp
		mov	bx,[bp+2+CALLSIZE] ; Get 'request' parameter
		cmp	bx,(VersDataEnd - VersionData) / 2 ; Validate
		mov	ax,-1		; Prepare for out of range
		jae	VersionRange	; If so
		shl	bx,1		; Double for word-sized values
		mov	ax,VersionData[bx] ; Get value
VersionRange:	pop	bp
		ret			; Return value in AX
_lptcap_version	ENDP

;-------------------------------------------------------------------------------

; int lptcap_port(int findmode)

		PUBLIC	_lptcap_port
		IF	CODEFAR
_lptcap_port	 PROC	far
		ELSE
_lptcap_port	 PROC	near
		ENDIF
		push	bp
		mov	bp,sp
		mov	bx,[bp+2+CALLSIZE] ; Get 'findmode' parameter
		cmp	bx,(PortFuncEnd - PortFunction) / 2 ; Validate
		mov	ax,-1		; Prepare for error
		jae	PortRange	; If invalid
		shl	bx,1		; Double for word-sized values
		jmp	PortFunction[bx] ; Go to appropriate handler

; Try first port

PortFunc1:	mov	PortNumber,0	; Start from before first possible port

; Try next port

PortFunc2:	inc	PortNumber	; Go to next port
		mov	ax,PortNumber	; Get port number
		cmp	ax,5		; Check for gone too far
		jb	TryPort		; If not
		mov	PortNumber,0	; If so, report nothing found
		mov	PortBase,0	; Zero base as well
		jmp	SHORT PortFunc0	; Return it

; Get port address

TryPort:	mov	bx,PortNumber	; Get current port number to BX
		shl	bx,1		; Double for word-sized I/O addresses
		push	ds
		xor	dx,dx
		mov	ds,dx		; Address BIOS data with DS
		mov	dx,ds:[406h+bx]	; Get base address of port to DX
		pop	ds
		mov	ax,dx		; To AX
		dec	ax
		cmp	ax,3FDh		; Validate (must have been 1-3FDh)
		jae	PortFunc2	; If not, try next port

; Test whether port has LOOPOUT looped back to LOOPIN

		call	DetectLoopback	; Check for loopback
		jnz	PortFunc2	; If failed, try another port

; Set port I/O address variables and initialise port

		pushf
		cli
		mov	PortBase,dx	; Store as base and data register addr
		mov	al,Data_Dflt	; Get default (initial) value
		mov	DataValue,al	; Store
		out	dx,al		; Set it
		inc	dx		; To status register
		inc	dx		; To control register
		mov	al,Cont_DFLT	; Get default (initial) value
		mov	ContValue,al	; Store
		out	dx,al		; Set it
		popf

; Return port number or 0 if none

PortFunc0:	mov	ax,PortNumber	; Get port number
PortRange:	pop	bp
		ret			; Return value in AX
_lptcap_port	ENDP

;-------------------------------------------------------------------------------

; int lptcap_test(unsigned int ntests)

		PUBLIC	_lptcap_test
		IF	CODEFAR
_lptcap_test	 PROC	far
		ELSE
_lptcap_test	 PROC	near
		ENDIF

		push	bp
		mov	bp,sp
		call	GetPortAddr	; Get parallel port address
		jnz	Alright1	; If there is an LPTCAP port, continue
		mov	ax,LA_NO_PORT	; If not, return error indication
		jmp	TestExit	; Return error code

; Check for single line loopback, return error LA_MISSING if not present

Alright1:	call	DetectLoopback	; First, check for loop

		pushf
		cli			; Lock interrupts out
		mov	al,DataValue	; Get data register value
		out	dx,al		; Set the register
		popf			; Restore interrupt flag

		jz	Alright2	; If loopback test was successful
		mov	ax,LA_MISSING	; If error, adapter is not attached
GoTestExit:	jmp	TestExit	; Return error code

; Make sure it is not running in interrupt mode

Alright2:	cmp	IRQNum,0
		mov	ax,LA_INTMODE
		jnz	GoTestExit	; If interrupt mode, return error

; Force a delay of 1 to 2 ticks if this port hasn't been used before - this
; gives the VCC reservoir capacitor time to charge up.

		mov	bx,PortNumber
		mov	al,1
		xchg	al,WasInited[bx] ; Set flag, get previous state
		test	al,al		; Has it been initialised?
		jnz	HasBeenInited	; If so

		pushf			; Preserve interrupt flag
		sti			; Make sure interrupts are enabled
		call	GetTickCount	; Get tick count now
		xchg	ax,bx		; To BX
WaitTick1:	call	GetTickCount	; Get tick count
		cmp	ax,bx		; Changed?
		je	WaitTick1	; If not, loop
		xchg	ax,bx		; New tick count to BX
WaitTick2:	call	GetTickCount	; Get tick count
		cmp	ax,bx		; Changed?
		je	WaitTick2	; If not, loop
		popf			; Restore interrupt flag

; Determine setting of IRQ Polarity switch or jumper on the LPTCAP adapter and
; set the DRDYPolarity variable accordingly.  The procedure is:
; Set -RESETB to electrical low (this forces the BUSY latch to the cleared
; state, regardless of the states of any other signals), wait a short time,
; then read the +-DRDY signal in the status register.  If the bit is 0, then
; the switch/jumper is in the Positive IRQ position (the normal position).
; In this case, DRDYPolarity is 0.  If the status register bit is 1, then the
; switch/jumper is in the Negative IRQ position, and DRDYPolarity is set to
; 01000000b.

HasBeenInited:	pushf
		cli			; Lock out interrupts
		mov	al,DataValue
		and	al,NOT Data_RESETB ; Drive -RESETB active
		out	dx,al
		@Delay
		in	al,21h
		in	al,21h		; More delay
		inc	dx
		in	al,dx
		dec	dx
		and	al,Stat_DRDY
		mov	DRDYPolarity,al	; Set DRDY polarity to current state
		mov	al,DataValue
		out	dx,al		; Raise -RESETB to inactive

; Detect Timer 2 readback port

		call	DetectT2Port	; Determine timer 2 readback port addr

; Perform basic logic function - repeat according to logic_tests parameter

		mov	cx,[bp+2+CALLSIZE] ; Get 'ntests' parameter
		cmp	cx,1
		adc	cx,0		; Map 0 to 1

; Main test loop ---------------------------------------------------------------

TestLoop:

; Check that data-ready indication is received from the latch when we drive
; -STROBE active.  At the start of this loop, interrupts are disabled and the
; data port is set to DataValue (i.e. all adapter control signals idle).
; Procedure:  Drive -STROBE active, wait, raise -STROBE, wait, test +-DRDY and
; return LA_NO_DRDY if inactive.

		mov	dx,PortBase
		inc	dx
		inc	dx		; To control register
		mov	al,ContValue
		or	al,Cont_STROBE	; Drive -STROBE active
		out	dx,al		; Set it
		@Delay
		and	al,NOT Cont_STROBE ; Raise -STROBE
		out	dx,al		; Set it
		@Delay
		dec	dx		; To status register
		in	al,dx		; Read it
		xor	al,DRDYPolarity	; Adjust for DRDY polarity
		test	al,Stat_DRDY	; Isolate DRDY bit (should be active)
		mov	ax,LA_NO_DRDY	; Prepare for error: no DRDY signal
		jz	GoFTestRet	; If error, pop flags and return

; Check that -ACKP is not stuck active, then check that it goes active when
; we drive -DACK active, and check that it goes inactive within a short time.
; Procedure: test -ACKP and return LA_ACKSTUK if active, drop -DACK and
; immediately read -ACKP, and return LA_NO_DACK if inactive.  Raise -DACK,
; wait with timeout until -ACKP inactive and return LA_ACKLONG if timeout.

		in	al,dx		; Read status register again
		test	al,Stat_ACKP	; Test -ACKP signal
		mov	ax,LA_ACKSTUK	; Prepare for error: -ACKP stuck low
		jnz	GoFTestRet	; If error, pop flags and return

		dec	dx		; Back to data register
		mov	al,DataValue	; Get current data value
		and	al,NOT Data_DACK ; Drop -DACK (falling edge triggered)
		out	dx,al
		inc	dx		; Back to status register
		in	al,dx		; Read status register
		test	al,Stat_ACKP	; Isolate -ACKP bit
		mov	ax,LA_NO_DACK	; Prepare for -ACKP did not go active
		jz	GoFTestRet	; If error, pop flags and return

		dec	dx		; Back to data register
		mov	al,DataValue
		out	dx,al		; Raise -DACK
		inc	dx		; Back to status register

; Start timeout for idle-going edge of -DACK pulse

		in	al,61h		; Read Port B
		and	al,11111100b
		or	al,00000001b	; Turn on timer 2 gate, turn off speaker
		out	61h,al
		mov	al,90h		; Timer 2, lobyte only, mode 0, binary
		out	43h,al		; Send command byte - prepare the timer
		mov	al,60		; Number of 1.1931816666 MHz clocks
					; Value 60 gives about 50 us timeout
		out	42h,al		; Start the timer

Wait_ACKP:	in	al,dx		; Read status register
		test	al,Stat_ACKP	; Test -ACKP signal
		jz	Alright3	; If inactive, break out of loop
		call	ReadT2		; Test for timeout
		jz	Wait_ACKP	; If not timed out yet
		mov	ax,LA_ACKLONG	; Error: -ACKP pulse too long
GoFTestRet:	jmp	SHORT FTestReturn ; Pop flags and return error code

; Check that the -ACK pulse cleared the BUSY latch.  +-DRDY should be inactive.
; If not, test the -STROBE signal and return BSYSTUK if -STROBE is inactive
; (this means that the BUSY latch was not reset by the -ACK pulse but -STROBE
; is in the correct state) or STRSTUK if -STROBE is active, which could mean a
; problem on the capture machine or on the Sender.  Either of these situations
; could also mean that the Sender is trying to send data while the test is
; being performed.

Alright3:	xor	al,DRDYPolarity	; Correct polarity of DRDY
		test	al,Stat_DRDY	; Test it
		jz	Alright4	; If inactive, okay - continue
		inc	dx		; If active, find out why
		in	al,dx
		test	al,Cont_STROBE	; Test -STROBE
		mov	ax,LA_BSYSTUK	; Prepare for Busy latch stuck
		jz	GoFTestRet	; If so, pop flags and return
		mov	al,LA_STRSTUK	; Strobe stuck
		jmp	SHORT GoFTestRet ; Pop flags and return error code

GoTestLoop:	jmp	SHORT TestLoop	; Branch point

; Data loopthrough test - checks operation of shift register by shifting data
; values through it.  For each byte, shift the byte into the shift register
; using the SDO and -SCL lines, then shift it out using -SCL and reading the
; data on SDI and -SDI.  If at any stage SDI is not the complement of -SDI,
; return error LA_SDISERR.  If the reassembled data byte does not match the
; byte that was sent, return error LA_DATAERR, with the sent and received byte
; values stored in TestFailData (can be obtained via lptcap_test_fail_data()
; and displayed in a diagnostic message by the caller).  Byte values of 0,
; 0FFh, 55h and 0AAh are sent and received.
;
; At the start of the test, ensure that the adapter control lines are in their
; idle states, and set -STROBE active then inactive, in order to set the BUSY
; latch so that the shift register will be in shifting mode.
;
; Then, for each data value (0, 0FFh, 55h, 0AAh) do:
;
;   Disable interrupts.
;   Loop1: Present data bit on SDO, wait, drop -SCL, wait, raise -SCL, loop
;	   for eight data bits to Loop1.
;   Loop2: Read SDI and -SDI and return with LA_SDISERR if they are the same.
;	   Shift bit into received byte, drop -SCL, wait, raise -SCL, wait,
;	   loop for eight data bits to Loop2.
;   Enable interrupts.
;   Check received value matched sent value and return LA_DATAERR if not.
;   Repeat the test as appropriate, according to the data_tests parameter.
; Then finally, force the adapter into a known state via -RESETB.

Alright4:	mov	dx,PortBase	; To data register
		mov	al,DataValue
		out	dx,al		; Set to normal idle states
		inc	dx
		inc	dx
		mov	al,ContValue
		or	al,Cont_STROBE	; Drive -STROBE active (electrical low)
		out	dx,al
		@Delay
		and	al,NOT Cont_STROBE
		out	dx,al
		dec	dx
		dec	dx		; Back to control register
		@Delay

		xor	ax,ax
		call	TestShift	; 0
		jnz	FTestReturn	; If error
		dec	ax
		call	TestShift	; 0FFh
		jnz	FTestReturn	; If error
		mov	al,055h
		call	TestShift	; 055h
		jnz	FTestReturn	; If error
		not	al
		call	TestShift	; 0AAh
		jnz	FTestReturn	; If error

		call	SendResetB	; Reset data capture latch

		loop	GoTestLoop	; Repeat test specified number of times

		xor	ax,ax		; Flag no error (LA_PRESENT), drop
					; through to code to reset hardware

; End of tests - return hardware to normal

FTestReturn:	push	ax		; Keep error code
		cli
		mov	dx,PortBase	; Get parallel port address
		call	SendResetB	; Reset BUSY latch
		mov	LongStrobe,0	; Clear long-strobe flag
		pop	ax		; Restore error code
PopfTestReturn:	popf			; Restore interrupt flag
TestExit:	pop	bp
		ret
_lptcap_test	ENDP

;-------------------------------------------------------------------------------

; unsigned int lptcap_test_fail_data(void)

		PUBLIC	_lptcap_test_fail_data
		IF	CODEFAR
_lptcap_test_fail_data PROC far
		ELSE
_lptcap_test_fail_data PROC near
		ENDIF

		mov	ax,TestFailData
		ret
_lptcap_test_fail_data ENDP

;-------------------------------------------------------------------------------

; void lptcap_adjust(unsigned int ticks)

; Perform calibration test by generating a timed sequence of signals to the
; LPTCAP adapter for a specified period of time.  If the parameter is zero,
; the signal is generated until the Ctrl key is pressed.

		PUBLIC	_lptcap_adjust
		IF	CODEFAR
_lptcap_adjust	 PROC	far
		ELSE
_lptcap_adjust	 PROC	near
		ENDIF

		push	bp
		mov	bp,sp
		call	GetPortAddr	; Get parallel port address
		jz	AdjustRet	; If no port, do nothing
		cmp	IRQNum,0	; Test for interrupt mode
		jnz	AdjustRet	; If interrupt mode, do nothing

		mov	cx,[bp+2+CALLSIZE] ; Get 'ticks' parameter

; Set up timer 2 to generate a square wave with a divisor of 84 (giving a
; cycle period of 70.4 us).  The signals generated are:
;
;		³<------------------ 70.4 us ------------------>³
;	      ÄÄ¿			ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
; T2OUT		³			³			³
;		ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ			ÀÄÄ
;	      ÄÄÄ¿  ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
; -DACK		 ³  ³						 ³
;		 ÀÄÄÙ						 ÀÄ
;		 ÚÄÄÄÄÄÄÄÄÄ¿					 ÚÄ
; +ACKP (U2.9)	 ³<-10 us->³<------------- 60.4 us ------------->³
;	      ÄÄÄÙ	   ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ
;		 ³    ÚÄÄÄÄÄÄÄÄ¿
; U2 pin 3	 ³<5u>³        ³
;	      ÄÄÄÄÄÄÄÄÙ        ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
;
; Trimpot R2 controls the width of the +ACKP pulse on U2 pin 9.  This should
; be a 10 us positive pulse every 70.4 us, i.e. a duty cycle of about 14%.
;
; Trimpot R1 controls the time from the falling edge of -DACK to the rising
; edge of the clock signal on U2 pin 3.  This time period should be 5 us.
; If R1 resistance is too high, no pulse will appear on U2 pin 3.  The right
; setting for R1 is half way between minimum resistance and the point at which
; the pulse disappears.

		pushf			; Preserve interrupt flag
		sti			; Enable interrupts

Test1Tick:	push	cx		; Push tick counter
		call	GetTickCount	; Get tick count
		xchg	ax,bx		; To BX
TestBurst:	mov	cx,100		; Generate burst for about 5 ms
		cli			; Lock interrupts during burst
		in	al,61h		; Read Port B
		and	al,11111100b
		or	al,00000001b	; Turn on timer 2 gate, turn off speaker
		out	61h,al
		mov	al,96h		; Timer 2, lobyte only, mode 3, binary
		out	43h,al		; Send command byte - prepare the timer
		mov	al,84		; Value of 84 gives a period of 70.4 us.
		out	42h,al		; Start the timer

; Wait for T2 output to go low, then drop and raise -DACK.

WaitLoop1:	call	ReadT2		; Read timer 2 output
		jnz	WaitLoop1	; Wait for T2 to go low
		mov	al,DataValue	; Get current data value
		and	al,NOT Data_DACK ; Drop -DACK
		out	dx,al
		@Delay
		or	al,Data_DACK	; Raise -DACK
		out	dx,al

; Wait for T2 output to go high

WaitLoop2:	call	ReadT2		; Read timer 2 output
		jz	WaitLoop2	; Wait for T2 to go high

; Repeat loop

		loop	WaitLoop1	; Do a burst of test pulses

		sti			; Enable interrupts
		call	GetTickCount	; Get tick count again
		cmp	ax,bx		; Has tick count changed?
		je	TestBurst	; If not, do another burst
		pop	cx
		jcxz	TestCtrl	; If waiting for Ctrl press

		loop	Test1Tick	; Loop for specified number of ticks
		jmp	SHORT AdjustEnd	; Restore hardware to normal and exit

TestCtrl:	push	ds
		xor	ax,ax
		mov	ds,ax
		test	WORD PTR ds:[417h],00000100b ; Test for Ctrl
		pop	ds
		jz	Test1Tick

AdjustEnd:	popf			; Restore interrupt flag
AdjustRet:	pop	bp
		ret
_lptcap_adjust	ENDP

;-------------------------------------------------------------------------------

; unsigned int lptcap_get_cont(void)

		PUBLIC	_lptcap_get_cont
		IF	CODEFAR
_lptcap_get_cont PROC	far
		ELSE
_lptcap_get_cont PROC	near
		ENDIF

		call	GetPortAddr	; Get parallel port address
		jz	GetContExit	; If there is no port, return zero
		inc	dx		; Point to status register
		inc	dx		; Point to control register
		pushf
		cli
		mov	al,ContValue
		out	dx,al		; Make sure we drive the lines open
		popf
		@Delay
		in	al,dx		; Read control register
		and	ax,Cont_SELECT OR Cont_INIT OR Cont_AUTOFD ; Get bits
		xor	al,Cont_INIT	; This bit is inverted
GetContExit:	ret
_lptcap_get_cont ENDP

;-------------------------------------------------------------------------------

; void lptcap_set_stat(unsigned int stat_word)

		PUBLIC	_lptcap_set_stat
		IF	CODEFAR
_lptcap_set_stat PROC	far
		ELSE
_lptcap_set_stat PROC	near
		ENDIF

		push	bp
		mov	bp,sp
		call	GetPortAddr	; Get parallel port address
		jz	SetStatExit	; If there is no port, do nothing
		mov	ax,[bp+2+CALLSIZE] ; Get stat_word parameter
		not	al		; Flip all bits
		or	al,Data_Idle	; Set all adapter control signals high
		pushf
		cli			; Lock out interrupts around this stuff
		mov	DataValue,al	; Store data port value
		out	dx,al
		popf			; Restore interrupt flag
SetStatExit:	pop	bp
		ret
_lptcap_set_stat ENDP

;-------------------------------------------------------------------------------

; void lptcap_send_ack(void)

		PUBLIC	_lptcap_send_ack
		IF	CODEFAR
_lptcap_send_ack PROC	far
		ELSE
_lptcap_send_ack PROC	near
		ENDIF

		call	GetPortAddr	; Get parallel port address
		jz	SendAckExit	; If there is no port, do nothing
		pushf
		cli			; Lock out interrupts
		call	SendAckPulse	; Generate an ACK pulse
		popf			; Restore interrupt flag
SendAckExit:	ret
_lptcap_send_ack ENDP

;-------------------------------------------------------------------------------

; int lptcap_poll_new(void)

		PUBLIC	_lptcap_poll_new
		IF	CODEFAR
_lptcap_poll_new PROC	far
		ELSE
_lptcap_poll_new PROC	near
		ENDIF

		call	GetPortAddr	; Get parallel port address
		jz	RetZero		; If there is no port, return zero

		call	Background	; Do background checking

		cmp	IRQNum,0	; Interrupt mode?
		jz	PollNewPoll	; If not, go and poll the hardware
		pushf
		cli
		les	bx,DWORD PTR BufDescOff ; Point to bufdescriptor
		mov	ax,es:[bx+BD_TAIL]
		xor	ax,es:[bx+BD_HEAD] ; Get zero if same, non-zero if not
		popf
		cmp	ax,1		; Set carry if AX is zero
		sbb	ax,ax		; Get -1 if same or 0 if different
		inc	ax		; Get 0 if same or 1 if different
		ret

PollNewPoll:	call	TestLatched	; Any new data latched?
		jz	RetZero		; If not
		mov	ax,1		; If so
		ret
RetZero:	xor	ax,ax
		ret
_lptcap_poll_new ENDP

;-------------------------------------------------------------------------------

; int lptcap_next_char(void)

		PUBLIC	_lptcap_next_char
		IF	CODEFAR
_lptcap_next_char PROC	far
		ELSE
_lptcap_next_char PROC	near
		ENDIF

		call	GetPortAddr	; Get parallel port address
		jz	Ret_NoData	; If there is no port, return -1

		call	Background	; Do background checking

		cmp	IRQNum,0	; Interrupt mode?
		jz	NextChrPoll	; If not, go and poll the hardware
		pushf
		cli
		les	bx,DWORD PTR BufDescOff ; Point to bufdescriptor
		mov	ax,es:[bx+BD_HEAD]
		cmp	ax,es:[bx+BD_TAIL] ; Any data in buffer?
		je	Popf_NoData	; If not
		mov	dx,ax		; Keep head pointer in DX
		inc	ax		; Bump head pointer
		cmp	ax,es:[bx+BD_SIZE] ; Time to wrap?
		jb	NoWrap1		; If not
		xor	ax,ax
NoWrap1:	mov	es:[bx+BD_HEAD],ax ; Store new head pointer
		add	dx,es:[bx+BD_PTR+0] ; Add offset to index
		IF	DATAFAR
		 mov	es,es:[bx+BD_PTR+2] ; Get segment
		ENDIF
		mov	bx,dx		; Get combined offset to BX
		mov	al,es:[bx]	; Get character from buffer
		jmp	SHORT Popf_Return

Popf_NoData:	popf			; Restore interrupt flag
Ret_NoData:	mov	ax,-1		; Return -1 indicating no data ready
		ret

NextChrPoll:	pushf
		cli
		call	TestLatched	; Any new data pending?
		jz	Popf_NoData	; If inactive, return no data
		call	CaptureByte	; Capture the pending character
Popf_Return:	popf			; Restore interrupt flag
		xor	ah,ah		; Zero hibyte
		ret			; Return character
_lptcap_next_char ENDP

;-------------------------------------------------------------------------------

; int lptcap_wait_char(unsigned int timeout_ticks)

		PUBLIC	_lptcap_wait_char
		IF	CODEFAR
_lptcap_wait_char PROC	far
		ELSE
_lptcap_wait_char PROC	near
		ENDIF

		push	bp
		mov	bp,sp
		call	GetPortAddr	; Get parallel port address
		jz	Ret_NoData	; If there is no port, return -1

		call	Background	; Do background checking

		mov	cx,[bp+2+CALLSIZE] ; Get timeout_ticks parameter
		add	cx,1		; Add (up to) one more tick
		sbb	cx,0		; But don't wrap it around to zero

		cmp	IRQNum,0	; Interrupt mode?
		jz	WaitChrPoll	; If not, go and poll the hardware
		pushf
		sti
		call	GetTickCount
		xchg	ax,dx		; Tick count to DX
WaitChrLoop1:	call	Background	; Do background checking
		cli
		les	bx,DWORD PTR BufDescOff ; Point to bufdescriptor
		mov	ax,es:[bx+BD_HEAD]
		cmp	ax,es:[bx+BD_TAIL] ; Any data in buffer?
		je	NoDataYet1	; If not
		mov	dx,ax		; Keep tail pointer in DX
		inc	ax		; Bump tail pointer
		cmp	ax,es:[bx+BD_SIZE] ; Time to wrap?
		jb	NoWrap2		; If not
		xor	ax,ax
NoWrap2:	mov	es:[bx+BD_HEAD],ax ; Store new head pointer
		add	dx,es:[bx+BD_PTR+0] ; Add offset to index
		IF	DATAFAR
		 mov	es,es:[bx+BD_PTR+2] ; Get segment
		ENDIF
		mov	bx,dx		; Get combined offset to BX
		mov	al,es:[bx]	; Get character from buffer
		jmp	SHORT ReturnChr	; Clear AH, pop flags and return

NoDataYet1:	sti			; Interrupts back on
		call	GetTickCount	; Get tick count to AX
		cmp	ax,dx		; Changed?
		je	WaitChrLoop1	; If not
		xchg	ax,dx		; Get new tick count to DX
		loop	WaitChrLoop1	; Loop for more ticks
		jmp	SHORT ReturnTimeout ; Return timeout indication

WaitChrPoll:	call	GetTickCount
		xchg	ax,bx		; Tick count to BX
		pushf
WaitChrLoop2:	call	Background	; Do background checking
		cli
		call	TestLatched	; New data ready?
		jz	NoDataYet2	; If inactive, return no data
		call	CaptureByte	; Capture the pending character

ReturnChr:	popf			; Restore interrupt flag
		xor	ah,ah		; Zero hibyte of return value
		pop	bp
		ret			; Return character

NoDataYet2:	sti			; Allow tick interrupt etc
		call	GetTickCount	; Get tick count to AX
		cmp	ax,bx		; Changed?
		je	WaitChrLoop2	; If not
		xchg	ax,bx		; Get new tick count to BX
		loop	WaitChrLoop2	; Loop for more ticks

ReturnTimeout:	popf			; Restore interrupt flag
		mov	ax,-1		; Return timeout indication
		pop	bp
		ret
_lptcap_wait_char ENDP

;-------------------------------------------------------------------------------

; int lptcap_autodetect_irq(unsigned int irqmask)
;
; Auto-detect the IRQ number for the LPTCAP port.  This is done by disabling
; interrupts via the CLI instruction, enabling (on the interrupt controllers)
; the IRQs specified by the irqmask parameter, enabling the IRQ line driver on
; the LPTCAP port, then toggling the incoming interrupt trigger line (+-DRDY
; signal) by holding -STROBE low and toggling -RESETB, watching the interrupt
; request register (IRR) in each interrupt controller to see whether any IRQ
; line enabled by irqmask is following the +-DRDY signal.
;
; On some older parallel ports, the IRR bit follows the logical opposite of
; +-DRDY, since the IRQ line is driven to the positive, active level when the
; +-DRDY line is low.  On most machines, the active state is the opposite
; state, so the IRR bit follows +-DRDY.  To support both types of machines,
; the LPTCAP adapter has an IRQ Polarity switch or jumper, which selects a true
; or inverted signal for the +-DRDY line.  In the Negative IRQ position, it
; works with a parallel port which triggers an IRQ when pin 10 of the 25-pin
; connector transitions from high to low.  In the Positive IRQ position, it
; works with a parallel port which triggers an IRQ when the pin transitions
; from low to high.
;
; Because it is possible that the switch or jumper is set incorrectly, this
; function explicitly checks for a backwards IRQ in addition to checking for
; a correct IRQ.  If a backwards IRQ is found, the function returns -1.
;
; This function also checks for the possibility that the parallel port is
; connected to more than one IRQ line, and returns -2 in this case.
;
; It returns 0 if no IRQ was detected, otherwise it returns the IRQ number,
; which is in the range 2-7, 9-12 or 14-15.

		PUBLIC	_lptcap_autodetect_irq
		IF	CODEFAR
_lptcap_autodetect_irq PROC far
		ELSE
_lptcap_autodetect_irq PROC near
		ENDIF

		push	bp
		mov	bp,sp
		call	GetPortAddr	; Get parallel port address
		jnz	DetIRQCont	; If there is a port number, continue
		jmp	DetIRQExit	; If there no LPTCAP port, return zero

DetIRQCont:	mov	ax,[bp+2+CALLSIZE] ; Get irqmask parameter
		and	ax,1101111011111100b ; Ignore IRQs 0, 1, 8, 13
		cmp	T2Port,62h	; Test for PC/XT
		jne	GotIRQMask	; If not
		xor	ah,ah		; If so, don't look for IRQs 8-15
GotIRQMask:	mov	IRQMask,ax	; Save it
		mov	InvIRQMask,ax	; Store to inverted mask too

		pushf			; Preserve interrupt flag
		cli			; Lock out interrupts for a while
		mov	al,DataValue
		and	al,NOT Data_RESETB ; Bring -RESETB low
		mov	dx,PortBase
		out	dx,al
		@Delay
		mov	al,ContValue
		or	al,(Cont_IRQEN OR Cont_STROBE) ; Enable IRQ buffer
		inc	dx		;   and force -STROBE low
		inc	dx		; Increment up to control port address
		out	dx,al
		dec	dx
		dec	dx		; Back to data register

		in	al,21h		; Get primary PIC IMR
		mov	PIC0IMRSave,al	; Save it
		in	al,0A1h		; Get secondary PIC IMR
		mov	PIC1IMRSave,al	; Save it too

		mov	ax,IRQMask	; Get IRQs to be tested
		not	ax		; Convert to 0 = enable for PIC IMR
		and	al,PIC0IMRSave	; Enable desired interrupts
		out	21h,al		; Set primary PIC IMR
		mov	al,ah		; Get high IRQ mask
		and	al,PIC1IMRSave	; Enable desired interrupts
		out	0A1h,al		; Set secondary PIC IMR

; Loop IDETLOOPS times, testing alternately for IRQ signals which are active
; when -RESETB is set inactive, and inactive when -RESETB is driven active.
; On each loop, turn off bits in IRQMask which do not meet the requirement.
; At the end of the loop, IRQMask contains 1-bits for the IRQ(s) driven by
; the LPTCAP parallel port.

		mov	cx,IDETLOOPS	; Number of tests
		xor	bx,bx		; Zero flip-bits
TryIRQLoop:	mov	al,bl		; Get flip-bits
		or	al,NOT Data_RESETB ; Set all bits except -RESETB
		and	al,DataValue	; Turn off 0-bits from DataValue
		out	dx,al		; Set data register
		mov	al,0Ah		; Command to select IRR for reading
		out	0A0h,al		; Send to secondary PIC
		out	20h,al		; Send to primary PIC
		@Delay
		cmp	cl,IDETLOOPS	; Are we on the first loop?
		jae	SkipThis	; If not, don't update
		in	al,0A0h		; Read secondary PIC IRR
		mov	ah,al		; Keep in AH
		in	al,20h		; Read primary PIC IRR
		xor	ax,bx		; Flip bits if -RESETB high
		and	InvIRQMask,ax	; Update inverted-IRQ mask
		not	ax		; Get 1-bits for IRR bit == NOT -RESETB
		and	IRQMask,ax	; Retain bits with matching IRR bits
SkipThis:	not	bx		; Flip flip-bits
		loop	TryIRQLoop	; Loop

; Reinstate original PIC IMR values and restore interrupt flag

		mov	al,PIC0IMRSave
		out	21h,al
		mov	al,PIC1IMRSave
		out	0A1h,al

		mov	al,ContValue
		inc	dx
		inc	dx		; Increment up to control port address
		out	dx,al		; Write normal control register value
		@Delay
		dec	dx
		dec	dx
		mov	al,DataValue
		and	al,NOT Data_RESETB ; Activate -RESETB
		out	dx,al
		@Delay
		or	al,Data_RESETB	; Raise it again
		out	dx,al		; Write normal data register value
		@Delay			; Give time for INTR to go inactive
		popf			; Restore interrupt flag

		cmp	InvIRQMask,0	; Get any inverted IRQs?
		mov	ax,-1		; Prepare for yes
		jnz	DetIRQExit	; If so, exit

		mov	ax,IRQMask	; Get IRQ(s) driven by LPTCAP port
		test	ax,ax		; Get any?
		jz	DetIRQExit	; If not, exit

		mov	dx,ax		; Value to DX
		neg	ax		; Get minus value
		and	ax,dx		; Get value AND (minus value)
		xor	ax,dx		; Turn off the lowest 1-bit
		mov	ax,-2		; Prepare for error
		jnz	DetIRQExit	; If there are more 1-bits - conflict!

		mov	ax,-1		; Pre-initialise bit counter
FindIRQNLoop:	inc	ax		; Increment bit number
		shr	IRQMask,1	; Shift bit out
		jnc	FindIRQNLoop	; Loop until we get a 1-bit

DetIRQExit:	pop	bp
		ret
_lptcap_autodetect_irq ENDP

;-------------------------------------------------------------------------------

; int lptcap_intmode_install(unsigned int irqnum, lptcap_bufdescriptor * bdp)
;
; Install and enable interrupt-driven reception.  Returns 1 if successful or 0
; if error (no LPTCAP port, unacceptable irqnum value, or already installed in
; interrupt mode).  Acceptable values for a PC or PC/XT are 2, 3, 4, 5, 6, 7
; and for an AT or later machine, 3, 4, 5, 6, 7, 9, 10, 11, 12, 14, 15.

		PUBLIC	_lptcap_intmode_install
		IF	CODEFAR
_lptcap_intmode_install PROC far
		ELSE
_lptcap_intmode_install PROC near
		ENDIF

		push	bp
		mov	bp,sp
		cmp	IRQNum,0	; Already installed in interrupt mode?
		jnz	IntInstErr	; If so
		call	GetPortAddr	; Get parallel port address
		jz	IntInstErr	; If there no a port number, return zero

		mov	bx,[bp+4+CALLSIZE] ; Get bufdescriptor offset
		mov	BufDescOff,bx
		IF	DATAFAR
		 mov	ax,[bp+6+CALLSIZE] ; Get bufdescriptor segment
		 mov	BufDescSeg,ax
		 mov	es,ax
		 mov	WORD PTR es:[bx+BD_TAIL],0 ; Init head and tail pointers
		 mov	WORD PTR es:[bx+BD_HEAD],0
		ELSE
		 mov	BufDescSeg,ds
		 mov	WORD PTR ds:[bx+BD_TAIL],0 ; Init head and tail pointers
		 mov	WORD PTR ds:[bx+BD_HEAD],0
		ENDIF
		mov	ax,[bp+2+CALLSIZE] ; Get irqnum parameter
		cmp	T2Port,62h	; Test for PC/XT
		jne	CheckNumAT	; If not
		cmp	ax,8		; If PC or PC/XT check for irqnum > 7
		jae	IntInstErr	; If so
		cmp	al,2		; Check for irqnum < 2
		jae	GoodIRQNum	; If alright
IntInstErr:	xor	ax,ax
		jmp	SHORT IntInstExit ; Exit with a zero return code

CheckNumAT:	cmp	ax,16		; Check for irqnum > 15
		jae	IntInstErr	; If so
		cmp	al,3		; Check for irqnum < 3
		jb	IntInstErr	; If so
		cmp	al,8		; Check for irqnum == 8
		je	IntInstErr	; If so
		cmp	al,13		; Check for irqnum == 13
		je	IntInstErr	; If so

GoodIRQNum:	mov	IRQNum,al	; Store IRQNum
		cmp	al,8
		jb	GotIntNum1	; If low IRQ, IRQ0-7 --> INT 8-15
		add	al,60h		; If high IRQ, IRQ8-15 --> INT 70h-77h
GotIntNum1:	add	al,8		; IRQ0 is INT 8
		mov	ah,35h
		int	21h		; Get old interrupt handler
		mov	LPTIntOff,bx
		mov	LPTIntSeg,es	; Store it
		push	ds
		push	cs
		pop	ds
		mov	dx,OFFSET LPTCAP_IRQHnd
		mov	ah,25h
		int	21h		; Set new interrupt handler
		pop	ds

		pushf
		cli
		in	al,0A1h		; Get secondary PIC IMR
		mov	[OldPIC1IMR],al	; Store
		in	al,21h		; Get primary PIC IMR
		mov	[OldPIC0IMR],al	; Store

		call	EnableLPTInt	; Enable interrupt in PIC(s)

		call	GetPortAddr	; Get parallel port address again

		or	ContValue,Cont_IRQEN ; Turn on IRQ enable
		mov	al,ContValue
		inc	dx
		inc	dx		; To control register
		out	dx,al		; Set control register with IRQ enabled

		call	TestLatched	; New data available?
		jz	NotPending	; If not
		call	StuffBuf	; Capture byte and stuff it into buffer
NotPending:	popf			; Restore interrupt flag
		mov	ax,1		; Return 1 - successful
IntInstExit:	pop	bp
		ret
_lptcap_intmode_install ENDP

;-------------------------------------------------------------------------------

; void lptcap_intmode_uninstall(void)
;
; Uninstall interrupt handler, disable interrupt-driven receive mode, disable
; parallel port interrupt.  This returns the LPTCAP system to polled mode.
; Any data in the circular buffer when this function is called is lost.

		PUBLIC	_lptcap_intmode_uninstall
		IF	CODEFAR
_lptcap_intmode_uninstall PROC far
		ELSE
_lptcap_intmode_uninstall PROC near
		ENDIF

		cmp	IRQNum,0	; Currently installed in interrupt mode?
		jz	IntUninstRet	; If not
		call	GetPortAddr	; Get parallel port address
		jz	IntUninstRet	; If there no a port number, return

; Restore PIC IMRs

		mov	ax,101h		; Set a bit in both bytes
		pushf
		cli
		mov	cl,IRQNum	; Get IRQ number
		cmp	cl,8
		jb	LowIRQ1		; If not a high IRQ
		shl	ax,cl		; Get one bit set in AH
		test	ah,[OldPIC1IMR]	; Was it enabled before we started?
		jz	RestoredPICs	; If so, don't change it
		in	al,0A1h		; Get secondary PIC IMR
		or	al,ah		; Disable the IRQ
		out	0A1h,al		; Set it back
		jmp	SHORT RestoredPICs ; Continue
LowIRQ1:	shl	ah,cl		; Shift to appropriate bit
		test	ah,[OldPIC0IMR]	; Was it enabled before we started?
		jz	RestoredPICs	; If so, don't change it
		in	al,21h		; Get primary PIC IMR
		or	al,ah		; Disable the IRQ
		out	21h,al		; Set it back

; Turn off interrupt enable in parallel port

RestoredPICs:	call	GetPortAddr	; Get parallel port address again
		and	ContValue,NOT Cont_IRQEN ; Turn off IRQ enable
		mov	al,ContValue
		inc	dx
		inc	dx		; To control register
		out	dx,al		; Set control register with IRQ disabled

; Restore interrupt vector

		popf
		mov	al,IRQNum	; Get IRQNum
		cmp	al,8
		jb	GotIntNum2	; If low IRQ, IRQ0-7 --> INT 8-15
		add	al,60h		; If high IRQ, IRQ8-15 --> INT 70h-77h
GotIntNum2:	add	al,8		; IRQ0 is INT 8
		mov	ah,25h
		push	ds
		mov	dx,LPTIntSeg
		mov	ds,dx
		mov	dx,LPTIntOff
		mov	ah,25h
		int	21h		; Restore old interrupt handler
		pop	ds
		mov	IRQNum,0	; Indicate we're in polled mode

IntUninstRet:	xor	ax,ax
		ret
_lptcap_intmode_uninstall ENDP

;-------------------------------------------------------------------------------

		IF	CODEFAR
LPTCAP_TEXT	 ENDS
		ELSE
_TEXT		 ENDS
		ENDIF

		END
