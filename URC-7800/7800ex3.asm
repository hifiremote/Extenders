; recreation of the 7800EX2 hex in the JP1 files section originally done by John Fine
; assemble: S3c8asm 7800ex3.asm -l7800ex3.lst -a7800ex3.hex

;  by Bill Jackson (unclemiltie)
; 
; Change log
; 9-jan-2007 	<egd>	changed popWAWB from $255 to 225
; 9-JAN-2007 	<egd> 	added default macros data bytes - need definitions to be built
; 9-JAN-2007 	<wmj> 	added lots of detail on entry points from John, more comments
;10-JAN-2007 	<wmj> 	fixed signature "X" ASCII code, discovered by <egd>
;			added blink entry point definitions for debugging
;			fix definition of R_maclim 
;			add computation of pseudo-device selection keys and initial macros
;			verified that this version assembles to match EXACTLY ex2 hex file 

; Assembler directives and their meaning

;		xorg	x			;set address of EEPROM to x
;		org	x			;set address of RAM to x
;		x = $$				;set variable x to current EEPROM address
;		x = $				;set variable x to current RAM address

		Sig		= 02		;signature area
		oldKM		= 1A		;address of old keymove area
		newKM		= 0400		;address of new keymove area
		Upgrade		= 0100		;address of new upgrade area
		oldLRN		= 03FF		;old learned area
		RAM		= 8000		;address of RAM in this remote

		PIPonoff	= 2B		;PIP on/off key
		PIPmove		= 2D		;PIP move key
		Shiftkey 	= 02		;initial shift  key
		Pseudokey	= V_+_CBL	;lowest of pseudo-device selection keys

		CBL		= 09		;device keys
		TV		= 01
		VCR		= 0A
		DVD		= 22
		RCV		= 11
		AUX		= 14
		CD		= 21

		R_SearchKey	= R44		;search key for macro/keymove EEPROM search
		R_Device	= R5E		;current device
		R_macptr	= R61		;macro pointer
		R_maclim	= R62		;macro buffer limit
		R_macbuf	= R63		;
		R_Key1		= R75		;debounced key from keypad scan
		R_Key		= R77		;current key being processed
		R_Closures	= R78		;number of keys pressed on keypad scan
		R_IFlags	= R7B		;interrupt flags
		R_Devtable	= RB8		;table of devices
		R_DevV		= RB8		;volume device
		R_DevT		= RB9		;transport device
		R_DevP		= RBA		;PIP device
		R_DevM		= RBB		;menu device
		R_Shiftbits	= RBC		;shift bits

		PopWBWA		= 0225		;POP WB/WA from stack, return
		SearchAdvCode	= 054D		;search for an advance code in EEPROM (KM, Macro)
		LoadMacro	= 065E		;load macro found in EEPROM into macro buffer
		CheckVolKeys	= 11B0		;check if key in volume keyset	
		CheckTransKeys	= 11B4		;check if key is in transport keyset
		ReadKeyDebounced= 12E8		;read debounced key
		WaitNoKeys	= 1360		;wait for no keys pressed
		LEDon		= 1423		;turn LED on
		LEDoff		= 1427		;turn LED off
		Read255		= 1683		;read 255 bytes from EEPROM then execute

		Blink		= 13D8		;Blink (if not in macro)
		Blink2		= 13EA		;Blink LED twice (if not in macro)
		BlinkW2		= 13EC		;Blink LED W2 times (if not in macro)
		BlinkMacro	= 13DD		;Blink LED even if in macro



		Xorg	oldKM			;old keymove area, keymove to load extender
		org 	oldKM
		db	03			;power key
		db	23			;2=keymove, 3=length of keymove
		dw	1708			;1=TV, $708=1800
		db	0			;hex for key
		db	0			;end of keymove
		ee_start = $$			;extender can start just after end of keymove to load extender

		xorg	Sig			;signature area
		org 	Sig
		db	43,37,4C,30,58,37,4C,33	;C7L0X7L3 - extender variant 3

		xorg	oldLRN			;terminate old learned area
		org	oldLRN
		db	0


; define phantom codes for device selection.  These must be contiguous with no other defined keys with
; higher value.  If you change the location of these keys, you have to change the offset into RB8 
; that is used to process the pseudo-device keys (see the code on how this works and how to compute the offset
; the offsets for $100 and $80 are here if you want to use them

		Ph_Start	= 100		;upper limit of pseudo-device keys
		offset		=  1C		;used in pseudo device processing (must match Ph_start)

;		Ph_STart	= 80		;upper limit of pseudo-device keys
;		offset		= 0C		;used in pseudo device processing (must match ph_start)

		M_		= Ph_Start - 08	;define base address for HT keysets
		P_		= M_ - 08
		T_		= P_ - 08
		V_		= T_ - 08	
 	

		_CD		= _AUX + 1	;define offsets within HT keysets for devices
		_AUX		= _RCV + 1
		_RCV		= _VCR + 1
		_VCR		= _DVD + 1
		_DVD		= _TV  + 1
		_TV		= _CBL + 1
		_CBL		= 0

		xorg	newKM			;load the default macros to make the remote work
		org	newKM

;			Key	t/l	Menu     Volume   Transp   PIP
		db	CBL,    14,	M_+_CBL, V_+_CBL, T_+_CBL, P_+_CBL
		db	TV,     14,	M_+_TV,  V_+_TV,  T_+_TV,  P_+_TV
		db	VCR,    14,	M_+_VCR, V_+_VCR, T_+_VCR, P_+_VCR
		db	DVD,    14,	M_+_DVD, V_+_DVD, T_+_DVD, P_+_DVD
		db	RCV,    14, 	M_+_RCV, V_+_RCV, T_+_RCV, P_+_RCV
		db	AUX,    14,	M_+_AUX, V_+_AUX, T_+_AUX, P_+_AUX
		db	CD,   	14, 	M_+_CD,  V_+_CD,  T_+_CD,  P_+_CD
		db 	0



;this is not nearly as elaborate as the regular extenders, they compute all of these addresses depending on 
;the number of devices and protocols installed, but this will give you an idea of what the protocol table 
;and device table looks like in the upgrade area.  In general, all of the devices are installed starting at 
;$0104 then all of the protocols are installed after that, then the device and protocol tables are built
;to point to those.  Finally the first 2 words in the upgrade area are filled in with the addresses of the 
;device and protocol tables.


		xorg	Upgrade			;build the upgrade tables
		org 	Upgrade	
		dw	devtbl			;pointer to start of device table
		dw	prottbl			;pointer to start of protocol table

		dev1= $$			;save address of first device
		db	80			;protocol ID (lower byte)
		db	00,01			;can't remember what this is

		proto1= $$			;save address of first protocol
		db	00,00,01		;protocol header
		LDW	RCA,#0020		;address of extender in EEPROM
		CALL	Read255			;read extender from EEPROM to RAM and then execute it

		devtbl = $$			;device table
		db	00			;?
		db	01			;number of devices
		dw	1F08			;TV 1800, protocol > 128?
		dw	dev1			;address of device in EEPROM
		db	0			;end of device table

		prottbl = $$-1			;protocol table
		db	01			;number of protocols
		dw	0180			;protocol ID
		dw	proto1			;address of protocol in EEPROM
		db	C6			;?
		db	00			;end of protocol table




;the distributed ex2 extender hex has a lot more in the upgrade area but it has been terminated so IR 
;doesn't show any more devices or protocols.  This may be an artifact of the original design work
;and/or debugging or something else.  I have not tried to recreate it here


		Xorg	ee_start		;start of extender in EEPROM
		org	RAM			;address of RAM

Start:		CALL	LEDon			;turn LED on
Wait:		EI				;enable interrupts 
		LD	RFB,#A5			;enable stop
		STOP				;STOP the processor and wait for an interrupt
		NOP
		NOP
		DI				;disable further interrupts
		TM	R_IFlags,#80		;check interrupt flags for keypress
		JREQ	Wait			;no keypress, go back and wait
		CALL	ReadKeyDebounced	;read the keypad, debounced		
		CP	R_Closures,#01		;one key pressed?
		JRNE	S2			;clean up and go back to start
		LD	W1,R_Key1		;probably the debounced key
		CP	RC1,Shiftkey		;shift?
		JRNE	KeyProcess		;no, process the key
		LD	R_Shiftbits,#80		;load shift bits
Done:		CALL	LEDoff			;turn LED off
		JR	ReEntry

KeyProcess:	LD	R_Key,W1		;get current key
		LD	RC0,W1			
		AND	RC0,#07			;mask off device within keyset (for pseudo key processing)
		CP	RC1,Pseudokey		;is key a pseudo device control key?
		JRNC	Pseudo			;yes, go process it

						;this block processes the regularkeys.  First determine 
						; which keyset (0=Volume, 1=transport, 2=PIP and 3=Menu) 
Regular:	CLR	RC2			;start with keyset 0 (Volume)
		CALL	CheckVolKeys		;is key in the volume keyset?
		JRC	SetDev			;yes, set device, keyset=volume
		INC	W2			;no, increment keyset 
		CALL	CheckTransKeys		;is key in the transport keyset?
		JRC	SetDev			;yes, set device, keyset=transport

		INC	W2			;keyset = PIP
		CP	R_Key,PIPonoff		;key less than PIP on/off?
		JRC	MenuSet			;yes, not part of PIP set, skip to set keyset=menu
		CP	R_Key,PIPmove		;key less  than PIP move?
		JRULE	SetDev			;yes, sset device, keyset=PIP
MenuSet:	INC	W2			;set device, keyset=Menu (the default choice if not found anywhere else)

SetDev:		LD	W2,R_Devtable[W2]	;load device index from table at RB8 based on keyset 
		LD	R_Device,W2		;set the current device to match the device index for this keyset
		LD	R_SearchKey,#40		;is #40 a special key of some sort to search for?
		AND	R00,#CF			;turn off R00.4 (keymove flag) and R00.5 (macro flag)
		CALL	0717
		LD	R_SearchKey,R_Key	;load key for search of EEPROM
		XOR	R_SearchKey,R_Shiftbits	;put in the shift bits
		CLR	R_Shiftbits		; and then clear the shift bits
		INC	R4D
		LDW	RCA,newKM		;address of new Advance code area
SearchAdv:	CALL	SearchAdvCode		;search EEPROM for an advance code
		JRC	MacFound		;ROM entries usually signal success with carry set, so this is probably found adv code
		ADD	W0,W0			;W0=0 probably signals that we hit the end so no key found
		JRNE	SearchAdv		;search again
MacFound:	JRNE	LoadMac			;load the macro that we just found

		CALL	Reload			;process the key and then reload the extender
ReEntry:	DEC	R_Closures		;if anything but 1, this was the last key in a macro
		JRGT	NextMac			;get next key in macro and process
S2:		CALL	WaitNoKeys		;wait for no more keys to be pressed		
		JR	Start

		db	FF,FF,FF,FF,FF,FF,FF	;don't know what this is, but it was in the original extender hex

						;this block processes the pseudo device keys, sets the device
						;into a block of device ID's.  clever trick to build an offset to 
						;put this into the RB8 table! 
						;W0=device within set, W1=keyset (ie: Volume)
Pseudo:		SUB	W1,W0			;strip device
		SWAP	RC1			;get most of the keyset into lower nibble
		RL	RC1			;rotate what was bit 3 into bit 0 to make offset
		LD	R_Devtable-offset[W1],W0	;save the device into the RB8 table (clever trick)
		JR	Done			;done changing device, turn off LED and reload extender


LoadMac:	CALL	LoadMacro		;load the macro into the macro buffer
NextMac:	LD	W0,R_macptr		;get current macro pointer
		LD	W1,R_macbuf[W0]		;get key from macro buffer
		INC	R_macptr		;increment macro pointer
		CP	R_macptr,R_maclim	;was this the last key?
		JRNC	KeyProcess		;no, go process the key
		LD	R_Closures,#02		;signal done with macro processing
		JR	KeyProcess		;go process the next key


Reload:		LDW	RC2,Read255		;address of Read255
		PUSH	RC3
		PUSH	RC2
		LDW	RC2,ee_start		;address of extender in EEPROM
		PUSH	RC2
		PUSH	RC3	
		LDW	RC2,PopWBWA		;address of POPWBWA
		PUSH	RC3
		PUSH	RC2
		LDW	RC2,#10B2		
		PUSH	RC3
		PUSH	RC2

		JP	072A			;go process the key then reload the extender via unwinding the stack

		db	FF,FF,FF,FF,FF,FF,FF,FF
		db	FF,FF,FF,FF,FF,FF,FF,FF,FF,FF,FF,FF,FF,FF,FF,FF


; check this to see that we don't go past $FF in the EEPROM since upgrades start at $100
		endEEPROM=$$-1

	

; the above loads and pushes are used because the calls into the ROM wipe out RAM, so the only way back is to 
; load "entry points" onto the stack so that the RET instructions from the ROM execute those entry points
; the entry points POP the address of the extender into registers and then reloads the extender from EEPROM
; it takes a while to figure this out, but it is very clever.

; Since Reload was called just before "ReEntry", the last return address will be on the stack and will be the entry point
; when the extender reloads

