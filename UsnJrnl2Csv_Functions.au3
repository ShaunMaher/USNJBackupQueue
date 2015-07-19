;
; Everything in this file has been taken directly from UsnJrnl2Csv.au3 found in
; Joakim Schicht's (jschicht) awesome UsnJrnl2Csv Github.com repository
; (https://github.com/jschicht/UsnJrnl2Csv).  Everything here is his work.  This
; is however not the entire script, it's only the functions needed to pull USN
; Journal sequence numbers and $Mft reference numbers from a USN Journal that
; has already been extracted from an NTFS volume (maybe by using Joakim's
; ExtractUsnJrnl tool) so that this feature can be built into another script
; without needing to call an external executable and then parse it's output,
; etc.
;
; At the very least I owe Joakim a(nother) beer.
;

Global $_COMMON_KERNEL32DLL = DllOpen("kernel32.dll")

; The following uses $_COMMON_KERNEL32DLL so make sure it is defined first
Global $tDelta = _WinTime_GetUTCToLocalFileTimeDelta()

;; Below this line is stripped directly from UsnJrnl2csv.au3
Func _UsnProcessPage($TargetPage)
	Local $LocalUsnPart = 0, $NextOffset = 1, $TotalSizeOfPage = StringLen($TargetPage)
	Do
		$LocalUsnPart+=1
		$SizeOfNextUsnRecord = StringMid($TargetPage,$NextOffset,8)
		$SizeOfNextUsnRecord = Dec(_SwapEndian($SizeOfNextUsnRecord),2)
		If $SizeOfNextUsnRecord = 0 Then ExitLoop
		$SizeOfNextUsnRecord = $SizeOfNextUsnRecord*2
		$NextUsnRecord = StringMid($TargetPage,$NextOffset,$SizeOfNextUsnRecord)
		$FileNameLength = StringMid($TargetPage,$NextOffset+112,4)
		$FileNameLength = Dec(_SwapEndian($FileNameLength),2)
		$TestOffset = 60+$FileNameLength
		If $NextOffset+$SizeOfNextUsnRecord >= $TotalSizeOfPage Then Return
		_UsnDecodeRecord($NextUsnRecord)
		$NextOffset+=$SizeOfNextUsnRecord
	Until $NextOffset >= $TotalSizeOfPage
	Return ""
EndFunc

Func _DecodeReasonCodes($USNReasonInput)
	Local $USNReasonOutput = ""
	If BitAND($USNReasonInput, 0x00008000) Then $USNReasonOutput &= 'BASIC_INFO_CHANGE+'
	If BitAND($USNReasonInput, 0x80000000) Then $USNReasonOutput &= 'CLOSE+'
	If BitAND($USNReasonInput, 0x00020000) Then $USNReasonOutput &= 'COMPRESSION_CHANGE+'
	If BitAND($USNReasonInput, 0x00000002) Then $USNReasonOutput &= 'DATA_EXTEND+'
	If BitAND($USNReasonInput, 0x00000001) Then $USNReasonOutput &= 'DATA_OVERWRITE+'
	If BitAND($USNReasonInput, 0x00000004) Then $USNReasonOutput &= 'DATA_TRUNCATION+'
	If BitAND($USNReasonInput, 0x00000400) Then $USNReasonOutput &= 'EA_CHANGE+'
	If BitAND($USNReasonInput, 0x00040000) Then $USNReasonOutput &= 'ENCRYPTION_CHANGE+'
	If BitAND($USNReasonInput, 0x00000100) Then $USNReasonOutput &= 'FILE_CREATE+'
	If BitAND($USNReasonInput, 0x00000200) Then $USNReasonOutput &= 'FILE_DELETE+'
	If BitAND($USNReasonInput, 0x00010000) Then $USNReasonOutput &= 'HARD_LINK_CHANGE+'
	If BitAND($USNReasonInput, 0x00004000) Then $USNReasonOutput &= 'INDEXABLE_CHANGE+'
	If BitAND($USNReasonInput, 0x00000020) Then $USNReasonOutput &= 'NAMED_DATA_EXTEND+'
	If BitAND($USNReasonInput, 0x00000010) Then $USNReasonOutput &= 'NAMED_DATA_OVERWRITE+'
	If BitAND($USNReasonInput, 0x00000040) Then $USNReasonOutput &= 'NAMED_DATA_TRUNCATION+'
	If BitAND($USNReasonInput, 0x00080000) Then $USNReasonOutput &= 'OBJECT_ID_CHANGE+'
	If BitAND($USNReasonInput, 0x00002000) Then $USNReasonOutput &= 'RENAME_NEW_NAME+'
	If BitAND($USNReasonInput, 0x00001000) Then $USNReasonOutput &= 'RENAME_OLD_NAME+'
	If BitAND($USNReasonInput, 0x00100000) Then $USNReasonOutput &= 'REPARSE_POINT_CHANGE+'
	If BitAND($USNReasonInput, 0x00000800) Then $USNReasonOutput &= 'SECURITY_CHANGE+'
	If BitAND($USNReasonInput, 0x00200000) Then $USNReasonOutput &= 'STREAM_CHANGE+'
	If BitAND($USNReasonInput, 0x00800000) Then $USNReasonOutput &= 'INTEGRITY_CHANGE+'
	$USNReasonOutput = StringTrimRight($USNReasonOutput, 1)
	Return $USNReasonOutput
EndFunc

Func _File_Attributes($FAInput)
	Local $FAOutput = ""
	If BitAND($FAInput, 0x0001) Then $FAOutput &= 'read_only+'
	If BitAND($FAInput, 0x0002) Then $FAOutput &= 'hidden+'
	If BitAND($FAInput, 0x0004) Then $FAOutput &= 'system+'
	If BitAND($FAInput, 0x0010) Then $FAOutput &= 'directory+'
	If BitAND($FAInput, 0x0020) Then $FAOutput &= 'archive+'
	If BitAND($FAInput, 0x0040) Then $FAOutput &= 'device+'
	If BitAND($FAInput, 0x0080) Then $FAOutput &= 'normal+'
	If BitAND($FAInput, 0x0100) Then $FAOutput &= 'temporary+'
	If BitAND($FAInput, 0x0200) Then $FAOutput &= 'sparse_file+'
	If BitAND($FAInput, 0x0400) Then $FAOutput &= 'reparse_point+'
	If BitAND($FAInput, 0x0800) Then $FAOutput &= 'compressed+'
	If BitAND($FAInput, 0x1000) Then $FAOutput &= 'offline+'
	If BitAND($FAInput, 0x2000) Then $FAOutput &= 'not_indexed+'
	If BitAND($FAInput, 0x4000) Then $FAOutput &= 'encrypted+'
	If BitAND($FAInput, 0x8000) Then $FAOutput &= 'integrity_stream+'
	If BitAND($FAInput, 0x10000) Then $FAOutput &= 'virtual+'
	If BitAND($FAInput, 0x20000) Then $FAOutput &= 'no_scrub_data+'
	If BitAND($FAInput, 0x10000000) Then $FAOutput &= 'directory+'
	If BitAND($FAInput, 0x20000000) Then $FAOutput &= 'index_view+'
	$FAOutput = StringTrimRight($FAOutput, 1)
	Return $FAOutput
EndFunc

Func _DecodeSourceInfoFlag($input)
	Select
		Case $input = 0x00000001
			$ret = "USN_SOURCE_DATA_MANAGEMENT"
		Case $input = 0x00000002
			$ret = "USN_SOURCE_AUXILIARY_DATA"
		Case $input = 0x00000004
			$ret = "USN_SOURCE_REPLICATION_MANAGEMENT"
		Case Else
			$ret = "EMPTY"
	EndSelect
	Return $ret
EndFunc

Func _DecodeTimestamp($StampDecode)
	$StampDecode = _SwapEndian($StampDecode)
	$StampDecode_tmp = _WinTime_UTCFileTimeToLocalFileTime("0x" & $StampDecode)
	$StampDecode = _WinTime_UTCFileTimeFormat(Dec($StampDecode,2) - $tDelta, $DateTimeFormat, $TimestampPrecision)
	If @error Then
		$StampDecode = "-"
	ElseIf $TimestampPrecision = 3 Then
		$StampDecode = $StampDecode & ":" & _FillZero(StringRight($StampDecode_tmp, 4))
	EndIf
	Return $StampDecode
EndFunc

Func _UnicodeHexToStr($FileName)
   $str = ""
   For $i = 1 To StringLen($FileName) Step 4
	  $str &= ChrW(Dec(_SwapEndian(StringMid($FileName, $i, 4))))
   Next
   Return $str
EndFunc

Func _SwapEndian($iHex)
	Return StringMid(Binary(Dec($iHex,2)),3, StringLen($iHex))
EndFunc

Func _FillZero($inp)
	Local $inplen, $out, $tmp = ""
	$inplen = StringLen($inp)
	For $i = 1 To 4 - $inplen
		$tmp &= "0"
	Next
	$out = $tmp & $inp
	Return $out
EndFunc   ;==>_FillZero

Func _HexEncode($bInput)
    Local $tInput = DllStructCreate("byte[" & BinaryLen($bInput) & "]")
    DllStructSetData($tInput, 1, $bInput)
    Local $a_iCall = DllCall("crypt32.dll", "int", "CryptBinaryToString", _
            "ptr", DllStructGetPtr($tInput), _
            "dword", DllStructGetSize($tInput), _
            "dword", 11, _
            "ptr", 0, _
            "dword*", 0)

    If @error Or Not $a_iCall[0] Then
        Return SetError(1, 0, "")
    EndIf
    Local $iSize = $a_iCall[5]
    Local $tOut = DllStructCreate("char[" & $iSize & "]")
    $a_iCall = DllCall("crypt32.dll", "int", "CryptBinaryToString", _
            "ptr", DllStructGetPtr($tInput), _
            "dword", DllStructGetSize($tInput), _
            "dword", 11, _
            "ptr", DllStructGetPtr($tOut), _
            "dword*", $iSize)
    If @error Or Not $a_iCall[0] Then
        Return SetError(2, 0, "")
    EndIf
    Return SetError(0, 0, DllStructGetData($tOut, 1))
EndFunc

Func _WinTime_GetUTCToLocalFileTimeDelta()
	Local $iUTCFileTime=864000000000		; exactly 24 hours from the origin (although 12 hours would be more appropriate (max variance = 12))
	$iLocalFileTime=_WinTime_UTCFileTimeToLocalFileTime($iUTCFileTime)
	If @error Then Return SetError(@error,@extended,-1)
	Return $iLocalFileTime-$iUTCFileTime	; /36000000000 = # hours delta (effectively giving the offset in hours from UTC/GMT)
EndFunc

Func _WinTime_UTCFileTimeToLocalFileTime($iUTCFileTime)
	If $iUTCFileTime<0 Then Return SetError(1,0,-1)
	Local $aRet=DllCall($_COMMON_KERNEL32DLL,"bool","FileTimeToLocalFileTime","uint64*",$iUTCFileTime,"uint64*",0)
	If @error Then Return SetError(2,@error,-1)
	If Not $aRet[0] Then Return SetError(3,0,-1)
	Return $aRet[2]
EndFunc

Func _WinTime_UTCFileTimeFormat($iUTCFileTime,$iFormat=4,$iPrecision=0,$bAMPMConversion=False)
;~ 	If $iUTCFileTime<0 Then Return SetError(1,0,"")	; checked in below call

	; First convert file time (UTC-based file time) to 'local file time'
	Local $iLocalFileTime=_WinTime_UTCFileTimeToLocalFileTime($iUTCFileTime)
	If @error Then Return SetError(@error,@extended,"")
	; Rare occassion: a filetime near the origin (January 1, 1601!!) is used,
	;	causing a negative result (for some timezones). Return as invalid param.
	If $iLocalFileTime<0 Then Return SetError(1,0,"")

	; Then convert file time to a system time array & format & return it
	Local $vReturn=_WinTime_LocalFileTimeFormat($iLocalFileTime,$iFormat,$iPrecision,$bAMPMConversion)
	Return SetError(@error,@extended,$vReturn)
EndFunc

Func _WinTime_LocalFileTimeFormat($iLocalFileTime,$iFormat=4,$iPrecision=0,$bAMPMConversion=False)
;~ 	If $iLocalFileTime<0 Then Return SetError(1,0,"")	; checked in below call

	; Convert file time to a system time array & return result
	Local $aSysTime=_WinTime_LocalFileTimeToSystemTime($iLocalFileTime)
	If @error Then Return SetError(@error,@extended,"")

	; Return only the SystemTime array?
	If $iFormat=0 Then Return $aSysTime

	Local $vReturn=_WinTime_FormatTime($aSysTime[0],$aSysTime[1],$aSysTime[2],$aSysTime[3], _
		$aSysTime[4],$aSysTime[5],$aSysTime[6],$aSysTime[7],$iFormat,$iPrecision,$bAMPMConversion)
	Return SetError(@error,@extended,$vReturn)
EndFunc

Func _WinTime_LocalFileTimeToSystemTime($iLocalFileTime)
	Local $aRet,$stSysTime,$aSysTime[8]=[-1,-1,-1,-1,-1,-1,-1,-1]

	; Negative values unacceptable
	If $iLocalFileTime<0 Then Return SetError(1,0,$aSysTime)

	; SYSTEMTIME structure [Year,Month,DayOfWeek,Day,Hour,Min,Sec,Milliseconds]
	$stSysTime=DllStructCreate("ushort[8]")

	$aRet=DllCall($_COMMON_KERNEL32DLL,"bool","FileTimeToSystemTime","uint64*",$iLocalFileTime,"ptr",DllStructGetPtr($stSysTime))
	If @error Then Return SetError(2,@error,$aSysTime)
	If Not $aRet[0] Then Return SetError(3,0,$aSysTime)
	Dim $aSysTime[8]=[DllStructGetData($stSysTime,1,1),DllStructGetData($stSysTime,1,2),DllStructGetData($stSysTime,1,4),DllStructGetData($stSysTime,1,5), _
		DllStructGetData($stSysTime,1,6),DllStructGetData($stSysTime,1,7),DllStructGetData($stSysTime,1,8),DllStructGetData($stSysTime,1,3)]
	Return $aSysTime
EndFunc

Func _WinTime_FormatTime($iYear,$iMonth,$iDay,$iHour,$iMin,$iSec,$iMilSec,$iDayOfWeek,$iFormat=4,$iPrecision=0,$bAMPMConversion=False)
	Local Static $_WT_aMonths[12]=["January","February","March","April","May","June","July","August","September","October","November","December"]
	Local Static $_WT_aDays[7]=["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"]

	If Not $iFormat Or $iMonth<1 Or $iMonth>12 Or $iDayOfWeek>6 Then Return SetError(1,0,"")

	; Pad MM,DD,HH,MM,SS,MSMSMSMS as necessary
	Local $sMM=StringRight(0&$iMonth,2),$sDD=StringRight(0&$iDay,2),$sMin=StringRight(0&$iMin,2)
	; $sYY = $iYear	; (no padding)
	;	[technically Year can be 1-x chars - but this is generally used for 4-digit years. And SystemTime only goes up to 30827/30828]
	Local $sHH,$sSS,$sMS,$sAMPM

	; 'Extra precision 1': +SS (Seconds)
	If $iPrecision Then
		$sSS=StringRight(0&$iSec,2)
		; 'Extra precision 2': +MSMSMSMS (Milliseconds)
		If $iPrecision>1 Then
;			$sMS=StringRight('000'&$iMilSec,4)
			$sMS=StringRight('000'&$iMilSec,3);Fixed an erronous 0 in front of the milliseconds
		Else
			$sMS=""
		EndIf
	Else
		$sSS=""
		$sMS=""
	EndIf
	If $bAMPMConversion Then
		If $iHour>11 Then
			$sAMPM=" PM"
			; 12 PM will cause 12-12 to equal 0, so avoid the calculation:
			If $iHour=12 Then
				$sHH="12"
			Else
				$sHH=StringRight(0&($iHour-12),2)
			EndIf
		Else
			$sAMPM=" AM"
			If $iHour Then
				$sHH=StringRight(0&$iHour,2)
			Else
			; 00 military = 12 AM
				$sHH="12"
			EndIf
		EndIf
	Else
		$sAMPM=""
		$sHH=StringRight(0 & $iHour,2)
	EndIf

	Local $sDateTimeStr,$aReturnArray[3]

	; Return an array? [formatted string + "Month" + "DayOfWeek"]
	If BitAND($iFormat,0x10) Then
		$aReturnArray[1]=$_WT_aMonths[$iMonth-1]
		If $iDayOfWeek>=0 Then
			$aReturnArray[2]=$_WT_aDays[$iDayOfWeek]
		Else
			$aReturnArray[2]=""
		EndIf
		; Strip the 'array' bit off (array[1] will now indicate if an array is to be returned)
		$iFormat=BitAND($iFormat,0xF)
	Else
		; Signal to below that the array isn't to be returned
		$aReturnArray[1]=""
	EndIf

	; Prefix with "DayOfWeek "?
	If BitAND($iFormat,8) Then
		If $iDayOfWeek<0 Then Return SetError(1,0,"")	; invalid
		$sDateTimeStr=$_WT_aDays[$iDayOfWeek]&', '
		; Strip the 'DayOfWeek' bit off
		$iFormat=BitAND($iFormat,0x7)
	Else
		$sDateTimeStr=""
	EndIf

	If $iFormat<2 Then
		; Basic String format: YYYYMMDDHHMM[SS[MSMSMSMS[ AM/PM]]]
		$sDateTimeStr&=$iYear&$sMM&$sDD&$sHH&$sMin&$sSS&$sMS&$sAMPM
	Else
		; one of 4 formats which ends with " HH:MM[:SS[:MSMSMSMS[ AM/PM]]]"
		Switch $iFormat
			; /, : Format - MM/DD/YYYY
			Case 2
				$sDateTimeStr&=$sMM&'/'&$sDD&'/'
			; /, : alt. Format - DD/MM/YYYY
			Case 3
				$sDateTimeStr&=$sDD&'/'&$sMM&'/'
			; "Month DD, YYYY" format
			Case 4
				$sDateTimeStr&=$_WT_aMonths[$iMonth-1]&' '&$sDD&', '
			; "DD Month YYYY" format
			Case 5
				$sDateTimeStr&=$sDD&' '&$_WT_aMonths[$iMonth-1]&' '
			Case 6
				$sDateTimeStr&=$iYear&'-'&$sMM&'-'&$sDD
				$iYear=''
			Case Else
				Return SetError(1,0,"")
		EndSwitch
		$sDateTimeStr&=$iYear&' '&$sHH&':'&$sMin
		If $iPrecision Then
			$sDateTimeStr&=':'&$sSS
;			If $iPrecision>1 Then $sDateTimeStr&=':'&$sMS
			If $iPrecision>1 Then $sDateTimeStr&=$PrecisionSeparator&$sMS
		EndIf
		$sDateTimeStr&=$sAMPM
	EndIf
	If $aReturnArray[1]<>"" Then
		$aReturnArray[0]=$sDateTimeStr
		Return $aReturnArray
	EndIf
	Return $sDateTimeStr
EndFunc
