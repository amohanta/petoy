
.586p
.model flat,stdcall
option casemap:none

include masm32\windows.inc

; ------------------------------------------------
; �ṹ������
; ------------------------------------------------

; �����
TOY_IMPORT_TYPE_DLLNAME      equ 1
TOY_IMPORT_TYPE_FIRST_THUNK  equ 2
TOY_IMPORT_TYPE_ORDINAL      equ 3
TOY_IMPORT_TYPE_FUNC_NAME    equ 4


TOY_TYPE_SECTION    equ 1       ; ���ݿ��ʾһ������
TOY_TYPE_IMPORT     equ 2       ; ���ݿ��ʾ�����
TOY_TYPE_BASERELOC  equ 3       ; ���ݿ��ʾ��ֵ�ض�λ����

TOY_IMPORT_THUNK struct
	dwSize  dd ?
	dwType  dd ?
TOY_IMPORT_THUNK ends

; ��ֵ�ض�λ
TOY_BASE_RELOC struct
	dwVAddr   dd ?
	dwType    dd ?
	dwNumber  dd ?
TOY_BASE_RELOC ends

; ������Ϣ
TOY_SECTION struct
	dwEncrypt      dd ?
	dwOrignalAddr  dd ?
	dwPackedSize   dd ?
TOY_SECTION ends

; ���ݿ���Ϣ
TOY_BLOCK_TYPE_SECTION    equ 1
TOY_BLOCK_TYPE_IMPORT     equ 2
TOY_BLOCK_TYPE_BASERELOC  equ 3

TOY_BLOCK_HEADER struct
	dwSize  dd ?
	dwType  dd ?
TOY_BLOCK_HEADER ends

; ��������
ToyMemCpy proto dst:ptr byte, src:ptr byte, len:dword
ToyZeroMem proto src:ptr byte, len:dword
ToyDecode proto dst:ptr byte, src:ptr byte, len:dword
ToyCheckDebugger proto
ToyDoSection proto instance:dword, section:dword
ToyDoImport proto instance:dword, thunk:dword
ToyDoBaseReloc proto instance:dword, reloc:dword
ToyDoDataBlock proto instance:dword, blockBase:dword


public ToyShellBegin
public ToyShellEnd
public ToyShellImportBegin
public ToyShellImportEnd
public ToyShellArgs

assume fs:nothing

.code

ToyShellBegin label dword
	nop ; 4�ֽڶ���
	nop
	pushad
	call next0

; -------------------------------------------------------------
; ��ǵ������
; -------------------------------------------------------------
ToyShellImportBegin label dword
ToyImportTable	 dd	AddressFirst - ToyImportTable     ; OriginalFirstThunk
		     dd	0,0                         ; TimeDataStamp, ForwardChain
 	         dd	DllName - ToyImportTable       ; Name
             dd	AddressFirst - ToyImportTable     ; FirstThunk
		     dd	0,0,0,0,0

AddressFirst	 dd	FirstFunction - ToyImportTable     ; ָ��IMAGE_THUNK_DATA
AddressSecond	 dd	SecondFunction - ToyImportTable    ; ָ��IMAGE_THUNK_DATA
AddressThird	 dd	ThirdFunction - ToyImportTable     ; ָ��IMAGE_THUNK_DATA
		     dd	0

DllName		 db	'KERNEL32.dll'
		     dw	0

FirstFunction	 dw	0	
		     db	'GetProcAddress', 0
SecondFunction	 dw	0
		     db	'GetModuleHandleA', 0
ThirdFunction	 dw	0
		     db	'LoadLibraryA', 0
ToyShellImportEnd label dword

; -------------------------------------------------------------
; �ǵı���
; -------------------------------------------------------------
ToyShellArgs label dword
toyBlockVAddr   dd 0
toyBlockSize    dd 0
origImageBase   dd 0
origEntryPoint  dd 0

; �ڲ�ʹ�õı���
isFirstRun      dd 0
imageBase       dd 0

next0:
	pop  ebp
	sub  ebp, (ToyImportTable - ToyShellBegin)
	
	mov  eax, [ebp + (isFirstRun - ToyShellBegin)]
	.if eax != 0
		jmp ToyReturnOEP
	.endif
	inc  dword ptr [ebp + (isFirstRun - ToyShellBegin)]

	;�õ�ӳ���ֵ
	push 0
	call dword ptr [ebp + (AddressSecond - ToyShellBegin)] ; GetModuleHandle
	mov [ebp + (imageBase - ToyShellBegin)], eax

	invoke ToyCheckDebugger

	; �������ݿ�
	mov eax, [ebp + (toyBlockVAddr - ToyShellBegin)]
	add eax, [ebp + (imageBase - ToyShellBegin)]
	invoke ToyDoDataBlock, ebp, eax

	; ɾ���ǵ������
	mov  edi, ebp
	add  edi, ToyShellImportBegin - ToyShellBegin

	lea  eax, ToyShellImportBegin
	lea  ecx, ToyShellImportEnd
	sub  ecx, eax
	invoke ToyZeroMem, edi, ecx

	; ����
	mov  eax, [ebp + (origEntryPoint - ToyShellBegin)]
	add  eax, [ebp + (imageBase - ToyShellBegin)]
	add  dword ptr [ebp + (ToyReturnOEP - ToyShellBegin) + 1], eax ; SMC
	popad
ToyReturnOEP:
	push dword ptr[0]
	ret

ToyDoDataBlock proc instance:dword, blockBase:dword
	local @block:dword, @blockData:dword
	
	mov  edi, [blockBase]
	mov  [@block], edi

	.while 1
		mov  edi, [@block]

		mov  eax, edi
		add  eax, TOY_BLOCK_HEADER.dwSize
		mov  eax, [eax]
		.if eax == 0
			.break
		.endif

		mov  eax, edi
		add  eax, sizeof TOY_BLOCK_HEADER
		mov  [@blockData], eax

		mov  eax, edi
		add  eax, TOY_BLOCK_HEADER.dwType
		mov  eax, [eax]
		.if eax == TOY_TYPE_SECTION
			invoke ToyDoSection, [instance], [@blockData]
		.elseif eax == TOY_TYPE_IMPORT
			invoke ToyDoImport, [instance], [@blockData]
		.elseif eax == TOY_TYPE_BASERELOC
			invoke ToyDoBaseReloc, [instance], [@blockData]
		.endif

		mov  edi, [@block]
		mov  ecx, [edi + TOY_BLOCK_HEADER.dwSize]
		mov  eax, edi
		add  eax, ecx
		mov  [@block], eax

		; ��յ�ǰ���ݿ������
		invoke ToyZeroMem, edi, ecx
	.endw
	ret
ToyDoDataBlock endp

ToyDoSection proc instance:dword, section:dword
	local  data:dword, encrypt:dword, origAddr:dword, packedSize:dword

	mov  edi, [section]

	mov  eax, edi
	add  eax, sizeof TOY_SECTION
	mov  data, eax

	mov  eax, [edi + TOY_SECTION.dwEncrypt]
	mov  [encrypt], eax

	mov  eax, [edi + TOY_SECTION.dwPackedSize]
	mov [packedSize], eax
	
	mov  eax, edi
	add  eax, TOY_SECTION.dwOrignalAddr
	mov  eax, [eax]
	mov  ebx, [instance]
	add  eax, [ebx + (imageBase - ToyShellBegin)]
	mov  [origAddr], eax

	.if encrypt == 0
		invoke ToyMemCpy, [origAddr], [data], [packedSize]
	.else
		invoke ToyDecode, [origAddr], [data], [packedSize]
	.endif
	ret
ToyDoSection endp

ToyImportThunkNext macro t, n
	push edi
	mov  edi, t
	add  edi, [edi + TOY_IMPORT_THUNK.dwSize]
	mov  n, edi
	pop  edi
endm

ToyImportThunkData macro t, d
	push edi
	mov  edi, t
	add  edi, sizeof TOY_IMPORT_THUNK
	mov  d, edi
	pop  edi
endm

ToyDoImport proc instance:dword, thunk:dword
	local @thunk:dword, @dll:dword, @firstThunk:dword, @thunkData:dword, @size:dword

	; DllName
	mov  edi, [thunk]
	mov  eax, [edi + TOY_IMPORT_THUNK.dwType]
	.if eax != TOY_IMPORT_TYPE_DLLNAME
		ret
	.endif

	ToyImportThunkData [thunk], [@thunkData]

	push [@thunkData]
	mov  ebx, [instance]
	call dword ptr [ebx + (AddressSecond - ToyShellBegin)] ; GetModuleHandle
	.if eax == 0
		push [@thunkData]
		mov  ebx, [instance]
		call dword ptr [ebx + (AddressThird - ToyShellBegin)] ; LoadLibrary
	.endif
	mov [@dll], eax

	; FirstThunk
	ToyImportThunkNext [thunk], [@thunk]

	mov  edi, [@thunk]
	mov  eax, [edi + TOY_IMPORT_THUNK.dwType]
	.if eax != TOY_IMPORT_TYPE_FIRST_THUNK
		ret
	.endif

	ToyImportThunkData [@thunk], [@thunkData]
	
	mov  edi, [@thunkData]
	mov  edi, [edi]
	mov  ebx, [instance]
	add  edi, [ebx + (imageBase - ToyShellBegin)]
	mov  [@firstThunk], edi

	; Function
	.while 1
		ToyImportThunkNext [@thunk], [@thunk]
		mov  eax, [@thunk + TOY_IMPORT_THUNK.dwSize]
		mov  eax, [eax]
		.if eax == 0
			.break
		.endif

		ToyImportThunkData [@thunk], [@thunkData]
		mov  edi, [@thunk]
		mov  eax, [edi + TOY_IMPORT_THUNK.dwType]
		.if eax == TOY_IMPORT_TYPE_ORDINAL
			mov  eax, [@thunkData]
			push [eax]
		.elseif eax == TOY_IMPORT_TYPE_FUNC_NAME
			push [@thunkData]
		.endif
		push [@dll]
		mov  ebx, [instance]
		call dword ptr [ebx + (AddressFirst - ToyShellBegin)] ; GetProcAddress
		mov  edx, [@firstThunk]
		mov	 [edx], eax

		mov  eax, [@firstThunk]
		add  eax, sizeof IMAGE_THUNK_DATA32
		mov  [@firstThunk], eax
	.endw
	ret
ToyDoImport endp

ToyDoBaseReloc proc instance:dword, reloc:dword
	local @addr:ptr dword, @diff:dword, @offset:ptr word, @VAddr:dword

	mov  ebx, [instance]
	mov  eax, [ebx + (imageBase - ToyShellBegin)]
	sub  eax, [ebx + (origImageBase - ToyShellBegin)]
	mov  [@diff], eax

	mov  edi, [reloc]

	mov  eax, [edi + TOY_BASE_RELOC.dwType]
	.if eax != 3
		ret
	.endif

	mov  eax, [edi + TOY_BASE_RELOC.dwVAddr]
	add  eax, [ebx + (imageBase - ToyShellBegin)]
	mov  [@VAddr], eax

	mov  eax, edi
	add  eax, sizeof TOY_BASE_RELOC
	mov  [@offset], eax

	mov  ecx, [edi + TOY_BASE_RELOC.dwNumber]
	xor  esi, esi
	.while esi < ecx
		mov  ebx, [@offset]
		movzx eax, word ptr [ebx + sizeof WORD * esi] ; 16bit -> 32bit
		add  eax, [@VAddr]
		mov  edx, [@diff]
		add  [eax], edx
		inc esi
	.endw
	ret
ToyDoBaseReloc endp

ToyMemCpy proc dst:ptr byte, src:ptr byte, len:dword
	mov  edi, [dst]
	mov  esi, [src]
	mov  ecx, [len]

	shr  ecx, 2 ; ��DWORD����
	rep movsd

	mov ecx, [len] ; ����ʣ���С��DWORD�Ĳ���
	and ecx, 3
	rep movsb

	mov eax, [dst]
	ret
ToyMemCpy endp

ToyZeroMem proc src:ptr byte, len:dword
	mov  edi, [src]
	mov  ecx, [len]
	mov  eax, 0

	shr  ecx, 2
	rep stosd

	mov ecx, [len]
	and ecx, 3
	rep stosb

	xor  eax, [src]
	ret
ToyZeroMem endp

ToyCheckDebugger proc
	ret
ToyCheckDebugger endp

ToyDecode proc dst:ptr byte, src:ptr byte, len:dword
	mov  edi, [dst]
	mov  esi, [src]
	mov  edx, [len]
	
	xor  ecx, ecx
	.while ecx < edx
		mov  al, byte ptr [esi]
		xor  al, cl
		mov  byte ptr [edi], al
		inc  esi
		inc  edi
		inc  ecx
	.endw
	ret
ToyDecode endp

ToyShellEnd label dword

end