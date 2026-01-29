; chunky_test.asm - Test program for chunky pixel display
;
; Displays the demo.bin cube using multicolor character mode.

        .include "macros.asm"

; ============================================================================
; C64 PRG header
; ============================================================================
        * = $0801

        ; BASIC stub: SYS <main>
        .word (+), 2024
        .null $9e, format("%d", main)
+       .word 0

; ============================================================================
; Main program
; ============================================================================
main
        ; Initialize VIC-II for chunky pixel mode
        jsr vic2_init

        ; Load the demo buffer to screen
        jsr load_demo_screen

        ; Infinite loop - just display
-       jmp -

; ============================================================================
; Include VIC-II setup and charset
; ============================================================================
        .include "vic2.asm"
