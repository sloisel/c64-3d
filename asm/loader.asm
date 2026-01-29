; loader.asm - Loads MAIN and jumps to it
;
; Build: 64tass -o loader.prg loader.asm
;
; This is a small BASIC-loadable program that loads the main
; program (MAIN) from disk and jumps to its entry point.

        * = $0801

; BASIC stub: 10 SYS2061
        .word (+), 10
        .null $9e, format("%d", start)
+       .word 0

start

; Loader code starts at $080d = 2061
        lda #1              ; logical file 1
        ldx #8              ; device 8 (disk)
        ldy #1              ; secondary address 1 (use file's load address)
        jsr $ffba           ; SETLFS

        lda #(filename_end - filename)
        ldx #<filename
        ldy #>filename
        jsr $ffbd           ; SETNAM

        lda #0              ; 0 = load (not verify)
        jsr $ffd5           ; LOAD

        jmp $3800           ; Jump to main entry point

filename
        .text "MAIN"
filename_end
