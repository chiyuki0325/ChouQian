VERSION 5.00
Begin VB.Form frmFloat 
   BorderStyle     =   0  'None
   Caption         =   "抽签悬浮窗"
   ClientHeight    =   1710
   ClientLeft      =   1020
   ClientTop       =   1410
   ClientWidth     =   1290
   LinkTopic       =   "Form2"
   ScaleHeight     =   1710
   ScaleWidth      =   1290
   ShowInTaskbar   =   0   'False
   Begin VB.Image Image1 
      Height          =   1245
      Left            =   30
      Stretch         =   -1  'True
      Top             =   0
      Width           =   765
   End
End
Attribute VB_Name = "frmFloat"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
Option Explicit

'用于置顶窗口的 API

Private IsDragging As Boolean
Private DragStartX!, DragStartY!, DragStartTop!, DragStartLeft!

Private Sub Form_Load()
    Dim StdPictureEx As New stdPicEx2
    Dim FSO As New FileSystemObject, BG As StdPicture
    
    '配置文件
    Config.LoadConfig
    
    '窗口初始化
    
    '置顶窗口
    Call APIs.SetWindowPos( _
        hWnd:=Me.hWnd, _
        hWndInsertAfter:=APIs.HWND_TOPMOST, _
        X:=0, Y:=0, cx:=0, cy:=0, _
        wFlags:=(APIs.SWP_NOMOVE Or APIs.SWP_NOSIZE) _
    )
    
    '加载图片
    Image1.Picture = StdPictureEx.LoadPictureEx(App.Path + "\" + Config.Config!BackgroundPath)
    Me.Height = Image1.Height
    Me.Width = Image1.Width
    
    '移动位置
    Me.Top = Screen.Height - Me.Height - 4000
    Me.Left = Screen.Width - Me.Width - 800
    
    '透明
    Me.BackColor = vbWhite
    Call APIs.SetWindowLong( _
        Me.hWnd, _
        APIs.GWL_EXSTYLE, _
        APIs.GetWindowLong(Me.hWnd, APIs.GWL_EXSTYLE) Or APIs.WS_EX_LAYERED _
    )
    Call APIs.SetLayeredWindowAttributes(Me.hWnd, vbWhite, 0&, APIs.LWA_COLORKEY)
    
    '修复 bug 最好的办法就是解决发现 bug 的人
    
    If App.LogMode <> 0 Then
        If App.PrevInstance Then
            MsgBox "禁止多开。", vbCritical
            End
        End If
    End If
    
    
    '后端
    
    If Not FSO.FileExists(App.Path + "\" + Config.Config!BackendPath) Then
        MsgBox "程序损坏，后端程序丢失。", vbCritical
        End
    Else
        '启动后端
        With New WshShell
            .Run """" + App.Path + "\" + Config.Config!BackendPath + """ """ + App.Path + "\" + Config.Config!FrontendPath + """", WshHide
        End With
    End If
End Sub

Private Sub Image1_MouseDown(Button As Integer, Shift As Integer, X As Single, Y As Single)
    If Button = 2 Then
        '退出程序
        Dim BackendPath$(), BaseName
        BackendPath = Split(Config.Config!BackendPath, "\")
        BaseName = BackendPath(UBound(BackendPath))
        With New WshShell
            .Run "taskkill /f /im " + BaseName, WshHide
        End With
        End
    ElseIf Button = 1 And Not IsDragging Then
        IsDragging = True
        DragStartX = X
        DragStartY = Y
        DragStartTop = Me.Top
        DragStartLeft = Me.Left
    End If
End Sub

Private Sub Image1_MouseMove(Button As Integer, Shift As Integer, X As Single, Y As Single)
    If IsDragging Then
        Me.Top = Me.Top + Y - DragStartY
        Me.Left = Me.Left + X - DragStartX
    End If
End Sub

Private Sub Image1_MouseUp(Button As Integer, Shift As Integer, X As Single, Y As Single)
    IsDragging = False
    Dim DraggingDelta#
    DraggingDelta = Sqr((Me.Left - DragStartLeft) ^ 2 + (Me.Top - DragStartTop) ^ 2)
    If DraggingDelta < 100 Then frmMain.ShowWindow
End Sub
