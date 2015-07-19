#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Change2CUI=y
#AutoIt3Wrapper_Res_Comment=CLI Parser for $UsnJrnl (NTFS)
#AutoIt3Wrapper_Res_Description=CLI Parser for $UsnJrnl (NTFS)
#AutoIt3Wrapper_Res_Fileversion=1.0.0.0
#AutoIt3Wrapper_Res_requestedExecutionLevel=asInvoker
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****
;
; This script is a reworking/combination of the UsnJrnl2Csv and MftRef2Name
; tools created by Joakim Schicht (https://github.com/jschicht).
;
; The basic idea is to, after enabling the USN Journal (https://en.wikipedia.org/wiki/USN_Journal)
; on an NTFS volume, use this tool to extract a list of files that the journal
; records as having been changed.  You then pass this list of changed files to
; your backup program (e.g. rsync --include-from=) so that it only backs up
; these files.
;
; Yes, rsync only copies files that have been changed by default,
; the problem arises however that if you have millions of files with only a
; limited subset of them changing, rsync will still spend a lot of time checking
; meta-data and checksums to work out what has changed.  Using this tool allows
; rsync to skip this check.
;
; So you don't repeat the mistake I made, because this is a console script, you
; can't simply double click the .au3 file or run "AutoIt3.exe FileName.au3" to
; use it.  You won't get any output.  You need to either compile the script into
; an executable using Aut2exe.exe with the "/console" switch or run this script
; from within the AutoIt3 provided SciTE-Lite editor.
;
; Finally, my excuse for code in this script being ugly and inefficient is that
; this is the first time I have ever worked with AutoIt code and there are large
; portions of Joakim's code that I don't fully understand.  Sorry.
;
#Include <WinAPIEx.au3>
#include <GUIConstantsEx.au3>
#include <WindowsConstants.au3>
#include <StaticConstants.au3>
#include <EditConstants.au3>
#include <GuiEdit.au3>
#Include <FileConstants.au3>
#Include <Array.au3>
#Include "UsnJrnl2Csv_Functions.au3"
#Include "MftRef2Name_Functions.au3"

Global $MyName = "BackupQueueFromUSNJournal"
Global $MyVersion = "1.0.0.0"
Global $DateTimeFormat, $TimestampPrecision
Global $PrecisionSeparator = "."
Global $de = "|"
Global $Record_Size = 4096
Global $VerboseOn = 0
Global $ParserOutDir = @ScriptDir
Global $CPUThrottle = 10
Global $File, $WithQuotes, $MaxRecords, $nBytes, $UsnJrnlCsv, $UsnJrnlCsvFile
Global $TargetDrive, $ExtractUsnJrnlPath, $ExtractUsnJrnlPid
Global $ExtractUsnJrnlResult
Global $MaxUSN = 0
Global $MinUSN = 0
Global $FirstUSN = 0

; Command line argument processing
If ($cmdline[0] > 0) Then
  For $i = 1 To $cmdline[0]
    If $cmdline[$i] = "-v" Then
      $VerboseOn = $VerboseOn + 1
      If ($VerboseOn = 1) Then
        ConsoleWrite("Turning on verbose output" & @CRLF)
      Else
        ConsoleWrite("Increasing output verbosity" & @CRLF)
      EndIf
    ElseIf $cmdline[$i] = "-V" Then
      ConsoleWrite($MyName & " " & $MyVersion & @CRLF)
      Exit
    ElseIf $cmdline[$i] = "-l" Then
      If ($CPUThrottle = 10) Then
        $CPUThrottle = 50
      Else
        $CPUThrottle = 200
      EndIf
    ElseIf $cmdline[$i] = "-m" Then
      If StringIsDigit($cmdline[$i + 1]) Then
        $MinUSN = $cmdline[$i + 1]
      Else
        ConsoleWriteError("Error: The value specified for the -m switch must be a number." & @CRLF)
        Exit
      EndIf
    ElseIf $cmdline[$i] = "/?" Or $cmdline[$i] = "/h" Or $cmdline[$i] = "-h" Or $cmdline[$i] = "-?" Then
      HelpMessage()
      Exit
    EndIf
  Next

  ; The Volume specified on the command line can be in either the for of "X:" or
  ; just "X".
  If (StringLen($cmdline[$cmdline[0]]) = 1) Then
    $TargetDrive = $cmdline[$cmdline[0]] & ":"
  ElseIf (StringLen($cmdline[$cmdline[0]]) = 2) And (StringRight($cmdline[$cmdline[0]], 1) = ":") Then
    $TargetDrive = $cmdline[$cmdline[0]]
  Else
    ConsoleWriteError("'" & $cmdline[$cmdline[0]] & "' is not a valid value for Volume." & @CRLF & @CRLF)
    HelpMessage()
    Exit
  EndIf
Else
  HelpMessage()
  Exit
EndIf

; Input validation - Ensure target volume exists
If Not (FileExists($TargetDrive & "\")) Then
  ConsoleWriteError("Error: The specified target volume '" & $TargetDrive & "' doesn't seem to exist.")
  Exit
EndIf

; Input validation - Ensure target volume is NTFS
_ReadBootSector($TargetDrive)
If @error Then
	ConsoleWriteError("Error: Filesystem not NTFS" & @CRLF)
	Exit
EndIf

;TODO: Test that this works
; Check that the target drive has the USN journal enabled and enable if
; necessary
Local $FSUTILPid = Run("fsutil usn queryjournal " & $TargetDrive, @ScriptDir, @SW_HIDE, $STDOUT_CHILD)
ProcessWaitClose($FSUTILPid)
Local $FSUTILResult = StdoutRead($FSUTILPid)
If $VerboseOn > 0 Then ConsoleWrite($FSUTILResult)
If (StringInStr($FSUTILResult, "First Usn") < 1) Then
  ConsoleWriteError("The USN Journal is not enabled on " & $TargetDrive & "." & @CRLF & @CRLF)
  ConsoleWriteError("On Windows 2008 and higher you can use the 'fsutil' tool to enable the USN Journal." & @CRLF & @CRLF)
  ConsoleWriteError("Please complete a full, rather than an incremental, backup." & @CRLF & @CRLF)
  Exit
Else
  If $VerboseOn > 0 Then ConsoleWrite("USN Journal is enabled for " & $TargetDrive & "." & @CRLF)
EndIf

; We need ExtractUsnJrnl.exe.  Make sure it exists.
If FileExists(@ScriptDir & "\ExtractUsnJrnl\ExtractUsnJrnl.exe") Then
  $ExtractUsnJrnlPath = @ScriptDir & "\ExtractUsnJrnl\"
ElseIf FileExists(@ScriptDir & "\ExtractUsnJrnl.exe") Then
  $ExtractUsnJrnlPath = @ScriptDir & "\"
Else
  ConsoleWriteError("ExtractUsnJrnl.exe not found!" & @CRLF)
  Exit
EndIf

; Need to set $File to USN Journal file path
$File = $ExtractUsnJrnlPath & "\$UsnJrnl_$J.bin"

; Delete $File if it exists
If FileExists($File) Then
  If $VerboseOn > 0 Then ConsoleWrite("Deleting previously extracted USN Journal." & @CRLF)
  FileDelete($File)
EndIf

; Here we call the ExtractUsnJrnl.exe to extract a copt of the USN Journal from
; the target drive.
ConsoleWrite("Extracting USN Journal with ExtractUsnJrnl.exe" & @CRLF)
Local $ExtractUsnJrnlPid = Run($ExtractUsnJrnlPath & "ExtractUsnJrnl.exe " & $TargetDrive, $ExtractUsnJrnlPath, @SW_HIDE, $STDOUT_CHILD)
ProcessWaitClose($ExtractUsnJrnlPid)
Local $ExtractUsnJrnlResult = StdoutRead($ExtractUsnJrnlPid)
If $VerboseOn > 0 Then ConsoleWrite($ExtractUsnJrnlResult)

;TODO: Do we still need this? Enable UNICODE
$EncodingWhenOpen = 2+32

If Not FileExists($File) Then
	ConsoleWrite("Error: Could not find extracted USN Journal file.  Maybe ExtractUsnJrnl.exe failed." & @CRLF)
	Exit
EndIf
$TimestampStart = @YEAR & "-" & @MON & "-" & @MDAY & "_" & @HOUR & "-" & @MIN & "-" & @SEC

ConsoleWrite("Decoding $UsnJrnl info..." & @CRLF)
$tBuffer = DllStructCreate("byte[" & $Record_Size & "]")
$hFile = _WinAPI_CreateFile("\\.\" & $File,2,2,7)
If $hFile = 0 Then
	ConsoleWrite("Error: Creating handle on file" & @CRLF)
	Exit
EndIf
$InputFileSize = _WinAPI_GetFileSizeEx($hFile)
$MaxRecords = Ceiling($InputFileSize/$Record_Size)
For $i = 0 To 15 ;$MaxRecords-1
	$CurrentPage=$i
	_WinAPI_SetFilePointerEx($hFile, $i*$Record_Size, $FILE_BEGIN)
	If $i = $MaxRecords-1 Then $tBuffer = DllStructCreate("byte[" & $Record_Size & "]")
	_WinAPI_ReadFile($hFile, DllStructGetPtr($tBuffer), $Record_Size, $nBytes)
	$RawPage = DllStructGetData($tBuffer, 1)
	_UsnProcessPage(StringMid($RawPage,3))
  Sleep($CPUThrottle)
Next

ConsoleWrite("Decoding finished" & @CRLF)
ConsoleWrite("Minimum Acceped USN: " & $MinUSN & @CRLF)
ConsoleWrite("Minimum Found USN: " & $FirstUSN & @CRLF)
ConsoleWrite("Maximum Found USN: " & $MaxUSN & @CRLF)

; If $MinUSN < $FirstUSN then there are gaps in the journal between the
; last time we ran and now.  DO A FULL BACKUP!
If (($MinUSN < $FirstUSN) And ($MinUSN > 0)) Then
  ConsoleWriteError(@CRLF & "USN " & $MinUSN & " was not found in the journal.  This means that changes have been made to the filesystem between " & $MinUSN & " and now that have been removed from the journal." & @CRLF & @CRLF)
  ConsoleWriteError("This may mean that your USN journal is too small or that too much time has passed (i.e. too many changes have occurred) since your last backup." & @CRLF & @CRLF)
  ConsoleWriteError("Please complete a full, rather than an incremental, backup." & @CRLF & @CRLF)
  Exit
EndIf

; Resolve MtfReference numbers to real file paths
;TODO: This process could be sped up if we modified the MftRef2Name function
; below to cache in an array some of the MftIDs in an array so they didn't all
; need to be resolved from $Mft
$MFTReferences = _ArrayUnique($MFTReferences, 0, 0, 0, $ARRAYUNIQUE_NOCOUNT, $ARRAYUNIQUE_MATCH)
If $VerboseOn > 0 Then ConsoleWrite("Accepted USNs: " & _ArrayToString($MFTReferences, ", ") & @CRLF)
For $i = 0 To UBound($MFTReferences)-1
  ConsoleWrite(MftRef2Name($MFTReferences[$i]) & @CRLF)
  Sleep($CPUThrottle)
Next

_WinAPI_CloseHandle($hFile)

Func _UsnDecodeRecord($Record)

	$UsnJrnlRecordLength = StringMid($Record,1,8)
	$UsnJrnlRecordLength = Dec(_SwapEndian($UsnJrnlRecordLength),2)
;	$UsnJrnlMajorVersion = StringMid($Record,9,4)
;	$UsnJrnlMinorVersion = StringMid($Record,13,4)
	$UsnJrnlFileReferenceNumber = StringMid($Record,17,12)
	$UsnJrnlFileReferenceNumber = Dec(_SwapEndian($UsnJrnlFileReferenceNumber),2)
	$UsnJrnlMFTReferenceSeqNo = StringMid($Record,29,4)
	$UsnJrnlMFTReferenceSeqNo = Dec(_SwapEndian($UsnJrnlMFTReferenceSeqNo),2)
	$UsnJrnlParentFileReferenceNumber = StringMid($Record,33,12)
	$UsnJrnlParentFileReferenceNumber = Dec(_SwapEndian($UsnJrnlParentFileReferenceNumber),2)
	$UsnJrnlParentReferenceSeqNo = StringMid($Record,45,4)
	$UsnJrnlParentReferenceSeqNo = Dec(_SwapEndian($UsnJrnlParentReferenceSeqNo),2)
	$UsnJrnlUsn = StringMid($Record,49,16)
	$UsnJrnlUsn = Dec(_SwapEndian($UsnJrnlUsn),2)
;	If $i = 1704000 Then $PreviousUsn = $UsnJrnlUsn
;	If $PreviousUsn < $UsnJrnlUsn Then Exit
;	$PreviousUsn = $UsnJrnlUsn
	$UsnJrnlTimestamp = StringMid($Record,65,16)
	$UsnJrnlTimestamp = _DecodeTimestamp($UsnJrnlTimestamp)
	$UsnJrnlReason = StringMid($Record,81,8)
	$UsnJrnlReason = _DecodeReasonCodes("0x"&_SwapEndian($UsnJrnlReason))
;	$UsnJrnlSourceInfo = StringMid($Record,89,8)
;	$UsnJrnlSourceInfo = _DecodeSourceInfoFlag("0x"&_SwapEndian($UsnJrnlSourceInfo))
;	$UsnJrnlSourceInfo = "0x"&_SwapEndian($UsnJrnlSourceInfo)
;	$UsnJrnlSecurityId = StringMid($Record,97,8)
	$UsnJrnlFileAttributes = StringMid($Record,105,8)
	$UsnJrnlFileAttributes = _File_Attributes("0x"&_SwapEndian($UsnJrnlFileAttributes))
	$UsnJrnlFileNameLength = StringMid($Record,113,4)
	$UsnJrnlFileNameLength = Dec(_SwapEndian($UsnJrnlFileNameLength),2)
	$UsnJrnlFileNameOffset = StringMid($Record,117,4)
	$UsnJrnlFileNameOffset = Dec(_SwapEndian($UsnJrnlFileNameOffset),2)
	$UsnJrnlFileName = StringMid($Record,121,$UsnJrnlFileNameLength*2)
	$UsnJrnlFileName = _UnicodeHexToStr($UsnJrnlFileName)
	If $VerboseOn > 1 Then
		ConsoleWrite("$UsnJrnlFileReferenceNumber: " & $UsnJrnlFileReferenceNumber & @CRLF)
		ConsoleWrite("$UsnJrnlMFTReferenceSeqNo: " & $UsnJrnlMFTReferenceSeqNo & @CRLF)
		ConsoleWrite("$UsnJrnlParentFileReferenceNumber: " & $UsnJrnlParentFileReferenceNumber & @CRLF)
		ConsoleWrite("$UsnJrnlParentReferenceSeqNo: " & $UsnJrnlParentReferenceSeqNo & @CRLF)
		ConsoleWrite("$UsnJrnlUsn: " & $UsnJrnlUsn & @CRLF)
		ConsoleWrite("$UsnJrnlTimestamp: " & $UsnJrnlTimestamp & @CRLF)
		ConsoleWrite("$UsnJrnlReason: " & $UsnJrnlReason & @CRLF)
;		ConsoleWrite("$UsnJrnlSourceInfo: " & $UsnJrnlSourceInfo & @CRLF)
;		ConsoleWrite("$UsnJrnlSecurityId: " & $UsnJrnlSecurityId & @CRLF)
		ConsoleWrite("$UsnJrnlFileAttributes: " & $UsnJrnlFileAttributes & @CRLF)
		ConsoleWrite("$UsnJrnlFileName: " & $UsnJrnlFileName & @CRLF)
	EndIf

  ; We're going to need to know that the first USN in the USN Journal is larger
  ; than the MaxUSN of the previous backup.  Otherwise we have missed changes.
  If (($FirstUSN > $UsnJrnlUsn) Or ($FirstUSN = 0)) Then
    $FirstUSN = $UsnJrnlUsn
  EndIf

  ; If this USN is lower then the MinUSN then this change has already been
  ;  actioned on a previous backup run
  If (($UsnJrnlUsn > $MinUSN) Or ($MinUSN = 0)) Then
    ; We will need the maximum USN value so we know where to kick off the next run
    If ($UsnJrnlUsn > $MaxUSN) Then
      $MaxUSN = $UsnJrnlUsn
    EndIf

    _ArrayAdd($MFTReferences, $UsnJrnlFileReferenceNumber)
  EndIf
EndFunc

Func MftRef2Name($IndexNumber)
  Local Static $Initialised = False

  If Not $Initialised Then
    If $VerboseOn > 0 Then ConsoleWrite("MftRef2Name: Initailising (this should only happen once)" & @CRLF)
    $ParentDir = _GenDirArray($TargetDrive & "\")
    Global $MftRefArray[$DirArray[0]+1]

    $hDisk = _WinAPI_CreateFile("\\.\" & $TargetDrive,2,2,7)
    If $hDisk = 0 Then
      ConsoleWriteError("MftRef2Name Error: CreateFile: " & _WinAPI_GetLastErrorMessage() & @CRLF)
      Return
    EndIf

    $MFTEntry = _FindMFT(0)
    If $MFTEntry = "" Then ;something wrong with record for $MFT
      ConsoleWriteError("MftRef2Name Error: Getting MFT record 0" & @CRLF)
      Return
    EndIf

    $MFT = _DecodeMFTRecord0($MFTEntry, 0)        ;produces DataQ for $MFT, record 0
    If $MFT = "" Then
      ConsoleWriteError("MftRef2Name Error: Parsing the MFT record 0" & @CRLF)
      Return
    EndIf

    _GetRunsFromAttributeListMFT0() ;produces datarun for $MFT and converts datarun to RUN_VCN[] and RUN_Clusters[]
    _WinAPI_CloseHandle($hDisk)

    $MFTSize = $DATA_RealSize
    $MFT_RUN_VCN = $RUN_VCN
    $MFT_RUN_Clusters = $RUN_Clusters

    _GenRefArray()
    $Initialised = True
  EndIf

  ; Resolve path based on MFT ref as input
  If StringIsDigit($IndexNumber) Then
  	Global $DataQ[1],$AttribX[1],$AttribXType[1],$AttribXCounter[1]
  	$NewRecord = _FindFileMFTRecord($IndexNumber)
  	_DecodeMFTRecord($NewRecord,2)
  	$TestHeaderFlags = $RecordHdrArr[7][1]
  	If StringInStr($TestHeaderFlags,"ALLOCATED")=0 And StringInStr($TestHeaderFlags,"ENABLED")=0 Then
  		;_DumpInfo()
  		;ConsoleWrite("File marked as deleted. Makes no sense to resolve the path" & @CRLF)
  		Return "Deleted!"

    ;TODO: ElseIf: See "$HEADER_Flags = 'FOLDER'" in _DecodeMFTRecord to filter out folders
  	EndIf
  	$TmpRef = _GetParent()
  	$TestFileName = $TmpRef[1]
  	$TestParentRef = $TmpRef[0]
  	$ResolvedPath = $TestFileName
  	Do
  		Global $DataQ[1],$AttribX[1],$AttribXType[1],$AttribXCounter[1]
  		$NewRecord = _FindFileMFTRecord($TestParentRef)
  		_DecodeMFTRecord($NewRecord,2)
  		$TmpRef = _GetParent()
  		If @error then ExitLoop
  		$TestFileName = $TmpRef[1]
  		$TestParentRef = $TmpRef[0]
  		$ResolvedPath = $TestFileName&"\"&$ResolvedPath
  	Until $TestParentRef=5

  	If StringLeft($ResolvedPath,2) = ".\" Then $ResolvedPath = StringTrimLeft($ResolvedPath,2)
  	Return $TargetDrive & "\" & $ResolvedPath
  EndIf
  ; Test if root directory is selected
  If $DirArray[0] = 2 And $DirArray[2] = "" Then
    Return $TargetDrive & "\"
  EndIf
  ; Resolve path under root directory
  $NextRef = 5
  $MftRefArray[1]=$NextRef
  $ResolvedPath = $DirArray[1]
  For $i = 2 To $DirArray[0]
  	Global $DataQ[1],$AttribX[1],$AttribXType[1],$AttribXCounter[1]
  	$NewRecord = _FindFileMFTRecord($NextRef)
  	_DecodeMFTRecord($NewRecord,1)
  	$NextRef = _ParseIndex($DirArray[$i])
  	$MftRefArray[$i]=$NextRef
  	If @error Then
  		ConsoleWriteError("MftRef2Name Error: 1" & @CRLF)
  		Return 1
  	ElseIf $i=$DirArray[0] Then
      Return $ResolvedPath & "\" & $DirArray[$i]
  	ElseIf StringIsDigit($NextRef) Then
  		$ResolvedPath &= "\" & $DirArray[$i]
  		ContinueLoop
  	Else
  		ConsoleWriteError("MftRef2Name Error: Something went wrong" & @CRLF)
  		ExitLoop
  	EndIf
  Next
EndFunc

Func HelpMessage()
  ConsoleWrite($MyName & " " & $MyVersion & @CRLF & @CRLF)
  ConsoleWrite("  " & $MyName & ".exe [-h|-l|-v|-V] [-m num] Volume" & @CRLF)
  ConsoleWrite("     -h      Show this help message and quit" & @CRLF)
  ConsoleWrite("     -l      Use longer sleep cycles to reduce CPU usage and the expense of the" & @CRLF)
  ConsoleWrite("             process taking longer.  You can use this switch twice to further" & @CRLF)
  ConsoleWrite("             increase the length of the sleep cycles." & @CRLF)
  ConsoleWrite("     -m num  Specify the USN of the first acceptable journal entry.  This will" & @CRLF)
  ConsoleWrite("             likely be the 'Maximum Found USN' from the previous run." & @CRLF)
  ConsoleWrite("             Basically, all journal entries before the specified num will be" & @CRLF)
  ConsoleWrite("             ignored as it is assumed that the changes they represent have" & @CRLF)
  ConsoleWrite("             already been captured by previous backup runs." & @CRLF)
  ConsoleWrite("     -v      Enable verbose output.  Use twice for more verbose output." & @CRLF)
  ConsoleWrite("     -V      Output version and quit" & @CRLF)
  ConsoleWrite("     Volume  The volume to extract the USN Journal from" & @CRLF & @CRLF)
EndFunc
