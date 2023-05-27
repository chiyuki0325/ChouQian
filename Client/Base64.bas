Attribute VB_Name = "Base64"

Public Function Base64Encode(InStr1 As String) As String
    Dim mInByte(3) As Byte, mOutByte(4) As Byte
    Dim myByte As Byte
    Dim i As Integer, LenArray As Integer, j As Integer
    Dim myBArray() As Byte
    Dim OutStr1 As String
    myBArray() = StrConv(InStr1, vbFromUnicode)
    LenArray = UBound(myBArray) + 1
    For i = 0 To LenArray Step 3
        If LenArray - i = 0 Then
            Exit For
        End If
        If LenArray - i = 2 Then
            mInByte(0) = myBArray(i)
            mInByte(1) = myBArray(i + 1)
            Base64EncodeByte mInByte, mOutByte, 2
        ElseIf LenArray - i = 1 Then
            mInByte(0) = myBArray(i)
            Base64EncodeByte mInByte, mOutByte, 1
        Else
            mInByte(0) = myBArray(i)
            mInByte(1) = myBArray(i + 1)
            mInByte(2) = myBArray(i + 2)
            Base64EncodeByte mInByte, mOutByte, 3
        End If
        For j = 0 To 3
            OutStr1 = OutStr1 & Chr(mOutByte(j))
        Next j
    Next i
    Base64Encode = OutStr1
End Function

Private Sub Base64EncodeByte(mInByte() As Byte, mOutByte() As Byte, Num As Integer)
    Dim tByte As Byte
    Dim i As Integer
    If Num = 1 Then
        mInByte(1) = 0
        mInByte(2) = 0
    ElseIf Num = 2 Then
        mInByte(2) = 0
    End If
    tByte = mInByte(0) And &HFC
    mOutByte(0) = tByte / 4
    tByte = ((mInByte(0) And &H3) * 16) + (mInByte(1) And &HF0) / 16
    mOutByte(1) = tByte
    tByte = ((mInByte(1) And &HF) * 4) + ((mInByte(2) And &HC0) / 64)
    mOutByte(2) = tByte
    tByte = (mInByte(2) And &H3F)
    mOutByte(3) = tByte
    For i = 0 To 3
        If mOutByte(i) >= 0 And mOutByte(i) <= 25 Then
            mOutByte(i) = mOutByte(i) + Asc("A")
        ElseIf mOutByte(i) >= 26 And mOutByte(i) <= 51 Then
            mOutByte(i) = mOutByte(i) - 26 + Asc("a")
        ElseIf mOutByte(i) >= 52 And mOutByte(i) <= 61 Then
            mOutByte(i) = mOutByte(i) - 52 + Asc("0")
        ElseIf mOutByte(i) = 62 Then
            mOutByte(i) = Asc("+")
        Else
            mOutByte(i) = Asc("/")
        End If
    Next i
    If Num = 1 Then
        mOutByte(2) = Asc("=")
        mOutByte(3) = Asc("=")
    ElseIf Num = 2 Then
        mOutByte(3) = Asc("=")
    End If
End Sub
Public Function Base64Decode(InStr1 As String) As String
    Dim mInByte(4) As Byte, mOutByte(3) As Byte
    Dim i As Integer, LenArray As Integer, j As Integer
    Dim myBArray() As Byte
    Dim OutStr1 As String
    Dim tmpArray() As Byte
    myBArray() = StrConv(InStr1, vbFromUnicode)
    LenArray = UBound(myBArray)
    ReDim tmpArray(((LenArray + 1) / 4) * 3)
    j = 0
    For i = 0 To LenArray Step 4
        If LenArray - i = 0 Then
            Exit For
        Else
            mInByte(0) = myBArray(i)
            mInByte(1) = myBArray(i + 1)
            mInByte(2) = myBArray(i + 2)
            mInByte(3) = myBArray(i + 3)
            Base64DecodeByte mInByte, mOutByte, 4
        End If
        tmpArray(j * 3) = mOutByte(0)
        tmpArray(j * 3 + 1) = mOutByte(1)
        tmpArray(j * 3 + 2) = mOutByte(2)
        j = j + 1
    Next i
    Base64Decode = BinaryToString(tmpArray)
End Function

Private Sub Base64DecodeByte(mInByte() As Byte, mOutByte() As Byte, ByteNum As Integer)
    Dim tByte As Byte
    Dim i As Integer
    ByteNum = 0
    For i = 0 To 3
        If mInByte(i) >= Asc("A") And mInByte(i) <= Asc("Z") Then
            mInByte(i) = mInByte(i) - Asc("A")
        ElseIf mInByte(i) >= Asc("a") And mInByte(i) <= Asc("z") Then
            mInByte(i) = mInByte(i) - Asc("a") + 26
        ElseIf mInByte(i) >= Asc("0") And mInByte(i) <= Asc("9") Then
            mInByte(i) = mInByte(i) - Asc("0") + 52
        ElseIf mInByte(i) = Asc("+") Then
            mInByte(i) = 62
        ElseIf mInByte(i) = Asc("/") Then
            mInByte(i) = 63
        Else   '"="
            ByteNum = ByteNum + 1
            mInByte(i) = 0
        End If
    Next i
    '取前六位
    tByte = (mInByte(0) And &H3F) * 4 + (mInByte(1) And &H30) / 16
    '0的六位和1的前两位
    mOutByte(0) = tByte
    tByte = (mInByte(1) And &HF) * 16 + (mInByte(2) And &H3C) / 4
    '1的后四位和2的前四位
    mOutByte(1) = tByte
    tByte = (mInByte(2) And &H3) * 64 + (mInByte(3) And &H3F)
    mOutByte(2) = tByte
    '2的后两位和3的六位
End Sub
Private Function BinaryToString(ByVal BinaryStr As Variant) As String    '二进制转换为字符串
    Dim lnglen As Long
    Dim tmpBin As Variant
    Dim strC As String
    Dim skipflag As Long
    Dim i As Long
    skipflag = 0
    strC = ""
    If Not IsNull(BinaryStr) Then
        lnglen = LenB(BinaryStr)
        For i = 1 To lnglen
            If skipflag = 0 Then
                tmpBin = MidB(BinaryStr, i, 1)
                If AscB(tmpBin) > 127 Then
                    strC = strC & Chr(AscW(MidB(BinaryStr, i + 1, 1) & tmpBin))
                    skipflag = 1
                Else
                    strC = strC & Chr(AscB(tmpBin))
                End If
            Else
                skipflag = 0
            End If
        Next
    End If
    BinaryToString = strC
End Function

Private Function StringToBinary(ByVal VarString As String) As Variant    '字符串转成二进制
    Dim strBin As Variant
    Dim varchar As Variant
    Dim varasc As Long
    Dim varlow, varhigh
    Dim i As Long
    strBin = ""
    For i = 1 To Len(VarString)
        varchar = Mid(VarString, i, 1)
        varasc = Asc(varchar)
        If varasc < 0 Then
            varasc = varasc + 65535
        End If
        If varasc > 255 Then
            varlow = Left(Hex(Asc(varchar)), 2)
            varhigh = Right(Hex(Asc(varchar)), 2)
            strBin = strBin & ChrB("&H" & varlow) & ChrB("&H" & varhigh)
        Else
            strBin = strBin & ChrB(AscB(varchar))
        End If
    Next
    StringToBinary = strBin
End Function
