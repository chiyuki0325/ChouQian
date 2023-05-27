VERSION 5.00
Begin VB.Form frmDev 
   BackColor       =   &H80000005&
   BorderStyle     =   1  'Fixed Single
   Caption         =   "控制台"
   ClientHeight    =   5685
   ClientLeft      =   45
   ClientTop       =   390
   ClientWidth     =   4890
   BeginProperty Font 
      Name            =   "微软雅黑"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   ScaleHeight     =   5685
   ScaleWidth      =   4890
   StartUpPosition =   3  '窗口缺省
   Begin VB.Label LabelUrl 
      Alignment       =   2  'Center
      AutoSize        =   -1  'True
      BackStyle       =   0  'Transparent
      Caption         =   "LabelUrl"
      BeginProperty Font 
         Name            =   "微软雅黑"
         Size            =   9
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   225
      Left            =   2115
      TabIndex        =   1
      Top             =   5280
      Width           =   660
   End
   Begin VB.Label Label1 
      Alignment       =   2  'Center
      AutoSize        =   -1  'True
      BackStyle       =   0  'Transparent
      Caption         =   "请使用手机扫描下图二维码"
      BeginProperty Font 
         Name            =   "微软雅黑"
         Size            =   12
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      Height          =   315
      Left            =   960
      TabIndex        =   0
      Top             =   180
      Width           =   2880
   End
   Begin VB.Image ImageQR 
      Enabled         =   0   'False
      Height          =   4500
      Left            =   180
      Stretch         =   -1  'True
      Top             =   660
      Width           =   4500
   End
End
Attribute VB_Name = "frmDev"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

Dim PicLoader As New stdPicEx2

Private Sub Form_Load()
    With New WinHttpRequest
        .Open Method:="GET", _
              Url:="http://" & Config.Config.Host & "/qr/url", _
              Async:=True
        .Send
        .WaitForResponse
        Dim FrontendUrl$: FrontendUrl = JSON.parse(.ResponseText).item("url")
        With LabelUrl
            .Caption = "或在浏览器中打开 " & FrontendUrl
            .Tag = FrontendUrl
        End With
    End With
    With New WinHttpRequest
        .Open Method:="GET", _
              Url:="http://" & Config.Config.Host & "/qr/image", _
              Async:=True
        .Send
        .WaitForResponse
        ImageQR.Picture = PicLoader.LoadPictureEx(.ResponseBody)
    End With
End Sub

Private Sub LabelUrl_Click()
    Shell PathName:="cmd /c start """" " & LabelUrl.Tag, _
          WindowStyle:=vbHide
End Sub
