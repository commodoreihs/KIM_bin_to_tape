* = $0401
;
; KIM-1 binary-to-tape transmitter for the PET (BASIC 4).
; This runs on a Commodore PET and virtually "plays" a program
; for the KIM-1 to load from audio cassette.
; 
; PET Requirements:
;  - Must be running BASIC 4
;  - Must have a user port connector
;  - Doesn't seem to work on PETs with an internal speaker
;
; The KIM-1 code is copied directly and exactly from the KIM-1
; user manual. The only changes were to use a 6522 VIA instead
; of the 6530 RRIOT in the KIM-1.
; 
; The BASIC 4 PET disk load routine was mostly stolen from the book
; "Programming the PET/CBM" by Raeto Collin West.
; 
; I wrote the first version of this on May 11, 2022 and showed
; the concept in a YouTube video "The gory details: how saving to
; tape from a KIM-1 single board computer works"
; 
; That version only transmitted a small, hard-coded string. This
; updated version was written April 25, 2026, and allows you to
; transmit any random file.
;
; Dave McMurtrie <dave@commodore.international> - April 27, 2026

; BASIC loader
.byte $0B,$04                 ; link to next line ($040B = EOP)
.byte $0A,$00                 ; line number 10
.byte $9E                     ; SYS token
.text "1037"                  ; SYS argument as ASCII digits
.byte $00                     ; end of line
.byte $00,$00                 ; end of program 

; PET BASIC 4 zero-page parameters expected by the LOAD subroutine.
FNLEN_ZP    = $D1             ; length of filename
FILENAME_PTR = $DA            ; pointer to filename ($DA-$DB)
DEVNUM      = $D4             ; device number (8 = disk)
LFFLAG      = $9D             ; 0 = LOAD, 1 = VERIFY
ST_ZP       = $96             ; KERNAL status byte (clear before call,
                              ;   read after for error check)
                              ; ($D1-$D4 are the standard PET file
                              ;  parameter block: $D2 = logical file,
                              ;  $D3 = secondary addr, $D4 = device.
                              ;  $9D is the LOAD/VERIFY flag.)

; PET BASIC 4 ROM entry points
; We use the override-LOAD path so that headerless .BIN files (which
; have no 2-byte load address up front) load correctly into our buffer.
; The PET-side buffer is fixed at $4000. The KIM-side load address is
; entered by the user at runtime and goes only into the tape header.
SEND_NAME   = $F4A5           ; send name to IEEE (BASIC 2: $F466)
SEND_TALK   = $F0D2           ; send TALK         (BASIC 2: $F0B6)
SEND_SECOND = $F193           ; send secondary address (BASIC 2: $F128)
GET_BYTE    = $F1C0           ; get byte from IEEE (BASIC 2: $F18C)
ABORT_FNF   = $F3C1           ; abort, ?FILE NOT FOUND (BASIC 2: $F56E)
REJOIN_LOAD = $F391           ; rejoin LOAD body  (BASIC 2: $F355)
CHROUT      = $FFD2
GETIN       = $FFE4

; KERNAL's I/O start-address pointer ($FB-$FC). Normally LOAD reads
; the file's first 2 bytes into here. We set it ourselves to override.
; After LOAD completes, ($FB) points one past the last byte stored.
IOSTART     = $FB

; PET-side buffer for the loaded file.
BUFFER      = $4000

; Variables
CHKL        = $0A00           ; checksum low
CHKH        = $0A01           ; checksum high
SAVX        = $0A02           ; saved X (and Y at SAVX+1) during OUTCHT
VEB         = $0A05           ; dynamic LDA target (4 bytes)
LOADAL      = $0A0A           ; KIM-side load addr (lo) for tape header
LOADAH      = $0A0B
ENDAL       = $0A0C           ; one past last byte (lo)
ENDAH       = $0A0D
FNAMELEN    = $0A0E
LINEBUF     = $0A0F           ; filename input buffer
LINEBUFMAX  = 16              ; CBM filenames max 16 chars

; PET 6522 VIA registers (user port)
ACR         = $E84B
PCR         = $E84C
IER         = $E84E
IFR         = $E84D
T1L         = $E844
T1H         = $E845

; KIM tape ID. The KIM-1 side ($17F9) must match this (or be 00 = wildcard).
ID          = $01

; Main entry. 
START
                ; Prompt for KIM-side load address (4 hex digits)
                lda     #<ADDRPROMPT
                sta     PRSTR_LDA+1
                lda     #>ADDRPROMPT
                sta     PRSTR_LDA+2
                jsr     PRSTR
                jsr     READLINE
                cmp     #4              ; need exactly 4 hex digits
                beq     ADDROK
                rts
ADDROK

                ; Parse 4 hex chars
                lda     LINEBUF
                jsr     HEX2NIB
                asl
                asl
                asl
                asl
                sta     LOADAH
                lda     LINEBUF+1
                jsr     HEX2NIB
                ora     LOADAH
                sta     LOADAH

                lda     LINEBUF+2
                jsr     HEX2NIB
                asl
                asl
                asl
                asl
                sta     LOADAL
                lda     LINEBUF+3
                jsr     HEX2NIB
                ora     LOADAL
                sta     LOADAL

                ; Prompt for filename
                lda     #<FNPROMPT
                sta     PRSTR_LDA+1
                lda     #>FNPROMPT
                sta     PRSTR_LDA+2
                jsr     PRSTR
                jsr     READLINE
                sta     FNAMELEN
                bne     FNAMEOK
                rts
FNAMEOK

                ; Set up KERNAL parameters
                lda     FNAMELEN
                sta     FNLEN_ZP
                lda     #<LINEBUF
                sta     FILENAME_PTR
                lda     #>LINEBUF
                sta     FILENAME_PTR+1
                lda     #8
                sta     DEVNUM
                lda     #0
                sta     LFFLAG          ; load (not verify)
                sta     ST_ZP           ; clear status

                ; Override: file gets stored at PET BUFFER ($4000),
                ; regardless of whatever the file's "first 2 bytes"
                ; might happen to be (since for a raw .BIN they are
                ; data, not a load address).
                lda     #<BUFFER
                sta     IOSTART
                lda     #>BUFFER
                sta     IOSTART+1

                ; Secondary address byte = $60 (channel 0).
                lda     #$60
                sta     $D3
                jsr     SEND_NAME       ; send OPEN + name + UNLISTEN
                jsr     SEND_TALK       ; tell drive to TALK
                lda     $D3
                jsr     SEND_SECOND     ; send secondary address

                jsr     GET_BYTE        ; first byte from file
                pha
                lda     ST_ZP           ; check ST after first read:
                lsr                     ;   bit 1 = timeout/no file
                lsr
                bcs     LOADERR
                pla
                jsr     STBUF           ; store first byte, advance

                jsr     GET_BYTE        ; second byte
                jsr     STBUF

                jsr     REJOIN_LOAD     ; soak up rest of file into ($FB)

                ; Capture end-of-load pointer for transmit
                lda     IOSTART
                sta     ENDAL
                lda     IOSTART+1
                sta     ENDAH

                ; Configure VIA and transmit
                sei                     ; requires cycle-exact timing for transmit
                lda     ACR             ; T1 free-running, SR off
                and     #%01100011
                ora     #%01000000
                sta     ACR
                lda     #$00
                sta     IER             ; disable VIA interrupts

                jsr     DUMPT

EXIT            rts                     ; back to BASIC

; LOADERR: discard the saved byte and let BASIC's error handler print
; "?FILE NOT FOUND ERROR".
LOADERR         pla
                jmp     ABORT_FNF

; store .A at (IOSTART), advance IOSTART by 1.
STBUF           ldy     #0
                sta     (IOSTART),y
                inc     IOSTART
                bne     STBUF1
                inc     IOSTART+1
STBUF1          rts

; HEX2NIB: convert ASCII hex char in A to nibble in A.
HEX2NIB         sec
                sbc     #$30            ; subtract '0'
                cmp     #$0A
                bcc     HEX2N1          ; was a digit, done
                sec
                sbc     #$07            ; was a letter, additional adjustment
HEX2N1          rts

; DUMPT - init volatile execution block
; dump mem to tape (code taken directly from the original 
; KIM-1 sources) with only the changes necessary to work with
; a 6522 VIA instead of the KIM-1's 6530. So, timer and pin
; differences.
DUMPT           lda     #$AD            ; Load absolute inst
                sta     VEB
                jsr     INTVEB

                ldx     #100
DUMPT1          lda     #$16            ; sync chars
                jsr     OUTCHT
                dex
                bne     DUMPT1

                lda     #$2A            ; start char
                jsr     OUTCHT

                lda     #ID             ; tape ID byte
                jsr     OUTBT

                lda     LOADAL          ; destination address
                jsr     OUTBTC
                lda     LOADAH
                jsr     OUTBTC

DUMPT2          lda     VEB+1
                cmp     ENDAL
                lda     VEB+2
                sbc     ENDAH
                bcc     DUMPT4

                lda     #$2F            ; end-of-data char
                jsr     OUTCHT
                lda     CHKL
                jsr     OUTBT
                lda     CHKH
                jsr     OUTBT

                ldx     #2
DUMPT3          lda     #4              ; EOT chars
                jsr     OUTCHT
                dex
                bne     DUMPT3
                cli
                rts

DUMPT4          jsr     VEB             ; LDA byte
                jsr     OUTBTC
                jsr     INCVEB
                jmp     DUMPT2

; INTVEB: init VEB to "LDA BUFFER : RTS", clear checksum.
; copied from the original KIM-1 sources
INTVEB          lda     #<BUFFER
                sta     VEB+1
                lda     #>BUFFER
                sta     VEB+2
                lda     #$60            ; RTS
                sta     VEB+3
                lda     #0
                sta     CHKL
                sta     CHKH
                rts

; INCVEB: advance VEB's address operand by 1.
; copied from the original KIM-1 sources
INCVEB          inc     VEB+1
                bne     INCVE1
                inc     VEB+2
INCVE1          rts

; CHKT: A -> running checksum, A preserved.
; copied from the original KIM-1 sources
CHKT            tay
                clc
                adc     CHKL
                sta     CHKL
                lda     CHKH
                adc     #0
                sta     CHKH
                tya
                rts

; OUTBTC: A -> 2 ASCII hex chars + checksum
; OUTBT:  A -> 2 ASCII hex chars (no checksum)
; copied from the original KIM-1 sources
OUTBTC          jsr     CHKT
OUTBT           tay
                lsr
                lsr
                lsr
                lsr
                jsr     HEXOUT          ; output MSD
                tya
                jsr     HEXOUT          ; output LSD
                tya
                rts

; HEXOUT: convert LSD of A to ASCII
; copied from the original KIM-1 sources;
HEXOUT          and     #$0F
                cmp     #10
                clc
                bmi     HEX1
                adc     #7
HEX1            adc     #$30

; OUTCHT: emit one ASCII char as 8 KIM-format bits via CB2.
; copied from the original KIM-1 sources
OUTCHT          stx     SAVX
                sty     SAVX+1
                ldy     #8
CHT1            jsr     ONE
                lsr
                bcs     CHT2
                jsr     ONE
                jmp     CHT3
CHT2            jsr     ZRO
CHT3            jsr     ZRO
                dey
                bne     CHT1
                ldx     SAVX
                ldy     SAVX+1
                rts

; ONE: HIGH tone (~3700 Hz), 9 cycles.
; copied from the original KIM-1 sources
ONE             ldx     #9
                pha
ONE1            lda     #126
                sta     T1L
                lda     #0
                sta     T1H
                lda     PCR             ; CB2 = 1
                ora     #%11100000
                sta     PCR
                lda     #%01000000
ONE2            bit     IFR
                beq     ONE2

                lda     #126
                sta     T1L
                lda     #0
                sta     T1H
                lda     PCR             ; CB2 = 0
                ora     #%11000000
                and     #%11011111
                sta     PCR
                lda     #%01000000
ONE3            bit     IFR
                beq     ONE3
                dex
                bne     ONE1

                pla
                rts

; ZRO: LOW tone (~2400 Hz), 6 cycles.
; copied from the original KIM-1 sources
ZRO             ldx     #6
                pha
ZRO1            lda     #195
                sta     T1L
                lda     #00
                sta     T1H
                lda     PCR
                ora     #%11100000
                sta     PCR
                lda     #%01000000
ZRO2            bit     IFR
                beq     ZRO2

                lda     #195
                sta     T1L
                lda     #00
                sta     T1H
                lda     PCR
                ora     #%11000000
                and     #%11011111
                sta     PCR
                lda     #%01000000
ZRO3            bit     IFR
                beq     ZRO3
                dex
                bne     ZRO1

                pla
                rts

; PRSTR: print null-terminated string. Caller stores its address into
; PRSTR_LDA+1/+2 first.
PRSTR           ldx     #0
PRSTR_LDA       lda     $FFFF,x         ; address patched at runtime
                beq     PRSTR_DONE
                jsr     CHROUT
                inx
                bne     PRSTR_LDA
PRSTR_DONE      rts

; READLINE: read line of input from keyboard into LINEBUF using GETIN.
READLINE        lda     #0
                sta     SAVX            ; SAVX = char count so far
RDLOOP          jsr     GETIN           ; clobbers X
                cmp     #0
                beq     RDLOOP
                cmp     #$0D
                beq     RDDONE
                cmp     #$14
                beq     RDDEL
                ldx     SAVX            ; reload count
                cpx     #LINEBUFMAX
                bcs     RDLOOP          ; buffer full, ignore char
                sta     LINEBUF,x
                inx
                stx     SAVX            ; save updated count
                jsr     CHROUT          ; clobbers X (we don't care now)
                jmp     RDLOOP
RDDEL           ldx     SAVX            ; A still = $14 from CMP
                beq     RDLOOP          ; nothing to delete
                dex
                stx     SAVX
                jsr     CHROUT          ; echo DEL (cursor back)
                jmp     RDLOOP
RDDONE          jsr     CHROUT          ; echo CR (A still = $0D)
                lda     SAVX            ; return count
                rts

; various NUL-terminated strings
ADDRPROMPT      .text   "KIM ADDR (4 HEX): "
                .byte   $00

FNPROMPT        .text   "FILENAME: "
                .byte   $00
