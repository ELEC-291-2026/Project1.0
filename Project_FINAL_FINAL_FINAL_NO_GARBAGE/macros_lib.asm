; side project file (macros_lib.asm)
; ------------------------------------------------------------------------------
; This is code for all the extra macros
; Used for mostly math stuff in the main file
; ------------------------------------------------------------------------------
; This include_file was made by the following people

;	- Owen Anderson 		 51069375
;	- Matthieu Moisan 		 68684836
; ------------------------------------------------------------------------------


;-------MACROS--------------------;
Load_X_Var32 MAC
	mov x+0, %0+0
	mov x+1, %0+1
	mov x+2, %0+2
	mov x+3, %0+3
ENDMAC

Load_Y_Var32 MAC
	mov y+0, %0+0
	mov y+1, %0+1
	mov y+2, %0+2
	mov y+3, %0+3
ENDMAC

Load_X_Var16 MAC
	mov x+0, %0+0
	mov x+1, %0+1
	mov x+2, #0
	mov x+3, #0
ENDMAC

Load_Y_Var16 MAC
	mov y+0, %0+0
	mov y+1, %0+1
	mov y+2, #0
	mov y+3, #0
ENDMAC

Load_X_Var8 MAC
	mov x+0, %0+0
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0
ENDMAC

Load_Y_Var8 MAC
	mov y+0, %0+0
	mov y+1, #0
	mov y+2, #0
	mov y+3, #0
ENDMAC

powerPercent MAC
	mov x+0, %0
	mov x+1, #0
	mov x+2, #0
	mov x+3, #0
	Load_Y_Var16(%1)
	lcall mul32
	
	load_y(100)
	lcall div32
	
	mov %2+0, x+0
	mov %2+1, x+1
ENDMAC

END