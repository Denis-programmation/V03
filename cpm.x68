*-----------------------------------------------------------
* Title      : CP/M
* Written by : Denis
* Date       : 2024
* Description: Une version MC68000 de CP/M 80
* Note       : Pour DBRA, vu qu'il teste le passage à -1, il faut toujours décrémenter le compteur de boucle
*-----------------------------------------------------------

    ORG    $1000
    
NUMBER_OF_DIR_ENTRIES   EQU 128
NUMBER_OF_DATA_BLOCKS   EQU 398
BLOCK_SIZE              EQU 2048    unité d'allocation indivisible
DIRECTORY_SIZE          EQU 32

OPEN_FILE       EQU 51
CREATE_FILE     EQU 52
READ_FILE       EQU 53
WRITE_FILE      EQU 54
POSITION_FILE   EQU 55
CLOSE_FILE      EQU 56

DISPLAY_STRING_WITH_CRLF:
* entry : A1 = address of string
* exit : none
    MOVEM.L D0, -(SP)
    MOVE.L  #13, D0
    TRAP    #15             execute
    MOVEM.L (SP)+, D0
    RTS

DISPLAY_STRING_WITHOUT_CRLF:
* entry : A1 = address of string
* exit : none
    MOVEM.L D0, -(SP)
    MOVE.L  #14, D0
    TRAP    #15             execute
    MOVEM.L (SP)+, D0
    RTS

DISPLAY_CHAR:
* entry : D1.B = char to display
* exit : none
    MOVEM.L D0, -(SP)
    MOVE.L  #6, D0
    TRAP    #15             execute
    MOVEM.L (SP)+, D0
    RTS

START:
    ANDI.W  #%1101111111111111, SR  switch to user mode
.S1
    LEA     COMMANDE, A1
    BSR     DISPLAY_STRING_WITHOUT_CRLF
    MOVE.L  #4, D0          read a number from keyboard
    TRAP    #15
    CMP.L   #1, D1          commande tapée
    BNE     .L10
    BSR     FORMAT_DISK
    BRA     .L90
.L10
    CMP.L   #2, D1
    BNE     .L20
    BSR     READ_DIRECTORY
    BRA     .L90
.L20
    CMP.L   #3, D1
    BNE     .L90
* export
    LEA     COMMANDE2, A1
    MOVE.L  #14, D0
    TRAP    #15
    LEA     FILE_TO_FETCH, A2
    MOVE.L  #5, D0
    MOVE.L  #12-1, D2
.LOOP1
    TRAP    #15
    MOVE.B  D1, (A2)+
    CMP.B   #$0D, D1        enter key ?
    BEQ     .L30
    DBRA    D2, .LOOP1
* transform file name
.L30
    LEA     FILE_TO_FETCH2, A3
    MOVE.L  #11-1, D2       fill file name with spaces
.LOOP2
    MOVE.B  #' ', (A3)+
    DBRA    D2, .LOOP2
    LEA     FILE_TO_FETCH, A2
    LEA     FILE_TO_FETCH2, A3
    MOVE.L  #8-1, D2
.LOOP3
    CMP.B   #'.', (A2)      try to locate the dot (separator between name and type)
    BEQ     .POINT
    BSR     CONVERT_CHAR_TO_UPPER_CASE
    MOVE.B  (A2)+, (A3)+
    DBRA    D2, .LOOP3
.POINT
    LEA     FILE_TO_FETCH2, A3
    ADDQ.L  #8, A3
    ADDQ.L  #1, A2
    BSR     CONVERT_CHAR_TO_UPPER_CASE
    MOVE.B  (A2)+, D1
    CMP.B   #$0D, D1
    BEQ     .L9
    MOVE.B  D1, (A3)+
    BSR     CONVERT_CHAR_TO_UPPER_CASE
    MOVE.B  (A2)+, D1
    CMP.B   #$0D, D1
    BEQ     .L9
    MOVE.B  D1, (A3)+
    BSR     CONVERT_CHAR_TO_UPPER_CASE
    MOVE.B  (A2)+, D1
    CMP.B   #$0D, D1
    BEQ     .L9
    MOVE.B  D1, (A3)+
.L9
    CLR.B   -(A2)
    BSR     FETCH_FILE
.L90
    BRA     .S1
.L100
    BSR     CLOSE_DISK_IMAGE
    BSR     CLOSE_OUTPUT_FILE
    SIMHALT
   

CONVERT_CHAR_TO_UPPER_CASE:
    CMP.B   #'a', (A2)
    BLT     NOT_LOWER_CASE
    CMP.B   #'z', (A2)
    BGT     NOT_LOWER_CASE
    BCLR.B  #5, (A2)        convert to upper case
NOT_LOWER_CASE
    RTS

FORMAT_DISK:
    MOVEM   D1, -(SP)
* create file
    MOVE.L  #CREATE_FILE, D0
    LEA     DISK_IMAGE, A1
    TRAP    #15
    MOVE.L  #1, D7
    TST.W   D0            success ?
    BNE     ABEND
* initialize E5
    LEA     E5, A1
    MOVE.L  #BLOCK_SIZE/4-1, D3
* création du motif de remplissage de la disquette
.LOOP1
    MOVE.L  #$E5E5E5E5, (A1)+
    DBRA    D3, .LOOP1
* write directory entries
* dans CP/M toute la zone des répertoires est remplie de E5, mais je préfère écrire une trame de répertoire à la place
    MOVE.L  #NUMBER_OF_DIR_ENTRIES-1, D3    number of directory entries 
.LOOP2
    LEA     DIRECTORY, A1
    MOVE.L  #DIRECTORY_SIZE, D2
    MOVE.L  #WRITE_FILE, D0
    TRAP    #15
    MOVE.L  #2, D7
    TST.W   D0            success ?
    BNE     ABEND
    DBRA    D3, .LOOP2
* initialize data blocks (comme dans CP/M)
    LEA     E5, A1
    MOVE.L  #WRITE_FILE, D0
    MOVE.L  #BLOCK_SIZE, D2
    MOVE.L  #NUMBER_OF_DATA_BLOCKS-1, D3
.LOOP3
    MOVE.L  #WRITE_FILE, D0
    TRAP    #15
    MOVE.L  #3, D7
    TST.W   D0
    BNE     ABEND
    DBRA    D3, .LOOP3
* close file
    BSR     CLOSE_DISK_IMAGE
    LEA     FORMAT_DONE, A1
    BSR     DISPLAY_STRING_WITH_CRLF
    MOVEM   (SP)+, D1
    RTS

OPEN_DISK_IMAGE:
    TST.L   FID_CPM
    BNE     .DEJA_OUVERT
    LEA     DISK_IMAGE, A1  filename of disk image
    MOVE.L  #OPEN_FILE, D0
    TRAP    #15
    MOVE.L  #4, D7
    TST.W   D0            success ?
    BNE     ABEND
    ORI.B   #$F0, D1
    MOVE.L  D1, FID_CPM
.DEJA_OUVERT
    RTS

READ_DISK_IMAGE:
    MOVE.L  #READ_FILE, D0
    MOVE.L  FID_CPM, D1
    ANDI.B  #$F, D1
    TRAP    #15
    MOVE.L  #5, D7
    TST.W   D0            succès ?
    BNE     ABEND
    RTS

CLOSE_DISK_IMAGE:
    MOVE.L  #CLOSE_FILE, D0
    MOVE.L  FID_CPM, D1
    BEQ     .NOT_OPENED
    ANDI.B  #$F, D1
    TRAP    #15
    MOVE.L  #6, D7
    TST.W   D0            success
    BNE     ABEND
    CLR.L   FID_CPM
.NOT_OPENED
    RTS

READ_DIRECTORY:
* declare all blocks unallocated
* la FAT est une bitmap, c'est-à-dire 1 bit par bloc
* pour simplifier : je suppose que toutes les entrées de répertoire d'un même fichier se suivent
*  et qu'il n'y a pas une autre qui traine plus loin
    MOVEM.L D0-A6, -(SP)
    LEA     FAT, A1
    MOVE.L  #NUMBER_OF_DATA_BLOCKS/8, D3
.LOOP1
    CLR.B   (A1)+
    DBRA    D3, .LOOP1  clear fat area (named bitmap)
    BSR     OPEN_DISK_IMAGE
    MOVE.L  #POSITION_FILE, D0
    MOVE.L  FID_CPM, D1
    ANDI.B  #$F, D1
    CLR.L   D2
    TRAP    #15             position file
    MOVE.L  #20, D7
    TST.W   D0
    BNE     ABEND
    LEA     DIR_BUFFER, A1
    MOVE.L  #DIRECTORY_SIZE*NUMBER_OF_DIR_ENTRIES, D2
    BSR     READ_DISK_IMAGE
**    BSR     CLOSE_DISK_IMAGE
* all directories are now read
* on va recenser tous les blocs alloués et renseigner la bitmap
* CP/M étant petit boutien, nous devons inverser les octets 2 par 2
    LEA     REPERTOIRE, A1
    BSR     DISPLAY_STRING_WITH_CRLF
    LEA     DIR_BUFFER, A2
    MOVE.L  #NUMBER_OF_DIR_ENTRIES-1, D3
.LOOP2
    CMP.B   #$E5, (A2)
    BEQ     .CONTINUE
* afficher nom et taille
    TST.B   12(A2)              Xt = zero ?
    BNE     .NOT_FIRST_ENTRY
    MOVEA   A2, A3
    ADDQ.L  #1, A3
    MOVE.L  #8-1, D4
.LOOP21
    MOVE.B  (A3)+, D1
    CMP.B   #' ', D1
    BEQ     .SKIP1
    BSR     DISPLAY_CHAR
.SKIP1 
    DBRA    D4, .LOOP21
    MOVE.B  #'.', D1
    BSR     DISPLAY_CHAR
    MOVE.L  #3-1, D4
.LOOP22
    MOVE.B  (A3)+, D1
    CMP.B   #' ', D1
    BEQ     .SKIP2
    BSR     DISPLAY_CHAR
.SKIP2 
    DBRA    D4, .LOOP22
    MOVE.B  #' ', D1
    BSR     DISPLAY_CHAR
    CLR.L   FILESIZE
.NOT_FIRST_ENTRY
    CMP.B   #$E5, DIRECTORY_SIZE(A2)    si l'entrée suivante n'est pas valide
    BEQ     .LAST_ENTRY
    TST.B   DIRECTORY_SIZE+12(A2)       si Xt = 0
    BEQ     .LAST_ENTRY
    MOVE.L  FILESIZE, D4
    EOR.L   D5, D5
    MOVE.B  15(A2), D5
    ADD.L   D5, D4
    MOVE.L  D4, FILESIZE            size in sectors
    BRA     .FILL_FAT
.LAST_ENTRY
    MOVE.L  FILESIZE, D4
    EOR.L   D5, D5
    MOVE.B  15(A2), D5
    ADD.L   D5, D4
    MOVE.L  D4, FILESIZE            size in sectors
    MOVE.L  D4, D1
    MOVE.L  #3, D0
    TRAP    #15         display D1.L
    LEA     TAILLE, A1
    BSR     DISPLAY_STRING_WITH_CRLF
* renseigner la FAT
.FILL_FAT
    LEA     FAT, A3
    MOVEQ.L #17, D4          pointe vers les 16 Al (low puis high byte)
.LOOP3
    EOR     D5, D5           clear D5 ; Motorola est grand boutien, d'où le byte swap
    MOVE.B  (A2, D4), D5     get high byte
    LSL.L   #8, D5           left shift 8 bits
    SUBQ.L  #1, D4
    OR.B    (A2, D4), D5     get low byte
    TST.L   D5               is it a valid block number ?
    BEQ     .RIEN_A_FAIRE
* the FAT is a bitmap : divide D5 by 8 gives the byte address and the remainder (modulo 8) the bit to set
    DIVU    #8, D5
    MOVE.L  D5, D6
    ANDI.L  #$0000FFFF, D5  offset
    SWAP    D6
    ANDI.L  #$0000FFFF, D6  bit à monter
    BSET    D6, (A3, D5)
.RIEN_A_FAIRE
    ADDQ.L  #3, D4
    CMP.L   #32, D4
    BLT     .LOOP3
.CONTINUE
    ADD.L   #DIRECTORY_SIZE, A2
    DBRA    D3, .LOOP2
    MOVEM.L (SP)+, D0-A6
    RTS

CREATE_OUTPUT_FILE:
* entry : A1 = address of output file
    MOVEM.L D0, -(SP)
    MOVE.L  #CREATE_FILE, D0
    TRAP    #15
    ORI.B   #$F0, D1
    MOVE.L  D1, FID_EXP
    MOVE.L  #7, D7
    TST.W   D0
    BNE     ABEND
    MOVEM.L (SP)+, D0
    RTS

WRITE_OUTPUT_FILE:
    MOVEM.L D1, -(SP)
    MOVE.L  FID_EXP, D1
    ANDI.B  #$F, D1
    MOVE.L  #WRITE_FILE, D0
    TRAP    #15
    MOVE.L  #8, D7
    TST.W   D0
    BNE     ABEND
    MOVEM.L (SP)+, D1
    RTS

CLOSE_OUTPUT_FILE:
    MOVEM.L D1, -(SP)
    MOVE.L  #CLOSE_FILE, D0
    MOVE.L  FID_EXP, D1
    BEQ     .NOT_OPENED
    ANDI.B  #$F, D1
    TRAP    #15
    MOVE.L  #9, D7
    TST.W   D0
    BNE     ABEND
    CLR.L   FID_EXP
.NOT_OPENED
    MOVEM.L (SP)+, D1
    RTS

EXPORT_BLOCK:
    MOVEM.L D0-D4, -(SP)
    MOVE.L  #POSITION_FILE, D0
    LEA     BLOCK_BUFFER, A1
    MOVE.L  FID_CPM, D1
    ANDI.B  #$F, D1
    MOVE.L  #BLOCK_SIZE, D2
    MULU    D5, D2          D2 = D2 * block number
    TRAP    #15             position file
    MOVE.L  #10, D7
    TST.W   D0
    BNE     ABEND
    MOVE.L  #BLOCK_SIZE, D2
    BSR     READ_DISK_IMAGE
    ADDI.L  #16, NUM_SECTORS_READ
* write block to output (export) file
    MOVE.L  NUM_SECTORS_READ, D3
    MOVE.L  NUM_SECT_TO_READ, D4
    CMP.L   D3, D4
    BGE     .WRITE_ALL      not too much read
* de combien de secteurs faut-il raccourcir ?
    SUB.L   D4, D3          D3 = nombre de secteurs à tronquer
    MULU    #128, D3        converti en nombre d'octets
    SUB.L   D3, D2          D2 diminué
* recherche du ctrl-Z
.LOOP1
    MOVE.L  D2, D3
    SUBQ.L  #1, D3
    CMP.B   #$1A, (A1, D3)
    BNE     .WRITE_ALL
    SUBQ.L  #1, D2
    BRA    .LOOP1
.WRITE_ALL
    BSR     WRITE_OUTPUT_FILE
    MOVEM.L (SP)+, D0-D4
    RTS

FETCH_FILE:
    MOVEM.L D0-A6, -(SP)
    CLR.L   NUM_SECT_TO_READ
    CLR.L   NUM_SECTORS_READ
    LEA     FILE_TO_FETCH, A1
    BSR     CREATE_OUTPUT_FILE
    BSR     READ_DIRECTORY
    LEA     DIR_BUFFER, A2
    LEA     FILE_TO_FETCH2, A0
    CLR.L   D0              from 0 to number of dir entries
.LOOP1
    CMP.B   #$E5, (A2)      entrée libre ?
    BEQ     .RIEN_A_FAIRE
    MOVEM.L A0/A2, -(SP)    save A0 and A2
    ADDQ.L  #1, A2          points to first char of filename
    MOVEQ.L #11-1, D1       from 10 to -1
.LOOP2
    CMPM.B  (A2)+, (A0)+    égalité ?
    DBNE    D1, .LOOP2
    TST.B   D1              avons-nous une égalité pour les 11 caractères ?
    BGE     .NO_MATCH
* file found, get block numbers
    MOVE.L  #8-1, D1        8 block numbers
    MOVE.L  #3, D4          pointe vers le nombre de secteurs (directory entry start + 15)
    MOVE.L  NUM_SECT_TO_READ, D6
    EOR.L   D5, D5
    MOVE.B  (A2, D4), D5
    ADD.L   D5, D6
    MOVE.L  D6, NUM_SECT_TO_READ
    MOVE.L  #5, D4          nous amène à DIRECTORY + 17
.LOOP3
    EOR.L   D5, D5           clear D5 ; Motorola est grand boutien, d'où le byte swap
    MOVE.B  (A2, D4), D5
    LSL.L   #8, D5
    SUBQ.L  #1, D4
    OR.B    (A2, D4), D5
    TST.L   D5
    BEQ     .NOT_ALLOCATED
    BSR     EXPORT_BLOCK
.NOT_ALLOCATED
    ADDQ.L  #3, D4
    DBRA    D1, .LOOP3
.NO_MATCH
    MOVEM.L (SP)+, A0/A2    restore dir pointer and filename pointer
.RIEN_A_FAIRE
    CMP.L   #NUMBER_OF_DIR_ENTRIES, D0
    BGE     .EXIT         si 128 ou plus
    ADDQ.L  #1, D0
    ADD.L   #DIRECTORY_SIZE, A2     prêt pour l'entrée suivante
    BRA     .LOOP1
.EXIT
    BSR     CLOSE_OUTPUT_FILE
    MOVEM.L (SP)+, D0-A6
    RTS

ABEND:                   * D7 = abend code
    LEA     ERREUR, A1
    BSR     DISPLAY_STRING_WITHOUT_CRLF
    MOVE.L  D7, D1
    MOVE.L  #3, D0
    TRAP    #15         display D1.L
    LEA     CRLF, A1
    BSR     DISPLAY_STRING_WITHOUT_CRLF
    BSR     CLOSE_DISK_IMAGE
    BSR     CLOSE_OUTPUT_FILE
    SIMHALT

DISK_IMAGE      DC.B    'cpmdisk.bin', 0
ERREUR          DC.B    'Erreur ', 0
CRLF            DC.B    $0D, $0A, 0
FORMAT_DONE     DC.B    'Formatage effectué', 0
COMMANDE        DC.B    'Commande ? 1=format, 2=dir, 3=export file : ', 0
COMMANDE2       DC.B    'Nom du fichier à exporter : ', 0
REPERTOIRE      DC.B    'Répertoire :', 0
TAILLE          DC.B    ' secteurs (de 128 octets)', 0
E5              DS.B    BLOCK_SIZE
MARKER1         DC.B    'FAT '
FAT             DS.B    NUMBER_OF_DATA_BLOCKS/8+1
FILE_TO_FETCH   DC.B    'FFFFFFFF.TTT', 0
FILE_TO_FETCH2  DC.B    'FFFFFFFFTTT'
FID_CPM         DC.L    0
FID_EXP         DC.L    0
NUM_SECT_TO_READ    DS.L    1
NUM_SECTORS_READ    DS.L    1
FILESIZE        DS.L    1

* directory entry
* inspired by CP/M which is little endian
* Us Fn Fn Fn Fn Fn Fn Fn Fn Ty Ty Ty Xt At Lh Ll
* Al Al Al Al Al Al Al Al Al Al Al Al Al Al Al Al
DIRECTORY   DC.B    $E5            user number
FILENAME    DC.B    'FFFFFFFF'  file name
FILETYPE    DC.B    'TTT'           file type
EXTEND      DC.B    0               extend number (0 = no extend, 1 = extend n° 1...)
ATTRIBUTES  DC.B    0               attributes (saved, public, protected...)
TIMESTAMP   DC.B    0
FILELENGTH  DC.B    0               file length in sectors of 128 bytes
ALLOCATION  DC.W    $0,$0,$0,$0,$0,$0,$0,$0  blocks allocated to the file, Al

* buffers
MARKER2         DC.B    'DIR BUFFER '
DIR_BUFFER      DS.B    DIRECTORY_SIZE*NUMBER_OF_DIR_ENTRIES
MARKER3         DC.B    'BLOCK BUFFER'
BLOCK_BUFFER    DS.B    BLOCK_SIZE

    END    START        ; last line of source
























































*~Font name~Fixedsys~
*~Font size~9~
*~Tab type~1~
*~Tab size~4~
