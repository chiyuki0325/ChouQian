VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "stdPicEx2"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = True
Option Explicit

' Coder notes: Jump to bottom of class for history of recent updates
'   Comments in this code may use the word subclassing. Subclassing the COM stdPicture
'   and IPicture objects is NOT technically done. What we do is create a copy of
'   the COM VTables and then redirect individual picture objects to that copy. The
'   original COM VTables are unmolested. Instead, the copy points to our thunk.
'   VB shares just one, maybe two, VTables for every created picture object
' --------------------------------------------------------------------------------------------

' The following event is sent whenever LoadPictureEx is called and before the image
'   is finalized and placed into a stdPicture object. This event allows you to
'   make any final changes to parameters before the LoadPictureEx function returns.
Public Event PreLoadPicture(ByVal PicType As PictTypeEx, PicProps() As Long, _
        ManageStyle As ManagementStyle, KeepOriginalFormat As Boolean, _
        IconIndex As Long, IconCx As Long, IconCy As Long, IconDepth As Long, _
        TransparencyFillColor As OLE_COLOR, _
        AbortLoading As Boolean, pLoadPicEventParam As Variant)
' The event is not called if LoadPictureEx is passed an image handle as the source.
' To receive this event, you must declare this class using keyword: WithEvents
' /// Parameters...
' PicProps() is a 2D array, sized: (0 to 2, 1 to n)
'   first 2 items in 1st dimension is the image width and height, respectively
'   3rd item in that dimension depends on the image type; psuedo-code follows
'   Select Case PicType
'       Case picBmp: PicProps(2,1) is AlphaTypeEnum value
'       Case picGIF, picTIF, picPNG ' 1st byte is AlphaTypeEnum, remaining bytes are frame/page count
'           (PicProps(2,1) \ &H10) is frame/page count
'           (PicProps(2,1) And &HF) is AlphaTypeEnum value ' if multi-frame/page, value is for 1st frame only
'       Case picWMF, picEMF: PicProps(2,1) is non-zero only if WMF is non-placeable
'           ' non-placeable WMF have no true width/height values; these are unknown
'       Case picJPG: PicProps(2,1) is non-zero only if orentiation correction should be applied
'           ' FYI: Enhanced/AutoSelect management style applies orientation correction
'       Case picICO, picCUR
'           ' UBound(PicProps(), 2) is the number of icons/cursors in the source format
'           For n = 1 to UBound(PicProps(), 2)
'               PicProps(0, n), PicProps(1, n) are dimensions for SubImage #n
'               PicProps(2, n) is bit count for SubImage #n
'           Next
'           ' use this info to set the IconIndex, IconCx, IconCy, IconDepth params if desired
'   End Select
' ManageStyle & KeepOriginalFormat reflect any change the function may make when passed ManageStyle of AutoSelect
' AbortLoading is defaulted to False. Change to True to prevent returning a picture
' pLoadPicEventParam is the optional pLoadPicEventParam value you passed to LoadPictureEx
' Remaining parameters are same as passed to LoadPictureEx and can be changed as desired
'   see LoadPictureEx for detailed description of those parameters

' Following event is used to simply help you remember that you can't get callbacks
' without the class being declared "WithEvents". Calling SetCallbacks function
' will generate an error if this event is not handled.
Public Event EventHandler(isHandled As Boolean)
'^^ must pass isHandled = True to receive any callbacks

' for rendering events below...
' Key parameter was set during your call to SetCallbacks
' hDC parameter is target DC, never wrapped by GDI+ hGraphics, when event called
' IPicture passed instead of stdPicture, because it offers same as stdPicture + more
' destination params are always pixels & values can be changed by you
' for the PreRender & PostRender events, the source params are either pixels or
'       himetric, depending on your choice when SetCallbacks was called. When
'       pixels, values are appropriate for APIs. When himetric, values are
'       appropriate for stdPicture/IPicture.Render
'    hImageGDIplus, when non-zero, indicates GDI+ was or will be used for rendering
Public Event PreRender(Key As String, thePicture As IPicture, _
                       ByVal hDC As Long, ByRef dstX As Long, ByRef dstY As Long, _
                       ByRef dstCx As Long, ByRef dstCy As Long, _
                       ByVal srcX As Long, ByVal srcY As Long, _
                       ByVal srcCx As Long, ByVal srcCy As Long, _
                       ByVal hImageGDIplus As Long, ByRef bufferHDC As Long, _
                       ByRef IgnoreBufferDestParams As Boolean, ByRef DoNotRender As Boolean)
' Pre-Render event...
' DoNotRender parameter, set to True on return, prevents thunk from rendering
' BufferHDC notes:
'   1. That parameter is initially set to the original target DC. You can change
'   this if you want the rendering to be sent to a backbuffer (flicker free intent)
'   or to a different VB control's hDC. In either case, obviously you would change
'   the destination parameters relative to the target DC. If you created the
'   BufferHDC, receiving post-render callbacks returns the BufferHDC which may
'   require destruction by you.
'   2. In this event, typically you would BitBlt hDC into BufferHDC
'   3. You can do all the drawing to a backbuffer within this event and do
'       not need to use the bufferHDC parameter. If you want the backbuffer
'       passed to the SetHGraphics and/or PostRender events, then it is useful
' IgnoreBufferDestParams notes:
'   when returned as false (default), any changed destination parameters are sent to
'   the PostRender event. Otherwise, original parameters are sent to PostRender event
Public Event PostRender(Key As String, thePicture As IPicture, _
                       ByVal hDC As Long, ByRef dstX As Long, ByRef dstY As Long, _
                       ByRef dstCx As Long, ByRef dstCy As Long, _
                       ByVal srcX As Long, ByVal srcY As Long, _
                       ByVal srcCx As Long, ByVal srcCy As Long, _
                       ByVal hImageGDIplus As Long, ByVal bufferHDC As Long)
' Post-Render event...
' BufferHDC notes if you provided a backbuffer DC in the PreRender event
'   1. In this event, typically you would BitBlt BufferHDC into visible hDC
'   2. In this event you would destroy the backbuffer DC as needed
'   3. Whether you provided a backbuffer DC or not is easy enough to check:
'       If BufferHDC <> hDC Then buffer used
Public Event SetHGraphics(Key As String, ByVal hGraphics As Long, _
                          ByRef dstX As Long, ByRef dstY As Long, _
                          ByRef dstCx As Long, ByRef dstCy As Long, _
                          thePicture As IPicture, ByVal hImageGDIplus As Long)
' SetHGraphics event...
' when pre-render events are requested and GDI+ will be used, this event is called
'   Occurs after PreRender event is sent, before any drawing by GDI+, and allows you
'       to modify the GDI+ hGraphics context, as desired
' note: any changes to destination parameters are for hGraphics only, not carried to PostRender event.
' though the event is not intended to be used for drawing, there is nothing stopping you. The
'   parameters include all the info you should need, either directly or indirectly
Public Event OwnerDrawn(Key As String, thePicture As IPicture, ByVal hDC As Long, _
                        ByVal dstX As Long, ByVal dstY As Long, _
                        ByVal dstCx As Long, ByVal dstCy As Long)
' ^^ special callback for ownerdrawn management style only. See SetOwnerDrawn function

Public Enum PictTypeEx
    picUnknown = vbPicTypeNone
    picBMP = vbPicTypeBitmap    ' bitmap (with/without alpha channel)
    picWMF = vbPicTypeMetafile  ' not managed by this class
    picEMF = vbPicTypeEMetafile ' not managed by this class
    picICO = vbPicTypeIcon      ' includes XP & Vista style icons (alpha and/or PNG-encoded)
    picCUR = 5                  ' cursors reflected as icon if original data not kept
    picJPG = 6                  ' reflected as bitmap if original data not kept
    picPNG = 7                  ' reflected as bitmap if original data not kept
    picGIF = 8                  ' reflected as bitmap if original data not kept
    picTIF = 9                  ' reflected as bitmap if original data not kept
'   picAPNG = 15                ' reserved. private constant for internal use only
End Enum
Private Const picAPNG As Long = 15 ' internal use only
Public Enum RenderEvents        ' enumeration for: SetCallBacks function
    rcbkNoCallbacks = 0         ' remove callbacks
    rcbkPreRenderOnly = 1       ' pre-render event only
    rcbkPostRenderOnly = 2      ' post-render event only
    rcbkBothPrePostRender = 3   ' pre/post-render events
    rcbkOwnerDrawn = 4          ' Required for owner drawn management style
End Enum
Public Enum ScalingQuality      ' enumeration for SetScalingQuality function
    sqNoGDIplusScaling = 0      ' if only reason to use GDI+ is for scaling, don't use GDI+
    sqNearestNeighbor = 1       ' GDI+ nearest-neighbor scaling algo
    sqBilinear = 2              ' GDI+ bilinear scaling algo
    sqBicubic = 3               ' GDI+ bicubic scaling algo
End Enum
Public Enum ManagementStyle     ' LoadPictureEx/CopyStdPicture parameter value
    mgtAutoSelect = -1          ' select style & format caching to favor transparency, low memory usage
    mgtVbOnly = 0               ' picture not managed, VB owns it 100%, similar to not using this class
    mgtVbPlus = 1               ' VB renders it, can request events & cache original image format
    mgtEnhanced = 2             ' GDI+ enabled for rendering, events enabled, and more
    mgtOwnerDrawn = 3           ' rendered by you via events, VB nor thunk renders image, events required
End Enum
Public Enum AlphaTypeEnum       ' enumeration for HasTransparency function/property
    alphaNone = 0
    alphaStandard = 1           ' standard alpha format as used in GIF, icons, most everything
    alphaPreMultiplied = 2      ' premultiplied R,G,B channels against the alpha channel
End Enum

' used to obtain system DPI when your app is DPI-aware
Private Declare Function GetDC Lib "user32.dll" (ByVal hWnd As Long) As Long
Private Declare Function GetDeviceCaps Lib "gdi32.dll" (ByVal hDC As Long, ByVal nIndex As Long) As Long
Private Declare Function ReleaseDC Lib "user32.dll" (ByVal hWnd As Long, ByVal hDC As Long) As Long

' used to read/write/create IStream
Private Declare Function GetHGlobalFromStream Lib "ole32.dll" (ByVal ppstm As Long, hGlobal As Long) As Long
Private Declare Function CreateStreamOnHGlobal Lib "ole32.dll" (ByVal hGlobal As Long, ByVal fDeleteOnRelease As Long, ppstm As Any) As Long
Private Declare Function GlobalAlloc Lib "kernel32.dll" (ByVal uFlags As Long, ByVal dwBytes As Long) As Long
Private Declare Function GlobalLock Lib "kernel32" (ByVal hMem As Long) As Long
Private Declare Function GlobalUnlock Lib "kernel32.dll" (ByVal hMem As Long) As Long
Private Declare Function GlobalFree Lib "kernel32.dll" (ByVal hMem As Long) As Long

' GDI+ APIs
Private Declare Function GdipLoadImageFromStream Lib "GdiPlus.dll" (ByVal Stream As Long, hImage As Long) As Long
Private Declare Function GdipDisposeImage Lib "GdiPlus.dll" (ByVal hImage As Long) As Long
Private Declare Function GdipCreateBitmapFromHBITMAP Lib "GdiPlus.dll" (ByVal pbitmap As Long, ByVal hPal As Long, ByRef hbmReturn As Long) As Long
Private Declare Function GdipCreateHBITMAPFromBitmap Lib "GdiPlus.dll" (ByVal pbitmap As Long, ByRef hBmp As Long, ByVal Color As Long) As Long
Private Declare Function GdiplusStartup Lib "GdiPlus.dll" (Token As Long, inputbuf As Any, Optional ByVal outputbuf As Long = 0) As Long
Private Declare Function GdiplusShutdown Lib "GdiPlus.dll" (Token As Long) As Long
Private Declare Function GdipGetImageHorizontalResolution Lib "GdiPlus.dll" (ByVal pImage As Long, ByRef resolution As Single) As Long
Private Declare Function GdipGetImageFlags Lib "GdiPlus.dll" (ByVal pImage As Long, ByRef lFlags As Long) As Long
Private Declare Function GdipImageSelectActiveFrame Lib "GdiPlus.dll" (ByVal Image As Long, ByRef dimensionID As Any, ByVal FrameIndex As Long) As Long
Private Declare Function GdipImageGetFrameCount Lib "GdiPlus.dll" (ByVal Image As Long, ByRef dimensionID As Any, ByRef Count As Long) As Long
Private Declare Function GdipImageGetFrameDimensionsCount Lib "GdiPlus.dll" (ByVal pImage As Long, ByRef Count As Long) As Long
Private Declare Function GdipImageGetFrameDimensionsList Lib "GdiPlus.dll" (ByVal pImage As Long, ByRef dimensionIDs As Any, ByVal Count As Long) As Long
Private Declare Function GdipGetImageRawFormat Lib "GdiPlus.dll" (ByVal hImage As Long, ByVal GUID As Long) As Long
Private Declare Function GdipBitmapLockBits Lib "GdiPlus.dll" (ByVal mBitmap As Long, ByVal mRect As Long, ByVal mFlags As Long, ByVal mPixelFormat As Long, ByVal mLockedBitmapData As Long) As Long
Private Declare Function GdipBitmapUnlockBits Lib "GdiPlus.dll" (ByVal mBitmap As Long, ByVal mLockedBitmapData As Long) As Long
Private Declare Function GdipDrawImageRectRectI Lib "GdiPlus.dll" (ByVal hGraphics As Long, ByVal hImage As Long, ByVal dstX As Long, ByVal dstY As Long, ByVal dstWidth As Long, ByVal dstHeight As Long, ByVal srcX As Long, ByVal srcY As Long, ByVal srcWidth As Long, ByVal srcHeight As Long, ByVal SRCUNIT As Long, ByVal imageAttributes As Long, ByVal Callback As Long, ByVal callbackData As Long) As Long
Private Declare Function GdipGetImageBounds Lib "GdiPlus.dll" (ByVal nImage As Long, srcRect As Any, SRCUNIT As Long) As Long
Private Declare Function GdipDeleteGraphics Lib "GdiPlus.dll" (ByVal mGraphics As Long) As Long
Private Declare Function GdipCreateFromHDC Lib "GdiPlus.dll" (ByVal hDC As Long, hGraphics As Long) As Long
Private Declare Function GdipCreateBitmapFromScan0 Lib "GdiPlus.dll" (ByVal Width As Long, ByVal Height As Long, ByVal stride As Long, ByVal PixelFormat As Long, ByVal scan0 As Long, hBitmap As Long) As Long
Private Declare Function GdipImageRotateFlip Lib "GdiPlus.dll" (ByVal pImage As Long, ByVal rfType As Long) As Long
Private Declare Function GdipGetPropertyItemSize Lib "GdiPlus.dll" (ByVal pImage As Long, ByVal propId As Long, ByRef pSize As Long) As Long
Private Declare Function GdipGetPropertyItem Lib "GdiPlus.dll" (ByVal pImage As Long, ByVal propId As Long, ByVal propSize As Long, ByRef buffer As Any) As Long
Private Declare Function GdipGetImagePixelFormat Lib "GdiPlus.dll" (ByVal hImage As Long, PixelFormat As Long) As Long
Private Declare Function GdipSetInterpolationMode Lib "GdiPlus.dll" (ByVal graphics As Long, ByVal Mode As Long) As Long
Private Declare Function GdipCloneImageAttributes Lib "GdiPlus.dll" (ByVal imageattr As Long, ByRef imageattrClone As Long) As Long
Private Declare Function GdipDisposeImageAttributes Lib "GdiPlus.dll" (ByVal imageattr As Long) As Long
Private Declare Function GdipCreateImageAttributes Lib "GdiPlus.dll" (ByRef imageattr As Long) As Long
Private Declare Function GdipSetImageAttributesWrapMode Lib "GdiPlus.dll" (ByVal imageattr As Long, ByVal wrap As Long, ByVal pColor As Long, ByVal clamp As Long) As Long

' APIs solely for APNG support
Private Declare Function GdipSetPropertyItem Lib "GdiPlus.dll" (ByVal pImage As Long, ByRef item As Any) As Long
Private Declare Function GdipSetCompositingMode Lib "gdiplus" (ByVal graphics As Long, ByVal compositingMode As Long) As Long
Private Declare Function GdipSetClipRectI Lib "gdiplus" (ByVal graphics As Long, ByVal X As Long, ByVal Y As Long, ByVal nWidth As Long, ByVal nHeight As Long, ByVal combineMode As Long) As Long
Private Declare Function GdipGetImageGraphicsContext Lib "GdiPlus.dll" (ByVal pImage As Long, ByRef graphics As Long) As Long
Private Declare Function GdipGraphicsClear Lib "GdiPlus.dll" (ByVal graphics As Long, ByVal pColor As Long) As Long
Private Declare Function GdipSaveAdd Lib "GdiPlus.dll" (ByVal mImage As Long, ByRef mEncoderParams As Any) As Long
Private Declare Function GdipSaveAddImage Lib "GdiPlus.dll" (ByVal pImage As Long, ByVal newImage As Long, ByRef encoderParams As Any) As Long
Private Declare Function GdipSaveImageToStream Lib "GdiPlus.dll" (ByVal Image As Long, ByVal Stream As IUnknown, clsidEncoder As Any, encoderParams As Any) As Long
Private Declare Function GdipGetImageEncoders Lib "GdiPlus.dll" (ByVal numEncoders As Long, ByVal Size As Long, Encoders As Any) As Long
Private Declare Function GdipGetImageEncodersSize Lib "GdiPlus.dll" (numEncoders As Long, Size As Long) As Long
Private Declare Function lstrlenW Lib "kernel32.dll" (ByVal psString As Long) As Long

' used to setup initial thunk and/or find existing thunk
Private Declare Function CreateWindowEx Lib "user32.dll" Alias "CreateWindowExA" (ByVal dwExStyle As Long, ByVal lpClassName As String, ByVal lpWindowName As String, ByVal dwStyle As Long, ByVal X As Long, ByVal Y As Long, ByVal nWidth As Long, ByVal nHeight As Long, ByVal hWndParent As Long, ByVal hMenu As Long, ByVal hInstance As Long, ByRef lpParam As Any) As Long
Private Declare Function FindWindow Lib "user32.dll" Alias "FindWindowA" (ByVal lpClassName As String, ByVal lpWindowName As String) As Long
Private Declare Function GetWindowThreadProcessId Lib "user32.dll" (ByVal hWnd As Long, ByRef lpdwProcessId As Long) As Long
Private Declare Function GetWindow Lib "user32.dll" (ByVal hWnd As Long, ByVal wCmd As Long) As Long
Private Declare Function FindWindowEx Lib "user32.dll" Alias "FindWindowExA" (ByVal hWndParent As Long, ByVal hWndChildAfter As Long, ByVal lpszClass As String, ByVal lpszWindow As String) As Long
Private Declare Function SendMessage Lib "user32.dll" Alias "SendMessageA" (ByVal hWnd As Long, ByVal wMsg As Long, ByVal wParam As Long, ByRef lParam As Any) As Long
Private Declare Function GetWindowLong Lib "user32.dll" Alias "GetWindowLongA" (ByVal hWnd As Long, ByVal nIndex As Long) As Long
Private Declare Function DestroyWindow Lib "user32.dll" (ByVal hWnd As Long) As Long
Private Declare Function FreeLibrary Lib "kernel32.dll" (ByVal hLibModule As Long) As Long
Private Declare Function LoadLibrary Lib "kernel32.dll" Alias "LoadLibraryA" (ByVal lpLibFileName As String) As Long
Private Declare Function VirtualAlloc Lib "kernel32.dll" (ByVal lpAddress As Long, ByVal dwSize As Long, ByVal flAllocationType As Long, ByVal flProtect As Long) As Long
Private Declare Function VirtualFree Lib "kernel32.dll" (ByVal lpAddress As Long, ByVal dwSize As Long, ByVal dwFreeType As Long) As Long
Private Declare Function GetModuleHandleA Lib "kernel32" (ByVal lpModuleName As String) As Long
Private Declare Function GetProcAddress Lib "kernel32" (ByVal hModule As Long, ByVal lpProcName As String) As Long
Private Declare Function SetWindowLong Lib "user32.dll" Alias "SetWindowLongA" (ByVal hWnd As Long, ByVal nIndex As Long, ByVal dwNewLong As Long) As Long

' used for LoadPictureEx
Private Declare Function ReadFile Lib "kernel32.dll" (ByVal hFile As Long, ByRef lpBuffer As Any, ByVal nNumberOfBytesToRead As Long, ByRef lpNumberOfBytesRead As Long, ByRef lpOverlapped As Any) As Long
Private Declare Function WriteFile Lib "kernel32.dll" (ByVal hFile As Long, lpBuffer As Any, ByVal nNumberOfBytesToWrite As Long, lpNumberOfBytesWritten As Long, lpOverlapped As Any) As Long
Private Declare Function CreateFileW Lib "kernel32.dll" (ByVal lpFileName As Long, ByVal dwDesiredAccess As Long, ByVal dwShareMode As Long, ByVal lpSecurityAttributes As Long, ByVal dwCreationDisposition As Long, ByVal dwFlagsAndAttributes As Long, ByVal hTemplateFile As Long) As Long
Private Declare Function CloseHandle Lib "kernel32.dll" (ByVal hObject As Long) As Long
Private Declare Function GetFileSize Lib "kernel32.dll" (ByVal hFile As Long, ByRef lpFileSizeHigh As Long) As Long
Private Declare Function GetIconInfo Lib "user32.dll" (ByVal hIcon As Long, ByRef piconinfo As Any) As Long
Private Declare Function GetDIBits Lib "gdi32.dll" (ByVal aHDC As Long, ByVal hBitmap As Long, ByVal nStartScan As Long, ByVal nNumScans As Long, ByRef lpBits As Any, ByRef lpBI As Any, ByVal wUsage As Long) As Long
Private Declare Function SetDIBits Lib "gdi32.dll" (ByVal hDC As Long, ByVal hBitmap As Long, ByVal nStartScan As Long, ByVal nNumScans As Long, ByRef lpBits As Any, ByRef lpBI As Any, ByVal wUsage As Long) As Long
Private Declare Function CopyImage Lib "user32.dll" (ByVal hHandle As Long, ByVal un1 As Long, ByVal n1 As Long, ByVal n2 As Long, ByVal un2 As Long) As Long
Private Declare Function GetObjectA Lib "gdi32.dll" (ByVal hObject As Long, ByVal nCount As Long, ByRef lpObject As Any) As Long
Private Declare Function GetSysColor Lib "user32.dll" (ByVal nIndex As Long) As Long
Private Declare Function CreateIconFromResourceEx Lib "user32.dll" (ByRef presbits As Any, ByVal dwResSize As Long, ByVal fIcon As Long, ByVal dwVer As Long, ByVal cxDesired As Long, ByVal cyDesired As Long, ByVal Flags As Long) As Long
Private Declare Function GetSystemMetrics Lib "user32.dll" (ByVal nIndex As Long) As Long
Private Declare Function GdipGetHemfFromMetafile Lib "GdiPlus.dll" (ByVal metafile As Long, ByRef hEMF As Long) As Long
Private Declare Function GdipEmfToWmfBits Lib "GdiPlus.dll" (ByVal hEMF As Long, ByVal cbData16 As Long, ByVal pData16 As Long, ByVal iMapMode As Long, ByVal eFlags As Long) As Long
Private Declare Function DeleteEnhMetaFile Lib "gdi32.dll" (ByVal hEMF As Long) As Long

' used for managing stdPictures
Private Declare Function OleLoadPicture Lib "oleaut32.dll" (ByVal pStream As Long, ByVal lSize As Long, ByVal fRunmode As Long, riid As Any, ppvObj As Any) As Long
Private Declare Function OleCreatePictureIndirect Lib "oleaut32.dll" (lpPictDesc As Any, riid As Any, ByVal fPictureOwnsHandle As Long, iPic As IPicture) As Long
Private Declare Function SysAllocStringLen Lib "oleaut32.dll" (ByVal OleStr As Long, ByVal bLen As Long) As Long
Private Declare Sub SysFreeString Lib "oleaut32.dll" (ByVal OleStr As Long)
Private Declare Sub CopyMemory Lib "kernel32.dll" Alias "RtlMoveMemory" (ByRef Destination As Any, ByRef Source As Any, ByVal length As Long)
Private Declare Sub FillMemory Lib "kernel32.dll" Alias "RtlFillMemory" (ByRef Destination As Any, ByVal length As Long, ByVal Fill As Byte)
Private Declare Function VarPtrArray Lib "msvbvm60.dll" Alias "VarPtr" (var() As Any) As Long
Private Declare Sub CoTaskMemFree Lib "ole32.dll" (ByVal pv As Long)
Private Declare Function CoTaskMemAlloc Lib "ole32.dll" (ByVal cb As Long) As Long
Private Declare Function CoTaskMemRealloc Lib "ole32.dll" (ByVal pv As Long, ByVal cb As Long) As Long
Private Declare Function CallThunk Lib "user32.dll" Alias "CallWindowProcA" (ByVal thunkAddr As Long, ByVal Criteria As Long, ByVal uMsg As ThunkMessagesEnum, Optional ByVal Param As Long = 0&, Optional ByVal vParam As Long = 0&) As Long

Private Declare Function CreateCompatibleDC Lib "gdi32.dll" (ByVal hDC As Long) As Long
Private Declare Function CreateDIBSection Lib "gdi32.dll" (ByVal hDC As Long, ByRef pBitmapInfo As Any, ByVal un As Long, ByRef lplpVoid As Long, ByVal hHandle As Long, ByVal dw As Long) As Long
Private Declare Function DeleteDC Lib "gdi32.dll" (ByVal hDC As Long) As Long
Private Declare Function DeleteObject Lib "gdi32.dll" (ByVal hObject As Long) As Long
Private Declare Function GetDesktopWindow Lib "user32.dll" () As Long
Private Declare Function SelectObject Lib "gdi32.dll" (ByVal hDC As Long, ByVal hObject As Long) As Long
Private Declare Function IIDFromString Lib "ole32.dll" (ByVal lpsz As Long, ByRef lpiid As Any) As Long
Private Declare Function CreateIconIndirect Lib "user32.dll" (ByRef piconinfo As Any) As Long
Private Declare Function DestroyIcon Lib "user32.dll" (ByVal hIcon As Long) As Long
Private Declare Function CreateBitmap Lib "gdi32.dll" (ByVal nWidth As Long, ByVal nHeight As Long, ByVal nPlanes As Long, ByVal nBitCount As Long, ByRef lpBits As Any) As Long
Private Declare Function CreateSolidBrush Lib "gdi32.dll" (ByVal crColor As Long) As Long
Private Declare Function FillRect Lib "user32.dll" (ByVal hDC As Long, ByRef lpRect As Any, ByVal hBrush As Long) As Long

Private Type BITMAP             ' primarily used to test for DIB vs DDB and bit count of hBitmap
    bmType As Long
    bmWidth As Long
    bmHeight As Long
    bmWidthBytes As Long
    bmPlanes As Integer
    bmBitsPixel As Integer
    bmBits As Long              ' 0 = DDB, non-zero = DIB (preferred for bitmaps <= 8 bpp)
End Type
Private Type BitmapData         ' 2 combined GDI+ structures used for reading/writing GDI+ pixel data
    bpLeft As Long              ' {GDI+ RECTI begins here...
    bpTop As Long
    bpWidth As Long             ' {GDI+ BitmapData begins here...
    bpHeight As Long            ' } GDI+ RECTI final member
    bpStride As Long
    bpPixelFormat As Long
    bpScan0Ptr As Long
    bpReserved As Long          ' } GDI+ BitmapData final member
End Type
' remaining structures below are for APNG support
Private Type APNGfDatStruct
    Pointer As Long                 ' pointer in source data where frame image data block begins
    length As Long                  ' length of the image data block
End Type
Private Type APNGFrameStruct
    DatCount As Long                ' how many blocks for entire frame; number of fDat() entries
    fDat() As APNGfDatStruct        ' collection of data block info
    Delay As Long                   ' frame delay
    Size(0 To 3) As Long            ' frame position within overall image
    Disposal As Integer             ' packed: 1st byte = disposal code; 2nd byte = transparency usage (ROP)
End Type
Private Type APNGDataStruct
    FrameCount As Long              ' number of frames; number of Frames() entries
    Frames() As APNGFrameStruct     ' collection of frame structures
    Loops As Long                   ' number of animation loops
    Offset As Long                  ' offset where 1st data block will begin in the stream
    Size(0 To 1) As Long            ' size of the overall image
    Frame As Long                   ' current frame
    Flags As Long                   ' packed: 1st bit = PNG Code 2 usage; 2nd bit = IDAT not used in animation
End Type
Private Type EncoderParameter       ' GDI+ image format encoding structure
    GUID(0 To 3)   As Long          ' http://www.jose.it-berater.org/gdiplus/iframe/index.htm (Constants | Image Encoder)
    NumberOfValues As Long          ' number of values
    Type           As Long          ' GDI+ EncoderParameterValueType enum value
    Value          As Long          ' memory location of value(s)
End Type
'-- Encoder Parameters structure; sized for multi-page TIFF (3 parameter structures)
Private Type EncoderParameters
    Count     As Long               ' number of EncoderParameter structures
    Parameter(0 To 2) As EncoderParameter
End Type

' note: arrays are often used instead of declaring structures. Some examples:
' BITMAPINFOHEADER faux structure as 10+ item Long array:
'    0 = biSize
'    1 = biWidth
'    2 = biHeight
'    3 = packed biPlanes & biBitCount
'    4 = biCompression
'    5 = biSizeImage
'    6,7 = biXPelsPerMeter,biYPelsPerMeter
'    8 = biClrUsed
'    9 = biClrImportant
'  10+ = depends on header version and needs
' ICONINFO faux structure as 5 item Long array
'    0 = fIcon
'    1 = xHotSpot
'    2 = yHotSpot
'    3 = mask hBitmap
'    4 = color hBitmap
' GDI+ RECTF faux structure as 4 item Single array:
'    0 = Left
'    1 = Top
'    2 = Width
'    3 = Height
' COM SafeArray as 6 item Long array:
'    0 = packed cDims & fFeatures
'    1 = cbElements
'    2 = cLocks
'    3 = pvData
'    4 = nrElements
'    5 = LBound

Private Enum ThunkMessagesEnum
    ' note: for messages 0-17, CallThunk vParam can return record version: VarPtr(lVersion)
    msgObjPtrIndex = 0          ' look for picture object or find empty record in collection
    msgUnsubclass = 1           ' remove records for managed picture; called in UnmanagePicture
    msgObjGetVTable = 2         ' return IPicture vtable for managed picture
    msgObjGetFlags = 3          ' return flags/options
    msgObjSetFlags = 4          ' set flags/options
    msgObjSetGDIpArr = 5        ' set GDI+ related record pointer
    msgObjGetGDIpArr = 6        ' return GDI+ releated record pointer
    msgObjGetHImage = 7         ' return GDI+ image handle
    msgObjGetHAttrs = 8         ' return GDI+ image attributes handle
    msgObjGetStream = 9         ' return stream pointer
    msgObjGetStrmSize = 10      ' return stream size
    msgObjSetHAttrs = 11        ' set user-defined GDI+ image attributes handle
    msgObjGetCBaddr = 12        ' return callback record address
    msgObjGetKey = 13           ' return callback Key
    msgObjGetClassPtr = 14      ' return callback class ObjPtr
    msgObjSetCBaddr = 15        ' set callback record address
    msgObjSetKey = 16           ' set callback Key
    msgStreamRead = 18          ' read all stream data. CallThunk pParam is destination's pointer: VarPtr(pDest)
    msgRedirectVTblIdx = 32     ' return redirection record slot for IPicture vtable
    msgRedirectIndex = 33       ' return redirection record slot for redirection array
    msgStrmAddRef = 128         ' calls IUnknown:AddRef
    msgStrmRelease = 129        ' calls IUnknown:Release
    msgStrmSetSeek = 130        ' set seek position. CallThunk pParam must be position pointer: VarPtr(cPos@)
                                ' set CallThunk vParam to VarPtr(cNow@) to return current seek position
    msgListener_getThunk = &H8001&  ' "listener" window message
    msgListener_setThunk = &H8002&  ' "listener" window message
End Enum

Private Enum ThunkFlagsEnum
'//////////////////// record flags used by this version and minimally by future versions
'   ----------------------------------------------------------------------------------------
'   summary/overview of flags
'   0x0000000F                  GDI+ related flags
'   0x000000F0                  Callback related flags
'   0x00000F00                  Scale quality & IStream related flags
'   0x0000F000                  Management style related flags
'   0x0F000000                  Picture type enumration flags
'   0xF0000000                  Transparency & multi-image related flags
'   0x80FFC800                  reserved for future versions
'   ----------------------------------------------------------------------------------------
    tfMaskVersion = &H7F0037FF  ' valid flags for this class version
    tfTransparent = &H1         ' Make VB believe image has transparency
    tfGDIpImage = &H2           ' GDI+ Image applies
    tfGDIpAttrs = &H4           ' GDI+ Image Attributes applies
    tfForceGDIp = &H8           ' Always use GDI+ (typically applies to managed ico/cur)
    ' 0x0000000E                ' GDI+ usage mask (used in thunk)
    tfPreCB = &H10              ' pre-render callback wanted
    tfPostCB = &H20             ' post-render callback wanted
    tfPrePostCB = &H30          ' both callbacks wanted
    tfCBinPixels = &H40         ' image source coords/dimension returned as pixels vs himetric in callbacks
    tfCBflags = &H70            ' callback-related flags
    tfRecursing = &H80          ' callback recursion (set/released within thunk only)
    tfScaleNN = &H100           ' GDI+ nearest-neighbor scaling
    tfScaleBilinear = &H200     ' GDI+ bilinear scaling
    tfScaleBicubic = &H300      ' GDI+ bicubic scaling, also mask for scaling algo
    tfIStream = &H400           ' IStream exists (image source data)
    tfMgmtFull = &H1000         ' enhanced management style
    tfMgmtOwnerDrawn = &H2000   ' ownerdrawn management style
    tfMaskMgmt = &H3000         ' mask for management style
    tfShiftMgmt = &H1000        ' bitshift value for managemen style
    tfMaskPicType = &HF000000   ' mask for picture type
    tfShiftPicType = &H1000000  ' bitshift value for picture type
    tfMultiImage = &H10000000   ' managed multi-page/frame TIF/GIF
    tfPicHasTransp = &H20000000 ' image has standard transparency (not pre-multiplied)
    tfPicHasPARGB = &H40000000  ' image has alpha as premultiplied RGB
    tfMaskTransp = &H60000000   ' mask for the two alpha formats
    ' 0x60000001                ' implied transparency mask (used in thunk)
End Enum                        ' notes: cannot change above values willy-nilly; many are used in thunk

Private Const TIFFPageDimension As String = "{7462DC86-6180-4C7E-8E3F-EE7333A7A483}"
Private Const PixelFormat32bppPARGB As Long = &HE200B   ' GDI+ color format
Private Const PixelFormat32bppARGB As Long = &H26200A   ' GDI+ color format
Private Const SrcUnit_Pixel As Long = &H2               ' GDI+ pixel units
Private Const ImageLockModeRead  As Long = &H1          ' GDI+ LockBits constant
Private Const ImageLockModeWrite As Long = &H2          ' GDI+ LockBits constant
Private Const ImageLockModeUserInputBuf As Long = &H4   ' GDI+ LockBits constant
Private Const PICTURE_TRANSPARENT As Long = &H2         ' COM constant

' all thunk versions will have these byte offsets
Private Const OFFSET_ArrObjVtbls As Long = 24   ' offset in thunk where object's VTable array pointer exists
Private Const OFFSET_ArrObjs As Long = 28       ' offset in thunk where object array pointer exists
Private Const OFFSET_ArrObjOptions As Long = 32 ' offset in thunk where object settings/options exists
Private Const OFFSET_ArrRedirects As Long = 36  ' offset in thunk where redirection table pointer exists

Private Const COUNT_PUBLIC As Long = 26         ' number of public methods in this class, if wrong: crash when callbacks used
Private Const THUNK_VERSION As Long = &H2000    ' version: 0x7FFFF000(major) 0xFFF(minor)
Private RECORD_VERSION As Long                  ' see Class_Initialize for how this constant is used

Private Const m_Debug As Boolean = False

Private m_APNGdat As APNGDataStruct             ' used for tracking APNG-related frame information
Private m_CRC32LUT() As Long                    ' used for validating/creating PNG chunk CRC values
Private p_ThunkAddr As Long                     ' general use, set by zzSafeThunkAddress
Private f_MsgAddr As Long                       ' general use, set by zzSafeThunkAddress
Private m_hWndListener As Long                  ' handle to listener window
Private m_EventsUsed As Boolean                 ' flag used in Class_Terminate
Private m_GDIpVersion As Single                 ' courtesy property: If GDI+ is loaded and which version
Private m_EnableAPNG As Boolean                 ' optional setting to not test for APNG (speeds up PNG loading)
Private m_PageGUID(0 To 3, 0 To 1) As Long      ' GUIDs for requesting GIF/TIF frame/page count

' //// Must be the first private method listed in the class
' note: whether public methods are placed above/below this method, does not matter
Private Sub cbPrePostRender(ByVal bBefore As Long, ByVal Key As String, _
           ByVal thePicture As IPicture, ByVal hDC As Long, _
           ByRef dstX As Long, ByRef dstY As Long, _
           ByRef dstCx As Long, ByRef dstCy As Long, _
           ByVal srcX As Long, ByVal srcY As Long, _
           ByVal srcCx As Long, ByVal srcCy As Long, _
           ByVal hImageGDIp As Long, ByRef bufferHDC As Long, _
           ByRef bFlags As Long, ByRef bHandled As Long)
           
    ' do not modify or move this method
    ' method receives event from thunk when callbacks are used
    ' This one method handles 3 different events...
    
    Dim bAbort As Boolean, bIgnore As Boolean
    If srcCy = 0& Then      ' flag indicating ownerdrawn callback being made
        RaiseEvent OwnerDrawn(Key, thePicture, hDC, dstX, dstY, dstCx, dstCy)
        bHandled = True
    ElseIf bBefore Then     ' pre-render event
        bIgnore = bFlags
        RaiseEvent PreRender(Key, thePicture, hDC, dstX, dstY, dstCx, dstCy, _
                             srcX, srcY, srcCx, srcCy, hImageGDIp, bufferHDC, bIgnore, bAbort)
        bHandled = bAbort: bFlags = bIgnore
    Else                    ' post-render event
        RaiseEvent PostRender(Key, thePicture, hDC, dstX, dstY, dstCx, dstCy, _
                             srcX, srcY, srcCx, srcCy, hImageGDIp, bufferHDC)
    End If
    
End Sub

' //// Must immediately follow cbPrePostRender
Private Sub cbSetHGraphics(ByVal Key As String, ByVal hGraphics As Long, _
                                    ByRef dstX As Long, ByRef dstY As Long, _
                                    ByRef dstCx As Long, ByRef dstCy As Long, _
                                    ByVal thePicture As IPicture, ByVal hImage As Long)
    
    ' do not modify or move this method
    ' method receives event from thunk when callbacks are used
    
    RaiseEvent SetHGraphics(Key, hGraphics, dstX, dstY, dstCx, dstCy, thePicture, hImage)
                            
End Sub

Public Function LoadPictureEx(ByVal Source As Variant, _
                     Optional ByVal ManageStyle As ManagementStyle = mgtAutoSelect, _
                     Optional ByVal KeepOriginalFormat As Boolean = False, _
                     Optional ByRef ImageDPI As Long, _
                     Optional ByVal TransparencyFillColor As OLE_COLOR = vbWindowBackground, _
                     Optional ByVal IconIndex As Long = 0&, _
                     Optional ByVal IconCx As Long = 0&, _
                     Optional ByVal IconCy As Long = 0&, _
                     Optional ByVal IconDepth As Long = 0&, _
                     Optional pLoadPicEventParam As Variant) As StdPicture
                     
    ' Loads a picture and creates a stdPicture, optionally manages the picture and
    '   can cache original format data with the image.
    
    ' Source: data that the stdPicture is to be created from.
    '   A VB stdPicture object. The returned picture may not be the same that was passed here
    '       if passed it's original format will be used if VB cached it, otherwise, managed by its handle
    '   If value is 0, then ManageStyle must be mgtOwnerDrawn else function aborts
    '   If string, then must be full path/file of the image. Unicode supported
    '   If array, must be 1D byte array and contains complete format
    '   If non-zero Long, must be a valid bitmap or icon/cursor handle
    '       Any passed handle is not freed in this routine -- your responsibility as needed.
    '       If you only want to set a handle to a stdPicture object, call WrapImageHandleToStdPicture
    '   Any other values passed in Source are ignored and routine aborts
    
    ' ManageStyle: type of management. Only mgtEnhanced can directly alter how an image is drawn
    ' mgtAutoSelect option favors not caching original bytes and rendering transparency for all formats
    '               this option also ignores the KeepOriginalFormat parameter
    '               - BMP: mgtEnhanced is chosen, KeepOriginalFormat is False
    '               - JPG: mgtEnhanced is chosen, auto-orientation correction & CMYK color-space applied,
    '                      KeepOriginalFormat is False and converted to bitmap
    '               - ICO/CUR: mgtEnhanced is chosen, KeepOriginalFormat is False
    '               - GIF: Multi-Frame: mgtEnhanced is chosen, KeepOriginalFormat is True, navigation enabled
    '                      Single-Frame: mgtEnhanced is chosen, converted to alpha-supported bitmap, KeepOriginalFormat is false
    '               - PNG: Single-Frame: same as GIF
    '                      Multi-Frame: navigation enabled, KeepOriginalFormat is False, mgtEnhanced chosen
    '               - TIF: same as PNG
    '               - WMF/EMF: mgtVbOnly is chosen, KeepOriginalFormat is false
    '   mgtVbOnly   Similar result to VB's LoadPicture(), no rendering management.
    '               VB does the rendering, no GDI+ support
    '               Alphablended icons may not render properly
    '               Transparency not supported for bitmaps with valid alpha channels
    '               JPG CMYK color space supported. No JPG orientation correction.
    '               PNG-encoded icons supported
    '               if KeepOriginalFormat true, ManageStyle may be changed to mgtVbPlus
    '               PNG/TIF: transparency filled, converted to bitmap
    '                   if KeepOriginalFormat true, ManageStyle changed to mgtVbPlus
    '   mgtVbPlus   Same as mgtVbOnly with these additions
    '               - allows you to request events
    '               - original format can be cached by thunk if VB does not support format
    '   mgtOwnerDrawn is same as mgtVbPlus except the following:
    '               - this class and VB will not render the picture
    '               - you are responsible for rendering via events
    '               - must call SetCallBacks to request owner-drawn event
    '   mgtEnhanced does what VB can do, in addition to these enhancements:
    '               If KeepOriginalFormat is false, then following applies:
    '                   - GIF/PNG/TIF: image converted to alpha-supported bitmap; no navigation
    '               Metafiles never enhanced by this class, ManageStyle changed to mgtVbPlus
    '               Transparency supported for all image formats
    '               JPG orientation correction applied, CMYK color space supported
    '               Can attach user-defined GDI+ image attributes to the image
    '               Various scaling options allowed when rendering other than actual size
    '               Can request events
    '               Can modify the GDI+ hGraphics object when used, via events, i.e., for rotation
    '               Can navigate GIF/PNG/TIF frames/pages if KeepOriginalFormat is true
    '               notes: when enhanced, some image formats require a GDI+ image to be created and
    '                   kept while style remains enhanced. For all other formats, a GDI+ image may be
    '                   created/destroyed on demand to peform higher quality scaling or for GDI+ image
    '                   attribute application. These formats require the GDI+ image while enhanced:
    '                   - BMP only if transparency applies
    '                   - GIF/PNG only if multi-frame or if first frame has transparency
    '                   - TIF only if multi-page or if first page has transparency
    '                   - ICO/CUR always, ensures alphablended icons are rendered properly
    
    ' KeepOriginalFormat. Retains the source. Avoid unless it is necessary, waste of memory.
    '   Ignored and automatically set when ManageStyle is auto-select (see above)
    '   Reasons for setting this parameter to True:
    '       - you may need to save the picture in its original format (PNG, GIF, JPG, etc)
    '           note: if you have this in your resource file, never cache it again, for this purpose
    '       - you want to be able to navigate GIF/PNG frames (animation) and/or TIF pages
    '   If data is kept, then original bytes can be retrieved via the GetImageData() method
    '   Also, if data is kept and VB can't load the picture or the picture is icon/cursor, then
    '       original bytes will be cached outside of the VB picture object and stored
    '       by the thunk indirectly. Otherwise, VB will cache the format with its picture object.
    
    ' ImageDPI. Returns the embedded DPI within the image, if it exists.
    '   If it does not exist, the value returned is zero. When zero, typically you assume 96 DPI
    
    ' TransparencyFillColor. Depends on management style and KeepOriginal format parameters
    '   If the image format is not supported by VB (PNG, TIF, possibly some GIFs) and that image
    '   contains transparency, then the returned format may be a bitmap with transparency filled
    '   If a bitmap with a valid alpha channel is the source, no filling occurs.
    ' Note: to fill any alpha-supported image with a specific background color:
    '   - when routine returns, call UnManagePicture passing it's PurgeOriginalFormat parameter as true
    '   - pass the returned picture to CopyStdPicture & provide the fill parameters.
    
    ' IconIndex applies only to icons/cursors.
    '   Determines which icon, in a multi-icon format, is returned in stdPicture
    '   Value is 1-based index: 1=1st icon, 2=2nd icon, etc
    '   If value is zero and IconCx/IconCy are both zero then system DPI-aware size for 32x32 used
    '   If value is -1 and IconCx/IconCy are both zero then system DPI-aware size for 16x16 used
    ' IconCx/IconCy applies only to icons/cursors. If either are zero, both are treated as zero
    '   Attempts to find closest size, in a multi-icon format
    '   When zero & IconIndex > 0 then actual size returned for icon at IconIndex
    ' IconDepth applies only to icons/cursors. Zero defaults to current screen depth
    '   Attempts to find closest depth, in a multi-icon format. Ignored if IconIndex > 0
    '   note: there is never any sampling up/down to the passed depth value
    
    ' Tips for returning icons...
    ' Goal                                  IconIndex   IconCx/Cy   IconDepth
    ' --------------------------------------------------------------------------
    ' Same as VB's LoadPicture (32x32)(default) 0           0*          0
    ' Best image at system small size (16x16)  -1           0*          0
    ' System size at specific depth             0 or -1     0*          depth
    ' Best image at specific size               0           size        0
    ' Best image at specific size & depth       0           size        depth
    ' Specific index, actual size               index       0           ignored
    ' Specific index, forced size               index       size        ignored
    ' (*) These are DPI-aware since they use system metrics to retrieve the size,
    '     if your project is manifested as DPI-aware.
    '     Any other scenario requires you to pass IconCx,IconCy scaled, if desired
    
    ' pLoadPicEventParam. This parameter will be passed to the PreLoadPicture event. Use
    '   it however you need. That event is called once the image format is known. The event
    '   allows you to modify the parameters passed to this function based on the picture
    '   type, if desired. In some cases, you may want different management styles based on
    '   the picture type or whether it has transparency, multiple images, etc. You typically
    '   won't know that in advance if loading images from outside your project. PreLoadPicture
    '   event attempts to help you in this scenario. See event comments at top of class
    
    ImageDPI = 0&
                                
    Dim hImage As Long, hGlobal As Long, lValue As Long
    Dim tPic As StdPicture, iPic As IPicture, bOK As Boolean
    Dim arrData() As Byte, lSize As Long, lFlags As Long
    Dim sngDPI As Single, IStream As stdole.IUnknown
    Const ImageFlagHasRealDPI As Long = &H1000&

    If zzSafeThunkAddress() = False Then    ' should never happen, thunk failed creation
        ManageStyle = mgtVbOnly: KeepOriginalFormat = False
    ElseIf m_GDIpVersion = 0! Then          ' should never happen, GDI+ failed to load
        ManageStyle = mgtVbOnly: KeepOriginalFormat = False
    ElseIf ManageStyle < mgtAutoSelect Or ManageStyle > mgtOwnerDrawn Then
        ManageStyle = mgtVbOnly
    End If                                  ' if either above checkes failed, picture loaded via VB only

    If IsObject(Source) Then                ' test for passed picture
        If Not TypeName(Source) = "Picture" Then Exit Function
        Set tPic = Source                   ' abort if no picture, thunk failed or already managed
        If tPic Is Nothing Then Exit Function
        If tPic.Handle = 0& Then GoTo ExitRoutine
        If p_ThunkAddr = 0& Or m_GDIpVersion = 0! Then GoTo ExitRoutine
        If CallThunk(f_MsgAddr, ObjPtr(tPic), msgObjPtrIndex) > 0& Then GoTo ExitRoutine
        Select Case tPic.Type
        Case vbPicTypeBitmap, vbPicTypeIcon ' manage by original format or handle if format doesn't exist
            If Me.HasOriginalFormat(tPic) = True Then
                Set IStream = zzGetImageData(tPic, False, (True))
                If IStream Is Nothing Then GoTo ExitRoutine
            Else
                lValue = tPic.Handle        ' will manage via its handle
            End If
        Case vbPicTypeEMetafile, vbPicTypeMetafile ' managed by original format
            Set IStream = zzGetImageData(tPic, False, (True))
            If IStream Is Nothing Then GoTo ExitRoutine
        Case Else: GoTo ExitRoutine
        End Select
        Set tPic = Nothing
    End If

    If IStream Is Nothing Then              ' else stdPicture original format already gathered
        If VarType(Source) = vbString Then  ' must be file path/name
            If Trim$(Source) = vbNullString Then
                Set LoadPictureEx = New StdPicture
                Exit Function
            End If
            If zzIStreamFromSource(CStr(Source), arrData(), hGlobal, lSize) = False Then Exit Function
            
        ElseIf (VarType(Source) = (vbByte Or vbArray)) Then
            On Error Resume Next            ' must be valid byte array
            arrData() = Source
            lSize = UBound(arrData)
            If LBound(arrData) > UBound(arrData) Then lSize = -1&
            If Err.Number = 0& And lSize > 0& Then
                On Error GoTo 0
                If zzIStreamFromSource(vbNullString, arrData(), hGlobal, lSize) = False Then Exit Function
                Erase arrData()
            Else
                On Error GoTo 0
                Set LoadPictureEx = New StdPicture
                Exit Function
            End If
            
        '//// process passed bitmap/icon handles
        ElseIf (VarType(Source) = vbLong Or VarType(Source) = vbInteger) Or lValue <> 0& Then
            KeepOriginalFormat = False      ' managed by handle, handle is copied
            If Source = 0& And lValue = 0& Then
                If ManageStyle = mgtOwnerDrawn Then
                    lValue = CreateBitmap(1, 1, 1, 1, ByVal 0&)
                    Set tPic = zzHandleToStdPicture(lValue, vbPicTypeBitmap)
                    lFlags = picBMP * tfShiftPicType
                    Set LoadPictureEx = zzManageBMP(tPic, ManageStyle, IStream, lSize, lFlags, False, TransparencyFillColor)
                End If
            Else
                If lValue = 0& Then lValue = Source
                lFlags = zzBitmapFromHBMP(lValue, tPic, True, False)
                If lFlags Then
                    If Not tPic Is Nothing Then _
                        Set LoadPictureEx = zzManageBMP(tPic, ManageStyle, IStream, lSize, lFlags, False, TransparencyFillColor)
                Else
                    If ManageStyle = mgtAutoSelect Then ManageStyle = mgtEnhanced
                    lFlags = zzBitmapFromHICON(tPic, lValue, hImage, ManageStyle, IconCx, IconCy)
                    If lFlags Then
                        If Not tPic Is Nothing Then _
                            Set LoadPictureEx = zzManageICO(tPic, ManageStyle, IStream, lSize, hImage, lFlags, False)
                    End If
                End If
            End If
            Exit Function
        End If
        ' create stream from hGlobal
        CreateStreamOnHGlobal hGlobal, 1&, IStream
        If IStream Is Nothing Then      ' only fails if out of memory
            GlobalFree hGlobal
            Exit Function
        ElseIf m_GDIpVersion = 0! Or p_ThunkAddr = 0& Then
            ' GDI+ or thunk failed to load. Load via VB and exit
            Set LoadPictureEx = zzIStreamToPicture(ObjPtr(IStream), KeepOriginalFormat, lSize)
            Exit Function
        End If
    End If
    
    ' GDI+ doesn't do alpha-bitmaps properly. If unmanaged, VB can't load bmp v4/v5 headers
    If ManageStyle = mgtAutoSelect Then lValue = mgtEnhanced: KeepOriginalFormat = False Else lValue = ManageStyle
    lFlags = zzValidateBmp(IStream, lSize, lValue, tPic, ImageDPI, KeepOriginalFormat, TransparencyFillColor, pLoadPicEventParam)
    If lFlags Then
        If lValue < mgtAutoSelect Or ManageStyle > mgtOwnerDrawn Then ManageStyle = mgtAutoSelect Else ManageStyle = lValue
        If Not tPic Is Nothing Then
            If ManageStyle < mgtAutoSelect Or ManageStyle > mgtOwnerDrawn Then ManageStyle = mgtAutoSelect
            Set LoadPictureEx = zzManageBMP(tPic, ManageStyle, IStream, lSize, lFlags, KeepOriginalFormat, TransparencyFillColor)
        End If
        Exit Function
    End If
    
    ' VB can't load all supported icon formats (i.e., PNG). GDI+ has issues with icons/cursors
    If ManageStyle = mgtAutoSelect Then ManageStyle = True: KeepOriginalFormat = False
    lFlags = zzValidateIcon(IStream, lSize, ManageStyle, tPic, hImage, IconIndex, IconCx, IconCy, IconDepth, KeepOriginalFormat, pLoadPicEventParam)
    If lFlags Then
        If Not tPic Is Nothing Then
            If ManageStyle < mgtAutoSelect Or ManageStyle > mgtOwnerDrawn Then ManageStyle = mgtAutoSelect
            Set LoadPictureEx = zzManageICO(tPic, ManageStyle, IStream, lSize, hImage, lFlags, KeepOriginalFormat)
        End If
        Exit Function
    End If
    
'///// Attempt GDI+ (loads more formats than VB)

    GdipLoadImageFromStream ObjPtr(IStream), hImage
    If hImage = 0& Then Exit Function                   ' not an image format?

    GdipGetImageFlags hImage, lValue                    ' get DPI info
    If (lValue And ImageFlagHasRealDPI) = ImageFlagHasRealDPI Then
        GdipGetImageHorizontalResolution hImage, sngDPI
        ImageDPI = sngDPI
    End If
    
    lValue = zzQueryFormat(hImage)                      ' get GDI+ image type
    Select Case lValue
    Case picGIF
        ImageDPI = 0&
        Set LoadPictureEx = zzManageGIF(ManageStyle, IStream, lSize, hImage, KeepOriginalFormat, TransparencyFillColor, pLoadPicEventParam)
    Case picJPG
        Set LoadPictureEx = zzManageJPG(ManageStyle, IStream, lSize, hImage, KeepOriginalFormat, pLoadPicEventParam)
    Case picPNG
        Set LoadPictureEx = zzManagePNG(ManageStyle, IStream, lSize, hImage, KeepOriginalFormat, TransparencyFillColor, pLoadPicEventParam)
    Case picTIF
        Set LoadPictureEx = zzManageTIF(ManageStyle, IStream, lSize, hImage, KeepOriginalFormat, TransparencyFillColor, pLoadPicEventParam)
    Case picWMF, picEMF                     ' never Enhanced by this class
        If sngDPI = 0! Then GdipGetImageHorizontalResolution hImage, sngDPI: ImageDPI = sngDPI
        Set LoadPictureEx = zzManageWMF(ManageStyle, IStream, lSize, lValue, hImage, 0&, KeepOriginalFormat, pLoadPicEventParam)
    Case Else
        zzFillImage hImage, lValue, zzConvertColor(TransparencyFillColor)
        GdipDisposeImage hImage: hImage = 0&
        If lValue Then
            Set tPic = zzHandleToStdPicture(lValue, vbPicTypeBitmap)
            Set LoadPictureEx = zzManageBMP(tPic, ManageStyle, Nothing, 0&, picBMP * tfShiftPicType, False, TransparencyFillColor)
        End If
    End Select
    Exit Function
    
ExitRoutine:
    If Not tPic Is Nothing Then Set LoadPictureEx = tPic
    
End Function

Public Function LoadResPictureEx(ResID As Variant, ByVal ResType As LoadResConstants, _
                                Optional ByVal ManageStyle As ManagementStyle = mgtAutoSelect, _
                                Optional ByRef ImageDPI As Long, _
                                Optional ByVal IconIndex As Long = 0&, _
                                Optional ByVal IconCx As Long = 0&, _
                                Optional ByVal IconCy As Long = 0&, _
                                Optional ByVal IconDepth As Long = 0&) As StdPicture

    ' Function replicates VB's LoadResPicture with a couple of major differences...
    ' 1) Bitmaps are loaded as DIBs vs DDB as LoadResPicture does
    ' 2) Icons/Cursors can have individual images extracted. VB's LoadResPicture always
    '    returns system size (32x32). This method can ensure color cursors loaded during IDE
    
    ' The parameters for this method are defined/described in LoadPictureEx method

    Dim arrData() As Byte, arrDir() As Byte
    Dim lCount As Long, n As Long, lPos As Long
    Dim lSize As Long, lOffset As Long, bPNG As Boolean
    Dim lValue As Long, arrRes() As Byte
    Const RT_CURSOR As Long = 1
    Const RT_BITMAP As Long = 2
    Const RT_ICON As Long = 3
    
    If ResType < vbResBitmap Or ResType > vbResCursor Then Exit Function
    On Error GoTo ExitRoutine
    If ResType = vbResBitmap Then                   ' build 14-byte BITMAPFILE header
        arrRes() = LoadResData(ResID, RT_BITMAP)    ' then append res data to it
        lSize = UBound(arrRes) + 1&
        ReDim arrData(0 To lSize + 13&)
        arrData(0) = 66: arrData(1) = 77            ' 1st 2 bytes: magic number BM
        CopyMemory arrData(2), lSize + 14&, 4&      ' next 4 bytes: overall size of array
        CopyMemory arrData(14), arrRes(0), lSize    ' transfer res data to array
        CopyMemory lOffset, arrRes(0), 4&           ' calculate where bitmap bits begin
        Erase arrRes()
        lPos = 14&
        If lOffset = 12& Then                       ' old format that VB still supports
            lValue = arrData(10 + lPos) Or arrData(11 + lPos) * &H100&
            If lValue < 9& Then lOffset = lOffset + (2 ^ lValue) * 3&
        Else                                        ' modern formats
            lValue = arrData(14 + lPos) Or arrData(15 + lPos) * &H100&
            CopyMemory lSize, arrData(32 + lPos), 4&    ' color count/size
            If lValue < 9& Then
                If lSize = 0& Then lOffset = lOffset + (2 ^ lValue) * 4& Else lOffset = lOffset + lSize * 4&
            Else
                If arrData(16 + lPos) = 3 And (lValue = 16 Or lValue = 32) Then
                    If lOffset = 40 Then lOffset = lOffset + 12&
                End If
                If lSize Then lOffset = lOffset + lSize * 4&
            End If
        End If
        CopyMemory arrData(10), lOffset + 14&, 4&   ' last 4 bytes: location where pixel data begins
        On Error GoTo 0
    Else
        If ResType = vbResIcon Then                 ' icons/cursors are each different within res data
            ResType = RT_ICON
        Else
            ResType = RT_CURSOR: lOffset = 4&       ' cursors contain a 4 byte prefix for hotspot
        End If
        arrDir() = LoadResData(ResID, ResType + 11&) ' get the directory for the passed res icon/cursor
        On Error GoTo 0
        For n = 14& To UBound(arrDir) - 5& Step 14& ' count number of sub-images & total size of all sub-images
            CopyMemory lValue, arrDir(n), 4&
            lSize = lSize + lValue - lOffset: lCount = lCount + 1&
        Next
        ReDim arrData(0 To lCount * 16& + lSize + 5&) ' size array for all sub-images + directories
        lPos = 6&: lOffset = lCount * 16& + lPos
        CopyMemory arrData(0), arrDir(0), lPos      ' copy 1st 6 bytes from directory
        For n = 18& To UBound(arrDir) - 1& Step 14& ' loop thru each directory & locate the res icon/cursor ID
            lValue = arrDir(n) Or arrDir(n + 1) * &H100&
            arrRes() = LoadResData(lValue, ResType) ' load that resource now & cache its size
            lSize = UBound(arrRes) + 1&
            If ResType = RT_CURSOR Then             ' build the icon/cursor directory
                lSize = lSize - 4&: CopyMemory arrData(lOffset), arrRes(4), lSize
            Else
                CopyMemory arrData(lOffset), arrRes(0), lSize
            End If
            CopyMemory lValue, arrData(lOffset), 4& ' get actual size & add to directory
            If lValue = &H474E5089 Then             ' PNG
                CopyMemory lValue, arrData(lOffset + 16&), 4&: lValue = zzReverseLong(lValue)
                If lValue > 255 Then arrData(lPos) = 0 Else arrData(lPos) = lValue
                CopyMemory lValue, arrData(lOffset + 20&), 4&: lValue = zzReverseLong(lValue)
                If lValue > 255 Then arrData(lPos + 1) = 0 Else arrData(lPos + 1) = lValue
                lValue = arrDir(n - 6&)             ' get bitcount from directory & use it if appears valid
                If (lValue = 0& Or lValue > 32&) Or ResType = RT_CURSOR Then ' else fetch it from PNG
                    Select Case arrData(lOffset + 25&)
                        Case 4, 6: lValue = 32&
                        Case 2: lValue = 24&
                        Case Else: lValue = arrData(lOffset + 24&)
                    End Select
                End If
            Else                                    ' non-PNG
                CopyMemory lValue, arrData(lOffset + 4&), 4&
                If lValue > 255 Then arrData(lPos) = 0 Else arrData(lPos) = lValue
                CopyMemory lValue, arrData(lOffset + 8&), 4&
                If ResType = RT_CURSOR Then lValue = lValue \ 2&
                If lValue > 255 Then arrData(lPos + 1) = 0 Else arrData(lPos + 1) = lValue
                lValue = arrData(lOffset + 14) Or arrData(lOffset + 15) * &H100& ' get bitcount
            End If
            If lValue < 8& Then arrData(lPos + 2) = 2 ^ lValue Else arrData(lPos + 2) = 0
            If ResType = RT_CURSOR Then             ' get hotspot
                CopyMemory arrData(lPos + 4), arrRes(0), 4&
            Else                                    ' else set planes & bitcount
                arrData(lPos + 4) = 1: arrData(lPos + 6) = lValue
            End If
            CopyMemory arrData(lPos + 8), lSize, 4& ' add resource size & location to directory & done with it
            CopyMemory arrData(lPos + 12), lOffset, 4&
            
            lPos = lPos + 16&                       ' set next directory location
            lOffset = lOffset + lSize               ' set next slot in our array for res data
        Next
        Erase arrDir()
    End If
    Erase arrRes()
    Set LoadResPictureEx = Me.LoadPictureEx(arrData(), ManageStyle, , ImageDPI, , IconIndex, IconCx, IconCy, IconDepth)

ExitRoutine:
End Function

Public Function CopyStdPicture(thePicture As StdPicture, ByVal Width As Long, ByVal Height As Long, _
                                        Optional ByVal ManageStyle As ManagementStyle = mgtAutoSelect, _
                                        Optional ByVal SendToEvents As Boolean = False, _
                                        Optional ByVal ReturnAsIcon As Boolean = False, _
                                        Optional ByVal BmpAlphaTypeAsPARGB As Boolean = True, _
                                        Optional ByVal FillTransparency As Boolean = False, _
                                        Optional ByVal FillTransparencyColor As OLE_COLOR = vbWindowBackground) As StdPicture
                                        
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function
                                        
    ' This method can be used to return a resized image as a bitmap or icon and optionally manage it
    
    ' Pass Width, Height as the new dimensions or zeroes for same dimensions
    ' ManageStyle is same as described in LoadPictureEx()
    ' SendToEvents when true will trigger Pre/Post/Ownerdrawn render events if events were requested for the
    '   passed picture. When this parameter is true, you MUST RENDER the picture or allow VB's default
    '   rendering to proceed within the event. The returned picture is the result of what occurred
    '   during the event. No rendering will be done by this function.
    ' ReturnAsIcon if true, returns a 32bpp icon else a 32bpp bitmap
    '   if bitmap and transparency exists, should be enhanced to display transparency else pass fill parameters
    ' BmpAlphaTypeAsPARGB determines which alpha channel format is returned for bitmaps with transparency
    '   default is premultiplied ARGB (appropriate for some APIs)
    '   optionally, setting parameter to False fills alpha channel with standard ARGB
    '   this parameter is ignored if returning an icon or if FillTransparency is true
    
    Dim tPic As StdPicture, lFlags As Long, hImage As Long, lStyle As Long
    
    If zzSafeThunkAddress() = False Or m_GDIpVersion = 0! Then Exit Function ' routine makes heavy use of GDI+ & not available
    If (CallThunk(f_MsgAddr, ObjPtr(thePicture), msgObjGetFlags) And tfRecursing) Then
        If SendToEvents Then Exit Function              ' can't send to event if called from an event
    End If
    
    If ManageStyle < mgtAutoSelect Or ManageStyle > mgtOwnerDrawn Then ManageStyle = mgtVbOnly
    If Width < 0& Then Width = 0&
    If Height < 0& Then Height = 0&
    
    If ManageStyle = mgtAutoSelect Then
        ' for bitmaps prevent creation of hImage in the zzXeroxFormat routine; zzManageBMP creates it as needed
        If ReturnAsIcon Then lStyle = mgtEnhanced Else lStyle = mgtVbOnly
    Else
        lStyle = ManageStyle
    End If
    lFlags = zzXeroxFormat(thePicture, tPic, hImage, SendToEvents, Width, Height, (lStyle), _
                            ReturnAsIcon, BmpAlphaTypeAsPARGB, FillTransparency, FillTransparencyColor)
                            
    If tPic.Type = vbPicTypeIcon Then
        Set CopyStdPicture = zzManageICO(tPic, lStyle, Nothing, 0&, hImage, lFlags, False)
    ElseIf tPic.Type = vbPicTypeBitmap Then
        Set CopyStdPicture = zzManageBMP(tPic, ManageStyle, Nothing, 0&, lFlags, False, FillTransparencyColor)
    End If

End Function

Public Function UnmanagePicture(thePicture As StdPicture, _
                                Optional ByVal PurgeOriginalFormat As Boolean = False, _
                                Optional ByVal TransparencyFillColor As OLE_COLOR = vbWindowBackground) As StdPicture
                
    ' This method takes an existing stdPicture and changes its management style
    ' LoadPictureEx creates managed/unmanaged pictures from array/file/handle
    ' Note: the returned stdPicture may not be the one that was passed.
    
    ' PurgeOriginalFormat. This permanently removes format information for most image formats.
    '   Along with the notes below, you are restricted to VB's SavePicture or custom code to
    '   extract bytes for saving to file. Otherwise, original data, if it exists, can always
    '   be retrieved via GetImageData(). Without original format, some formats converted to bitmap.
    '   BMP:        transparency filled, alpha channel permanently lost
    '   GIF:        no frame navigation, alpha can only be rendered by VB
    '   JPG:        visually no change, format changes to BMP
    '   ICO/CUR:    no change in format, alphablended icons may not be rendered correctly
    '   WMF/EMF:    visually no change
    '   TIF/PNG:    no page/frame navigation, transparency filled, format changes to BMP
    
    ' TransparencyFillColor applies only when format will be filled
    
    Dim lFlags As Long, lObjPtr As Long, hBmp As Long
    Dim tPic As StdPicture, IStream As stdole.IUnknown
    Dim hImage As Long, tImage As Long
    Dim lType As Long, pStream As Long
    
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle Then
        If zzSafeThunkAddress() Then
            lObjPtr = ObjPtr(thePicture)
            If CallThunk(f_MsgAddr, lObjPtr, msgObjPtrIndex) < 1& Then  ' not managed
                If PurgeOriginalFormat = True Then
                    If Me.HasOriginalFormat(thePicture) = True Then
                        Set IStream = zzGetImageData(thePicture, False, (True))
                        If Not IStream Is Nothing Then Set tPic = zzIStreamToPicture(ObjPtr(IStream), False, 0&)
                    End If
                End If
            ElseIf PurgeOriginalFormat = False Then                     ' simply unmanage
                zzUnmanage thePicture
            Else
                lFlags = CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags)
                lType = (lFlags And tfMaskPicType) \ tfShiftPicType
                Select Case lType
                Case picBMP, picPNG, picTIF                             ' fill transparency
                    If (lFlags And (tfMaskTransp Or tfMultiImage)) Then
                        hImage = CallThunk(f_MsgAddr, lObjPtr, msgObjGetHImage)
                        If hImage = 0& Then
                            If lType = picBMP Then
                                zzGetCompatibleBmp tImage, thePicture, (lFlags And tfPicHasTransp)
                            Else
                                pStream = CallThunk(f_MsgAddr, lObjPtr, msgObjGetStream)
                                If pStream Then
                                    CallThunk f_MsgAddr, pStream, msgStrmSetSeek, VarPtr(0@)
                                    GdipLoadImageFromStream pStream, tImage
                                End If
                            End If
                            If tImage Then hImage = tImage
                        End If
                        If hImage Then
                            If (lFlags And tfMultiImage) Then
                                If m_PageGUID(0, 1) = 0& Then IIDFromString StrPtr(TIFFPageDimension), m_PageGUID(0, 1)
                                GdipImageSelectActiveFrame hImage, m_PageGUID(0, 1), 0&
                            End If
                            zzFillImage hImage, hBmp, zzConvertColor(TransparencyFillColor)
                            If hBmp Then Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
                            If tImage Then GdipDisposeImage tImage
                        End If
                    End If
                Case picGIF                                         ' handle special case
                    pStream = CallThunk(f_MsgAddr, lObjPtr, msgObjGetStream)
                    If pStream Then         ' VB couldn't load GIF, gonna fill it
                        hImage = CallThunk(f_MsgAddr, lObjPtr, msgObjGetHImage)
                        If hImage = 0& Then
                            CallThunk f_MsgAddr, pStream, msgStrmSetSeek, VarPtr(0@)
                            GdipLoadImageFromStream pStream, tImage
                            If tImage Then hImage = tImage
                        End If
                        If hImage Then
                            zzFillImage hImage, hBmp, zzConvertColor(TransparencyFillColor)
                            If hBmp Then Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
                            If tImage Then GdipDisposeImage tImage
                        End If
                    Else
                        Set IStream = zzGetImageData(thePicture, False, (True))
                        If Not IStream Is Nothing Then Set tPic = zzIStreamToPicture(ObjPtr(IStream), False, 0&)
                    End If
                Case picJPG                                         ' remove cached format
                    zzBitmapFromHBMP thePicture.Handle, tPic, False, False
                Case picICO, picCUR, picWMF, picEMF
                    ' nothing special needed
                End Select
                zzUnmanage thePicture
            End If
        End If
    End If
    If tPic Is Nothing Then Set UnmanagePicture = thePicture Else Set UnmanagePicture = tPic

End Function

Public Function GetImageData(thePicture As StdPicture, arrData() As Byte) As Boolean

    ' routine returns the image data associated with the picture
    ' If the picture was loaded via LoadPictureEx, managed and that method's
    '   KeepOriginalFormat set to True, then original format was cached.
    ' Otherwise, the image data returned is dependent on the format that
    '   VB has associated with the picture.
    ' This method should always return data. The format is dependent
    ' Can test for original format with HasOriginalFormat function

    arrData() = zzGetImageData(thePicture, True, GetImageData)

End Function

Public Property Get IsManaged(thePicture As StdPicture) As ManagementStyle

    ' simply returns whether the passed picture is currently managed or not
    
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle Then
        If zzSafeThunkAddress() Then
            Dim lFlags As Long
            lFlags = CallThunk(f_MsgAddr, ObjPtr(thePicture), msgObjGetFlags)
            If lFlags Then IsManaged = (lFlags And (tfMgmtFull Or tfMgmtOwnerDrawn)) \ tfShiftMgmt + 1&
        End If
    End If

End Property

Public Property Get HasOriginalFormat(thePicture As StdPicture) As Boolean

    ' returns whether original format data can be retrieved from the picture.
    ' note: The picture does not have to be managed to contain original data;
    '   however, if it is managed then it is guaranteed to have that data if
    '   if was managed with KeepOriginalFormat set in call to LoadPictureEx

    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle Then
        Dim iPic As IPicture, bKOF As Boolean
        Set iPic = thePicture
        bKOF = iPic.KeepOriginalFormat
        If bKOF Then
            HasOriginalFormat = True
        ElseIf zzSafeThunkAddress() Then
            HasOriginalFormat = CBool(CallThunk(f_MsgAddr, ObjPtr(iPic), msgObjGetFlags) And tfIStream)
        End If
    End If
    
End Property

Public Property Get HasTransparency(thePicture As StdPicture) As AlphaTypeEnum

    ' Property returns type of transparency, if any
    ' notes:
    '   GIF/APNG/TIF, if multiple frames/pages apply, current frame/page checked on demand
    ' Note: having transparency doesn't mean transparency is rendered.
    ' Enhanced/AutoSelect management styles should always be used to ensure transparency is rendered

    If thePicture Is Nothing Then Exit Property
    If thePicture.Handle Then
        Dim iPic As IPicture, lObjPtr As Long, lFlags As Long, hImage As Long
        If Not (thePicture.Type = picWMF Or thePicture.Type = picEMF) Then
            If zzSafeThunkAddress() Then
                lObjPtr = ObjPtr(thePicture)
                lFlags = CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags)
                Select Case (lFlags And tfMaskPicType) \ tfShiftPicType
                Case 0
                    If thePicture.Type = vbPicTypeBitmap Then
                        HasTransparency = zzValidateAlphaChannel(0&, thePicture.Handle) \ &H20000000
                    Else
                        lObjPtr = 0&
                    End If
                Case picGIF, picTIF, picAPNG
                    hImage = CallThunk(f_MsgAddr, lObjPtr, msgObjGetHImage)
                    If hImage Then
                        HasTransparency = zzValidateAlphaChannel(hImage, 0&) \ &H20000000
                    Else
                        HasTransparency = (lFlags And tfMaskTransp) \ &H20000000
                    End If
                Case Else
                    HasTransparency = (lFlags And tfMaskTransp) \ &H20000000
                End Select
            End If
        End If
        If lObjPtr = 0& Then
            Set iPic = thePicture
            HasTransparency = (iPic.Attributes And PICTURE_TRANSPARENT) \ PICTURE_TRANSPARENT
        End If
    End If

End Property

Public Property Get PictureTypeEx(thePicture As StdPicture) As PictTypeEx

    ' returns the picture type for passed picture (managed or not)
    ' The type depends on whether managed or not and whether original format data was kept
    '   when the picture was initially managed.
    
    ' if KeepOriginalFormat option in LoadPictureEx was not set to true or the
    '   picture is not managed, then this function returns the same as VB's
    '   .Picture.Type property
    ' otherwise, it will return the image format that was cached due to
    '   KeepOriginalFormat option being set.
    
    ' Bitmaps can have transparency. If you need to know this, and the picture
    '   is managed, then you can call the class HasTransparency property to determine
    '   whether bitmap uses ARGB or pARGB alpha channel or none (no transparency).
    
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function
    
    Dim lObjPtr As Long, lType As PictTypeEx
    If zzSafeThunkAddress() Then
        lObjPtr = ObjPtr(thePicture)
        If CallThunk(f_MsgAddr, lObjPtr, msgObjPtrIndex) > 0& Then
            lType = (CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags) And tfMaskPicType) \ tfShiftPicType
            If lType = picAPNG Then lType = picPNG
        End If
    End If
    If lType = picUnknown Then lType = thePicture.Type
    PictureTypeEx = lType
    
End Property

Public Sub PaintPictureEx(Destination As Variant, thePicture As StdPicture, _
                    ByVal X1 As Single, ByVal Y1 As Single, _
                    Optional ByVal Width1 As Single = 0!, Optional ByVal Height1 As Single = 0!, _
                    Optional ByVal X2 As Single = 0!, Optional ByVal Y2 As Single = 0!, _
                    Optional ByVal Width2 As Single = 0!, Optional ByVal Height2 As Single = 0!)

    ' Suitable substitute for VB's PaintPicture method & APIs BitBlt/StretchBlt
    ' This method can be called regardless whether picture is managed or not
    
    ' When pictures are enhanced, the management is via the picture's Render method.
    ' VB does not call the render method when PaintPicture is used; therefore no events either.
    ' This routine simulates PaintPicture and/or BitBlt/StretchBlt, triggers Render and events,
    '   and has the same parameters with these two noted exceptions...
    ' 1) There is no ROP option like there is in VB's PaintPicture. stdPicture Render function doesn't offer one.
    ' 2) The Destination is either:
    '       - the VB object (form, picturebox) that would call VB's PaintPicture
    '           all coords/sizes are in the target's scalemode, same as VB would expect
    '       - a target hDC for API use, in which case, all coords/sizes are pixels
    ' note: to mirror vertically: Y1 = renderY + renderHeight: Height1 = -renderHeight
    ' note: to mirror horizontally: X1 = renderX + renderWidth: Width1 = -renderWidth
    ' when mirroring, always use negative values on the destination parameters, not source
    '   parameters. Negative source parameters are ignored.
    
    ' one final note. If calling this from within a rendering event for an image control,
    '   and GDI+ will be used for rendering then ensure the passed parameters are set correctly
    '   to prevent rendering outside of the image control's bounds. When the pre/post-render
    '   events are called for image controls, GDI clips the target DC which would prevent this
    '   problem if GDI is used for rendering. However, GDI+ doesn't honor GDI clipping areas.
    '   So, your passed parameters could allow GDI+ to render outside of the image control.

    If thePicture Is Nothing Then Exit Sub
    If thePicture.Handle = 0& Then Exit Sub

    Dim lScale As ScaleModeConstants, tDC As Long, lDPI As Long
    On Error GoTo ExitRoutine ' should user pass invalid parameters or invalid Destination
    
    ' ignore sign for source parameters...
    If Width2 < 0! Then Width2 = -Width2
    If Height2 < 0! Then Height2 = -Height2
    If X2 < 0! Then X2 = -X2
    If Y2 < 0! Then Y2 = -Y2
    
    If IsObject(Destination) Then
        With Destination            ' PaintPicture substitute
            tDC = .hDC
            lScale = .ScaleMode     ' scale destination coords/sizes to pixels
            X1 = .ScaleX(X1, lScale, vbPixels): Y1 = .ScaleY(Y1, lScale, vbPixels)
            If Width1 = 0! Then
                Width1 = .ScaleX(thePicture.Width, vbHimetric, vbPixels)
            Else
                Width1 = .ScaleX(Width1, lScale, vbPixels)
            End If
            If Height1 = 0! Then
                Height1 = .ScaleY(thePicture.Height, vbHimetric, vbPixels)
            Else
                Height1 = .ScaleY(Height1, lScale, vbPixels)
            End If
            X2 = .ScaleX(X2, lScale, vbHimetric): Y2 = .ScaleY(Y2, lScale, vbHimetric)
            If Width2 = 0! Then     ' convert source width to himetrics
                Width2 = thePicture.Width
            Else
                Width2 = .ScaleX(Width2, lScale, vbHimetric)
            End If
            If Height2 = 0! Then    ' convert source height to himetrics
                Height2 = thePicture.Height
            Else
                Height2 = .ScaleY(Height2, lScale, vbHimetric)
            End If
        End With
        
    ElseIf VarType(Destination) = vbLong Then
        tDC = Destination       ' BitBlt/StretchBlt/AlphaBlend substitutes
        lDPI = zzRealDPI        ' convert image size to pixels as needed
        If Width1 = 0! Then Width1 = CLng(thePicture.Width / 2540! * (1440! / Screen.TwipsPerPixelX))
        If Height1 = 0! Then Height1 = CLng(thePicture.Height / 2540! * (1440! / Screen.TwipsPerPixelX))
        X2 = CLng(X2 * 2540! / lDPI): Y2 = CLng(Y2 * 2540! / lDPI)
        If Width2 = 0! Then
            Width2 = thePicture.Width
        Else                    ' convert source width to himetrics
            Width2 = CLng(Width2 * 2540! / lDPI)
        End If
        If Height2 = 0! Then
            Height2 = thePicture.Height
        Else                    ' convert source height to himetrics
            Height2 = CLng(Height2 * 2540! / lDPI)
        End If
    Else
        Exit Sub
    End If
    If Width1 < 0! Then
        X2 = X2 + Width2: Width2 = -Width2
        X1 = X1 + Width1: Width1 = -Width1
    End If
    If Height1 < 0! Then
        Y2 = Y2 + Height2: Height2 = -Height2
        Y1 = Y1 + Height1: Height1 = -Height1
    End If
    thePicture.Render (tDC), X1, Y1, Width1, Height1, _
                X2, thePicture.Height - Y2, Width2, -Height2, ByVal 0&
ExitRoutine:
End Sub

Public Function GetFramePageCount(thePicture As StdPicture) As Long

    ' Returns the GIF/APNG frame count or TIF page count
    ' Picture must be managed for a valid return
    '   coder note: Why managed? When managed, multi-frame/page property is known else it is not
    
    Dim hImage As Long, tImage As Long
    Dim lObjPtr As Long, lCount As Long
    Dim lFlags As Long, lType As PictTypeEx
    Dim IStream As stdole.IUnknown
    
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle Then
        If zzSafeThunkAddress() Then
            lObjPtr = ObjPtr(thePicture)
            lFlags = CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags)
            lType = (lFlags And tfMaskPicType) \ tfShiftPicType
            Select Case lType
            Case picGIF, picTIF, picAPNG        ' else not these formats or not managed
                If (lFlags And tfMultiImage) Then
                    hImage = CallThunk(f_MsgAddr, lObjPtr, msgObjGetHImage)
                    If hImage = 0& Then
                        Set IStream = zzGetImageData(thePicture, False, (True))
                        If Not IStream Is Nothing Then GdipLoadImageFromStream ObjPtr(IStream), tImage
                        If tImage = 0& Then GoTo ExitRoutine
                        hImage = tImage
                    End If
                    If lType = picGIF Then
                        If m_PageGUID(0, 0) = 0& Then
                            GdipImageGetFrameDimensionsCount hImage, lType
                            If lType > 0& Then GdipImageGetFrameDimensionsList hImage, m_PageGUID(0, 0), 1&
                        End If
                        GdipImageGetFrameCount hImage, m_PageGUID(0, 0), lCount
                    Else
                        If m_PageGUID(0, 1) = 0& Then IIDFromString StrPtr(TIFFPageDimension), m_PageGUID(0, 1)
                        GdipImageGetFrameCount hImage, m_PageGUID(0, 1), lCount
                    End If
                    If tImage Then GdipDisposeImage tImage
                End If
                If lCount = 0& Then lCount = 1&
            End Select
        End If
    End If
    
ExitRoutine:
    GetFramePageCount = lCount
    
End Function

Public Function SetFrameGifPng(thePicture As StdPicture, ByVal FrameNumber As Long, _
                            Optional PictureHost As Object = Nothing) As Boolean

    ' Picture must be managed as enhanced for a valid return
    '   coder note: Why Enhanced? Navigation enabled only when enhanced
    ' FrameNumber is one-bound, first frame is #1, second is #2, etc.
    ' If this is for a picture property, passing PictureHost as the picture's
    '   object (control/form) will ensure it gets refreshed automatically
    
    If FrameNumber < 1& Then Exit Function
    
    Dim lObjPtr As Long, hImage As Long, lCount As Long, lFlags As Long
    
    lCount = Me.GetFramePageCount(thePicture)
    If lCount > 1& And FrameNumber <= lCount Then
        lObjPtr = ObjPtr(thePicture)
        hImage = CallThunk(f_MsgAddr, lObjPtr, msgObjGetHImage)
        If hImage = 0& Then Exit Function   ' can't navigate if not enhanced
        lFlags = CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags)
        If (lFlags And tfRecursing) Then Exit Function
        Select Case (lFlags And tfMaskPicType) \ tfShiftPicType
        Case picGIF
            SetFrameGifPng = (GdipImageSelectActiveFrame(hImage, m_PageGUID(0, 0), FrameNumber - 1&) = 0&)
        Case picAPNG
            SetFrameGifPng = (GdipImageSelectActiveFrame(hImage, m_PageGUID(0, 1), FrameNumber - 1&) = 0&)
        Case Else: Exit Function
        End Select
        If Not PictureHost Is Nothing Then
            On Error Resume Next
            PictureHost.Refresh
            On Error GoTo 0
        End If
    End If

End Function

Public Function SetPageTIF(thePicture As StdPicture, ByVal PageNumber As Long, _
                            Optional PictureHost As Object = Nothing) As StdPicture

    ' Picture must be managed as enhanced and original format must be cached for a valid return
    ' PageNumber is one-bound, first page is #1, second is #2, etc.
    ' Picture must be enhanced
    '   coder note: Why Enhanced? Navigation enabled only when enhanced
    
    ' Note: This can return a different picture object if the requested page is
    '   a different size than the current page size.
    ' If this is for a picture property, passing PictureHost as the picture's control/form
    '   will ensure it gets refreshed automatically
    
    ' Suggestion: Always use a temp stdPicture variable for this method's return.
    '   Then you can compare width/height with your existing picture to see if page size changed.
    ' i.e.,
    '    Dim tPic As StdPicture
    '    Set tPic = cStdPicEx.SetPageTIF(Image1.Picture, 2)
    '    If tPic.Width = Image1.Picture.Width And tPic.Height = Image1.Picture.Height Then
    '        ' same size
    '    Else
    '        ' not same size
    '    End If
    
    If PageNumber < 1& Then Exit Function
    
    Dim lObjPtr As Long, hImage As Long, lCount As Long
    Dim fRect(0 To 7) As Single, tPic As StdPicture
    Dim lFlags As Long, hGDIp As Long, hCallbk As Long
    Dim hBmp As Long, lVersion As Long
    
    Set tPic = thePicture
    lCount = Me.GetFramePageCount(thePicture)
    If lCount > 1& And PageNumber <= lCount Then
        lObjPtr = ObjPtr(thePicture)
        If (CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags) And tfMaskPicType) \ tfShiftPicType = picTIF Then
            lFlags = CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags, , VarPtr(lVersion))
            If (lFlags And tfRecursing) Then GoTo ExitRoutine
            
            hImage = CallThunk(f_MsgAddr, lObjPtr, msgObjGetHImage) ' if multi-page, will have hImage
            GdipGetImageBounds hImage, fRect(0), SrcUnit_Pixel      ' see if same size as current page
            If GdipImageSelectActiveFrame(hImage, m_PageGUID(0, 1), PageNumber - 1&) = 0& Then
                GdipGetImageBounds hImage, fRect(4), SrcUnit_Pixel
                If Not (fRect(2) = fRect(6) And fRect(3) = fRect(7)) Then
                    If Not lVersion = RECORD_VERSION Then GoTo ExitRoutine
                    Set tPic = Nothing                              ' different size page, create new picture
                    zzFillImage hImage, hBmp, -1&
                    If hBmp Then Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
                    If zzAddClient(tPic, 0&) Then
                        ' remove GDI+ and/or callback records before unmanaging, to prevent destruction
                        hGDIp = CallThunk(f_MsgAddr, lObjPtr, msgObjGetGDIpArr)
                        hCallbk = CallThunk(f_MsgAddr, lObjPtr, msgObjGetCBaddr)
                        CallThunk f_MsgAddr, lObjPtr, msgObjSetCBaddr, 0&
                        CallThunk f_MsgAddr, lObjPtr, msgObjSetGDIpArr, 0&
                        zzUnmanage thePicture
                        
                        ' reapply the GDI+ and/or callback record and set the flags
                        lObjPtr = ObjPtr(tPic)
                        CallThunk f_MsgAddr, lObjPtr, msgObjSetFlags, lFlags
                        CallThunk f_MsgAddr, lObjPtr, msgObjSetCBaddr, hCallbk
                        CallThunk f_MsgAddr, lObjPtr, msgObjSetGDIpArr, hGDIp
                    End If
                ElseIf Not PictureHost Is Nothing Then
                    On Error Resume Next
                    PictureHost.Refresh
                    On Error GoTo 0
                End If
            End If
        End If
    End If
ExitRoutine:
    Set SetPageTIF = tPic

End Function

Public Function SetCallBacks(thePicture As StdPicture, Optional ByVal PictureKey As String = vbNullString, _
                            Optional ByVal Mode As RenderEvents = rcbkNoCallbacks, _
                            Optional ByVal KeepHimetricValues As Boolean = False) As Boolean

    ' WARNING    WARNING    WARNING    WARNING
    ' ------------------------------------------------------------------------------------------------
    ' The COUNT_PUBLIC constant's value in declarations section must be correct else crash
    ' ------------------------------------------------------------------------------------------------

    ' if you are using callbacks for more than 1 subclassed picture, then
    '   you should always provide a unique Key for the picture. That key
    '   is passed to all callback events.
    ' The picture must be managed already
    
    ' This routine creates/updates a callback record. That record is actually a 16 byte blob.
    '   Coder note: existing callback records may have a string that must be freed here
    ' The callback record is referenced in the thunk's Options collection, so that collection
    '   may need to be updated to include a new record pointer and/or changed option value
    
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function
    If Mode < rcbkNoCallbacks Or Mode > rcbkOwnerDrawn Then Exit Function
    
    Dim lPtrKey As Long, lPtrCallBk As Long
    Dim lFlags As ThunkFlagsEnum, bValidation As Boolean
    Dim lObjPtr As Long, lVersion As Long
    Dim arrData() As Long, arrSafeArray() As Long
    Const ERROR_UNSUPPORTED As Long = 438
    
    If zzSafeThunkAddress() = False Then Exit Function
    
    lObjPtr = ObjPtr(thePicture)            ' see if picture is managed
    If CallThunk(f_MsgAddr, lObjPtr, msgObjPtrIndex, , VarPtr(lVersion)) < 1& Then Exit Function
    
    lFlags = CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags)
    If (lFlags And tfRecursing) Then
        If Mode > rcbkNoCallbacks Then Exit Function
    End If
    If Not Mode = rcbkNoCallbacks Then
        If Not lVersion = RECORD_VERSION Then Exit Function
        RaiseEvent EventHandler(bValidation)
        If bValidation = False Then             ' you must respond to the event just raised
            Err.Raise ERROR_UNSUPPORTED         ' else error: Object doesn't support this property or method
            Exit Function
        End If                                  ' OwnerDrawn can only use ownderdrawn callback
        If Mode = rcbkOwnerDrawn Then           ' non-OwnerDrawn cannot use that callback
            If (lFlags And tfMgmtOwnerDrawn) = 0& Then Exit Function
            Mode = rcbkPreRenderOnly            ' thunk-wise: rcbkOwnerDrawn=rcbkPreRenderOnly
        ElseIf (lFlags And tfMgmtOwnerDrawn) Then
            Exit Function
        End If
    End If
    
    If (lFlags And tfCBflags) Then              ' callbacks exist; reuse array or remove it
        lPtrCallBk = CallThunk(f_MsgAddr, lObjPtr, msgObjGetCBaddr)
        lPtrKey = CallThunk(f_MsgAddr, lObjPtr, msgObjGetKey)
        If lPtrKey Then SysFreeString lPtrKey   ' free key
        If Mode = rcbkNoCallbacks Then
            CallThunk f_MsgAddr, lObjPtr, msgObjSetCBaddr, 0&    ' remove record
            CoTaskMemFree lPtrCallBk            ' free record
            lFlags = lFlags And Not tfCBflags   ' update & set new flags
            CallThunk f_MsgAddr, lObjPtr, msgObjSetFlags, lFlags
            GoTo ExitRoutine
        End If
        lFlags = (lFlags And Not tfCBflags) Or Mode * &H10&
    Else        ' appending callback
        If Mode = rcbkNoCallbacks Then          ' none exists, none set
            SetCallBacks = True: Exit Function  ' done
        End If
        lPtrCallBk = CoTaskMemAlloc(16&)
        If lPtrCallBk = 0& Then Exit Function   ' low on memory?
    End If
    
    If PictureKey = vbNullString Then           ' create key
        lPtrKey = 0&
    Else
        lPtrKey = SysAllocStringLen(0&, Len(PictureKey))
        If lPtrKey Then CopyMemory ByVal lPtrKey, ByVal StrPtr(PictureKey), LenB(PictureKey)
    End If
    
    zzOverlayArray VarPtrArray(arrData()), lPtrCallBk, arrSafeArray(), 4&, False
    arrData(0) = lPtrKey                        ' build record
    arrData(1) = ObjPtr(Me)
    CopyMemory lPtrKey, ByVal arrData(1), 4&
    CopyMemory arrData(2), ByVal zzSafeOffset32(lPtrKey, &H1C& + COUNT_PUBLIC * 4&), 4&
    CopyMemory arrData(3), ByVal zzSafeOffset32(lPtrKey, &H1C& + COUNT_PUBLIC * 4& + 4&), 4&
    zzOverlayArray VarPtrArray(arrData()), 0&, arrSafeArray(), 0&, False
    
    If (lFlags And tfCBflags) = 0& Then         ' reuse or new record?
        lFlags = lFlags Or Mode * &H10&         ' create new record & apply
        CallThunk f_MsgAddr, lObjPtr, msgObjSetCBaddr, lPtrCallBk
    End If
    If KeepHimetricValues = False Then lFlags = lFlags Or tfCBinPixels
    CallThunk f_MsgAddr, lObjPtr, msgObjSetFlags, lFlags    ' update & set new flags
    
ExitRoutine:
    m_EventsUsed = True                         ' flag used in Class_Terminate
    SetCallBacks = True

End Function

Public Function SetScalingQuality(thePicture As StdPicture, ByVal Quality As ScalingQuality, _
                                    Optional PictureHost As Object = Nothing) As Boolean

    ' Routine enables custom scaling options
    ' The picture must be managed as enhanced
    '   coder note: Why Enhanced? GDI+ is used for higher quality scaling; GDI+ only available when enhanced
    ' PictureHost is the stdPicture object's control/form if applicable and when passed,
    '   the host's Refresh method will be called
    
    ' By default, any enhanced picture will automatically be scaled with
    '   bicubic scaling, the highest quality option. However, as is the case
    '   with anything, exceptions apply. Per image, different algorithms can produce
    '   different/better results. And maybe one of the lesser qualities is better?
    
    ' Bicubic is considered the highest quality
    ' Bilinear is very good quality
    ' Nearest Neighbor is fastest, but considered poorest quality (similar to what VB does)
    ' sqNoGDIplusScaling will prevent GDI+ from being used for rendering if the
    '   only reason for its use is scaling

    If Quality < sqNoGDIplusScaling Or Quality > sqBicubic Then Exit Function
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function
    
    Dim lFlags As ThunkFlagsEnum, lObjPtr As Long, lVersion As Long
    
    If zzSafeThunkAddress() Then
        lObjPtr = ObjPtr(thePicture)
        If CallThunk(f_MsgAddr, lObjPtr, msgObjPtrIndex, , VarPtr(lVersion)) > 0& Then
            If Not lVersion = RECORD_VERSION Then Exit Function
            
            lFlags = (CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags) And Not tfScaleBicubic) Or Quality * tfScaleNN
            If (lFlags And tfMgmtFull) = 0& Then Exit Function
            CallThunk f_MsgAddr, lObjPtr, msgObjSetFlags, lFlags     ' update & set new flags
            SetScalingQuality = True
            If Not PictureHost Is Nothing Then
                On Error Resume Next
                PictureHost.Refresh
                On Error GoTo 0
            End If
        End If
    End If

End Function

Public Function SetImageAttributesHandle(thePicture As StdPicture, ByVal GDIpAttrHandle As Long, _
                                        Optional PictureHost As Object = Nothing) As Boolean

    ' Routine allows attaching a GDI+ image attributes handle to a picture
    ' The picture must be managed as enhanced
    '   coder note: Why Enhanced? GDI+ is only available when enhanced & this is a GDI+ attribute object
    ' PictureHost is the stdPicture object's control/form if applicable and when passed,
    '   the host's Refresh method will be called
    
    ' Any passed handle is your responsibility for destruction
    ' This routine clones passed attributes & disposes the copies when appropriate
    ' Passing zero will remove any previously assigned handle
    
    ' GDI+ attribute handles can be useful to modify colors without modifying the image
    '   itself. For example, drawing grayscale or shearing colors, etc. They can also
    '   be used to render with semi-transparency to picture's background (blending)

    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function
    
    Dim lObjPtr As Long, lVersion As Long
    Dim lHandle As Long, lFlags As ThunkFlagsEnum, lPtr As Long
    Dim arrData() As Long, arrSafeArray() As Long
    
    If zzSafeThunkAddress() Then
        lObjPtr = ObjPtr(thePicture)
        If CallThunk(f_MsgAddr, lObjPtr, msgObjPtrIndex, , VarPtr(lVersion)) > 0& Then
            If Not lVersion = RECORD_VERSION Then Exit Function
            
            lFlags = CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags) And Not tfGDIpAttrs
            If (lFlags And tfMgmtFull) = 0& Then Exit Function
            lPtr = CallThunk(f_MsgAddr, lObjPtr, msgObjGetGDIpArr)
            If lPtr = 0& Then                           ' create GDI+ subrecord
                lPtr = CoTaskMemAlloc(16&)
                If lPtr = 0& Then Exit Function
                FillMemory ByVal lPtr, 16&, 0&
                lVersion = 0&                           ' flag indicating record created
            End If
            zzOverlayArray VarPtrArray(arrData), lPtr, arrSafeArray(), 4&, False
            If arrData(1) Then                         ' has hAttributes
                GdipDisposeImageAttributes arrData(1)
                arrData(1) = 0&
            End If
            If GDIpAttrHandle Then                      ' dispose existing handle
                If GdipCloneImageAttributes(GDIpAttrHandle, arrData(1)) = 0& Then _
                    lFlags = lFlags Or tfGDIpAttrs
            End If
            zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, False
            CallThunk f_MsgAddr, lObjPtr, msgObjSetFlags, lFlags
            If lVersion = 0& Then CallThunk f_MsgAddr, lObjPtr, msgObjSetGDIpArr, lPtr
            SetImageAttributesHandle = True
            If Not PictureHost Is Nothing Then          ' refresh passed control
                On Error Resume Next
                PictureHost.Refresh
                On Error GoTo 0
            End If
        End If
    End If

End Function

Public Function SetForceGDIplusUsage(thePicture As StdPicture, ByVal Apply As Boolean, _
                                        Optional PictureHost As Object = Nothing) As Boolean

    ' Routine forces GDI+ to always be used when rendering.
    ' PictureHost is the stdPicture object's control/form if applicable and when passed,
    '   the host's Refresh method will be called
    
    ' Typically GDI+ is not used if image has no transparency and no scaling is required and
    '   you did not provide optional GDI+ image attributes.
    ' However, you may be using callbacks and always want a GDI+ environment to work with.
    ' The picture must be managed as enhanced
    '   coder note: Why Enhanced? GDI+ is only used with enhanced management style
    
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function

    Dim lObjPtr As Long, lFlags As ThunkFlagsEnum, lVersion As Long
    
    If zzSafeThunkAddress() Then
        lObjPtr = ObjPtr(thePicture)
        If CallThunk(f_MsgAddr, lObjPtr, msgObjPtrIndex, , VarPtr(lVersion)) > 0& Then
            If Not lVersion = RECORD_VERSION Then Exit Function
            lFlags = (CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags) And Not tfForceGDIp) Or Abs(Apply) * tfForceGDIp
            If (lFlags And tfMgmtFull) = 0& Then Exit Function
            CallThunk f_MsgAddr, lObjPtr, msgObjSetFlags, lFlags ' update & set new flags
            SetForceGDIplusUsage = True
            If Not PictureHost Is Nothing Then
                On Error Resume Next
                PictureHost.Refresh
                On Error GoTo 0
            End If
        End If
    End If
    
End Function

Public Function SetForceTransparency(thePicture As StdPicture, ByVal Apply As Boolean, _
                                        Optional PictureHost As Object = Nothing) As Boolean

    ' Routine adds/removes the flag to force VB to think an image contains transparency.
    ' The picture must be managed else there is not thunk record to update
    ' PictureHost is the stdPicture object's control/form if applicable and when passed,
    '   the host's Refresh method will be called

    ' Typically you only want to call this routine in this scenario, for image controls:
    '   You are introducing transparency AND
    '   The source image contains no transparency AND
    '   You are taking responsibility for rendering the image yourself, via Callbacks
    
    '   How do you introduce transparency? Several ways
    '   Rotation, blending, custom scaling that does not include the entire image control
    '   For example, if you rotate an image 45 degrees. What used to be covered by the
    '       image at normal orientation is no longer fully covered
    '   In this scenario, if you do not force transparency VB may not redraw what is
    '       behind the image until the image's container is refreshed
    
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function

    Dim lObjPtr As Long, lFlags As ThunkFlagsEnum, lVersion As Long
    
    If zzSafeThunkAddress() Then
        lObjPtr = ObjPtr(thePicture)
        If CallThunk(f_MsgAddr, lObjPtr, msgObjPtrIndex, , VarPtr(lVersion)) > 0& Then
            If Not lVersion = RECORD_VERSION Then Exit Function
            
            lFlags = (CallThunk(f_MsgAddr, lObjPtr, msgObjGetFlags) And Not tfTransparent) Or Abs(Apply) * tfTransparent
            CallThunk f_MsgAddr, lObjPtr, msgObjSetFlags, lFlags ' update & set new flags
            SetForceTransparency = True
            If Not PictureHost Is Nothing Then
                On Error Resume Next
                PictureHost.Refresh
                On Error GoTo 0
            End If
        End If
    End If
    
End Function

Public Property Get GDIplusVersion() As Single

    ' courtesy property. If v1.1 or higher returned, can use functions like GdipDrawImageFX
    ' note: when this class first loaded, GDI+ becomes available to the entire project
    ' and remains available until the project unloads, even if this class is unloaded.
    GDIplusVersion = m_GDIpVersion

End Property

Public Property Get GDIplusImage(thePicture As StdPicture) As Long
    ' This will return a GDI+ hImage object for the passed picture (if possible)
    ' Any returned handle is your responsibility for destruction with GdipDisposeImage
    ' Icons/Cursors may fail to return an image handle because GDI+ has issues with these
    ' Otherwise, this is the same as calling GetImageData, creating stream, loading GDI+ image from stream
    
    ' The returned image can be used to query its properties and metadata if desired
    
    Dim IStream As stdole.IUnknown
    Set IStream = zzGetImageData(thePicture, False, (True))
    If Not IStream Is Nothing Then GdipLoadImageFromStream ObjPtr(IStream), GDIplusImage

End Property

Public Sub GetImageDimensions(thePicture As StdPicture, Width As Long, Height As Long, _
                            Optional ByVal ScaleFromDPI As Long, Optional ByVal ScaleToDPI As Long)

    ' function returns image dimensions in pixels and is DPI aware
    ' passing the last two parameters as same value (default), results similar to ScaleX/Y(himetric to pixels)
    ' if your app is DPI-aware, this function returns true values in all DPIs, but
    '   VB will fail to return correct values in some DPIs
    '   if this returns a fractional value: 1440 / [SystemDPI], i.e. at 175% DPI: 1440 / 168
    '   then VB will fail to return the correct image dimensions when using ScaleX/Y
    ' note: DPI-awareness depends on whether you manifested your project for DPI-awareness

    Dim lDPI As Long
    Width = 0&: Height = Width
    If Not thePicture Is Nothing Then
        If thePicture.Handle Then
            lDPI = zzRealDPI
            Width = CLng(thePicture.Width / 2540! * lDPI)
            Height = CLng(thePicture.Height / 2540! * lDPI)
            If Not (ScaleFromDPI = ScaleToDPI) Then
                If ScaleFromDPI = 0& Then ScaleFromDPI = 96&
                If ScaleToDPI = 0& Then ScaleToDPI = lDPI
                Width = Width * (ScaleToDPI / ScaleFromDPI)
                Height = Height * (ScaleToDPI / ScaleFromDPI)
            End If
        End If
    End If
    
End Sub

Public Function GetGifPngAnimationInfo(thePicture As StdPicture, FrameDurations() As Long) As Boolean

    ' Method returns the duration for each GIF frame and the GIF/PNG loop count
    ' If the GIF/PNG is not managed as Enhanced and does not contain more than 1 frame,
    '   then function returns false and return parameters are undefined
    '   coder note: Why Enhanced? GDI+ is used to extract metadata; GDI+ only used when enhanced
    ' notes:
    '   FrameDurations() will be sized: 0 to number of GIF/PNG frames
    '   GIF/PNG loop count will be placed in array's zero position.
    '       Loop count can be zero indicating GIF/PNG doesn't have a count or count interpreted as infinite
    '   Each frame's duration is expressed as milliseconds (compatible with VB's timer)
    '       It is possible that frame durations can be zero & up to you to decide what should be used.
    '       In these cases, good results can be expected when duration set between 70 and 100 ms, but
    '       obviously depends on the GIF/PNG content or intent
    
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function
    
    Const PropertyTagFrameDelay As Long = &H5100
    Const PropertyTagLoopCount As Long = &H5101
    Dim lIndex As Long, hImage As Long, lCount As Long
    Dim arrData() As Byte, lSize As Long, pPointer As Long
    
    lCount = Me.GetFramePageCount(thePicture)   ' verifies frame count
    If lCount < 2& Then Exit Function           ' gotta have at least 2 frames to animate
    If Me.PictureTypeEx(thePicture) = picTIF Then Exit Function ' else a TIF, not a GIF
    
    hImage = CallThunk(f_MsgAddr, ObjPtr(thePicture), msgObjGetHImage)
    If hImage = 0& Then Exit Function
                                     
    GetGifPngAnimationInfo = True
    ReDim FrameDurations(0 To lCount)           ' get durations/intervals
    
    If GdipGetPropertyItemSize(hImage, PropertyTagFrameDelay, lSize) Then Exit Function
    ReDim arrData(0 To lSize - 1&)
    If GdipGetPropertyItem(hImage, PropertyTagFrameDelay, lSize, arrData(0)) Then Exit Function
    CopyMemory lSize, arrData(4), 4&
       
    CopyMemory pPointer, arrData(12), 4&
    If lSize > lCount * 4& Then lSize = lCount * 4&
    CopyMemory FrameDurations(1), ByVal pPointer, lSize
    If GdipGetPropertyItemSize(hImage, PropertyTagLoopCount, lSize) = 0& Then ' get loop count
        If lSize < UBound(arrData) Then
            If GdipGetPropertyItem(hImage, PropertyTagLoopCount, lSize, arrData(0)) = 0& Then
                CopyMemory lSize, arrData(4), 4&
                If lSize < 5& Then              ' this should always be 2
                    CopyMemory pPointer, arrData(12), 4&
                    CopyMemory FrameDurations(0), ByVal pPointer, lSize
                End If
            End If
        End If
    End If
        
    For lCount = 1& To lCount                ' convert 100ths of seconds to 1000ths of second
        If FrameDurations(lCount) < 0& Then
            FrameDurations(lCount) = 0&
        ElseIf FrameDurations(lCount) < &HF000000 Then
            FrameDurations(lCount) = FrameDurations(lCount) * 10&
        End If
    Next

End Function

Public Function RemoveAlphaChannel(thePicture As StdPicture) As StdPicture

    ' This function is primarily for use when bitmaps are retreived from the clipboard
    '   or unverified sources. For example, when a screen capture is created and placed
    '   on the clipboard, the alpha channel may contain garbage which can be mistakenly
    '   interpreted as a valid alpha channel. This routine removes the alpha channel.
    
    ' If channel was cleaned, the returned picture object will not be the same as what was passed
    ' i.e., If returnObject Is thePicture then ' no cleaning performed
    
    Dim uBMP As BITMAP, X As Long
    Dim hDib As Long, pvBits As Long
    Dim arrData() As Byte, arrSafeArray() As Long
    Const LR_CREATEDIBSECTION As Long = &H2000

    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then GoTo ExitRoutine
    
    If GetObjectA(thePicture.Handle, 24&, uBMP) = 0& Then GoTo ExitRoutine
    If uBMP.bmBitsPixel = 32& Then  ' validate alpha channel appears valid
        If zzValidateAlphaChannel(0&, thePicture.Handle) = 0& Then GoTo ExitRoutine
        ' create new bitmap and zeroize the alpha channel
        hDib = CopyImage(thePicture.Handle, 0&, 0&, 0&, LR_CREATEDIBSECTION)
        If hDib = 0& Then GoTo ExitRoutine
        If GetObjectA(hDib, 24&, uBMP) = 0& Then ' should not have happened; something is wrong!
            DeleteObject hDib: hDib = 0&
            GoTo ExitRoutine
        End If
        zzOverlayArray VarPtrArray(arrData), uBMP.bmBits, arrSafeArray(), uBMP.bmHeight * uBMP.bmWidth * 4&, True
        For X = 3& To UBound(arrData) Step 4
            arrData(X) = 255    ' make alpha channel 100% opaque; could also zeroize it instead
        Next
        zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, True
    End If

ExitRoutine:
    If hDib = 0& Then
        Set RemoveAlphaChannel = thePicture
    Else
        Set RemoveAlphaChannel = zzHandleToStdPicture(hDib, vbPicTypeBitmap)
    End If
    
End Function

Public Property Let EnableAPNGSupport(ByVal bSupport As Boolean)
    ' APNG is supported on demand only. Set this, as needed, before calling LoadPictureEx
    '   PNGs must be parsed manually to determine if it is an APNG format.
    '   Setting this property to true, allows APNG support, otherwise not supported (default).
    '   Reason for not supporting by default is that APNG is rare and requires additional code/time
    '   to even determine if the PNG format is really APNG. Faster PNG loading without checking.
    '   If not supported and an APNG is sent to LoadPictureEx, then the first frame
    '   will be processed, but no additional code is used due to the way APNG format is written.
    m_EnableAPNG = bSupport
End Property
Public Property Get EnableAPNGSupport() As Boolean
    EnableAPNGSupport = m_EnableAPNG
End Property

Public Function WrapImageHandleToStdPicture(ByVal hHandle As Long) As StdPicture

    ' This function simply wraps a bitmap, icon, or cursor handle within a new stdPicture object
    ' The passed handle must not already be assigned to a stdPicture or some VB property.
    ' If function returns a stdPicture, the passed handle is destroyed when stdPicture is destroyed
    
    If Not hHandle = 0& Then
        If zzBitmapFromHBMP(hHandle, WrapImageHandleToStdPicture, False, True) = 0& Then
            zzBitmapFromHICON WrapImageHandleToStdPicture, hHandle, 0&, -1&, 0&, 0&
        End If
    End If

End Function

Private Function zzAddClient(thePicture As StdPicture, lFlags As ThunkFlagsEnum, _
                            Optional hImage As Long, _
                            Optional pStream As Long, Optional StrmSize As Long) As Boolean

    ' routine creates or reuses records for a newly managed picture
    
    Dim lRedirect As Long, nIPicVTblOffset As Long
    Dim nIPicVtable As Long, nStdPicTbl As Long
    Dim arrData() As Long, arrSafeArray() As Long
    Dim arrRealloc() As Long, lSize As Long
    Dim lPtr As Long, ptrOptions As Long, bFail As Boolean
    Dim lIPicPtr As Long, lStdPicPtr As Long
    Dim n As Long, p As Long, lSizeNow As Long
    Dim tPic As IPicture
    
    Set tPic = thePicture
    lIPicPtr = ObjPtr(tPic)
    lStdPicPtr = ObjPtr(thePicture)
    Set tPic = Nothing

    CopyMemory nIPicVtable, ByVal lIPicPtr, 4&  ' cache IPicture VTable address
    CopyMemory nStdPicTbl, ByVal lStdPicPtr, 4& ' cache stdPicture VTable address

    n = CallThunk(f_MsgAddr, lIPicPtr, msgObjPtrIndex)
    If n > 0& Then                  ' currently managed & shouldn't be
        If m_Debug Then Debug.Print "unexpected: passed picture is already managed (cleanup may have failed)"
        zzUnmanage thePicture       ' unmanage to be safe, then re-manage
    End If
    
    ' if GDI+ or IStream passed, we need a GDI+ related record
    If Not (hImage = 0& And pStream = 0&) Then
        ptrOptions = CoTaskMemAlloc(16&)
        If ptrOptions = 0& Then Exit Function
        FillMemory ByVal ptrOptions, 16&, 0&
    End If

    ' return existing redirection record or create new one
    lRedirect = zzCreateRedirection(nIPicVtable, nStdPicTbl, nIPicVTblOffset)
    If lRedirect = 0& Then          ' shouldn't happen unless system is running out of memory
        If m_Debug Then Debug.Print "creation of redirect table failed"
        If ptrOptions Then CoTaskMemFree ptrOptions
        Exit Function
    End If
    
    ' locate the thunk objects collection of records & its current size in elements
    CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrObjs), 4&
    CopyMemory lSize, ByVal lPtr, 4&
    
    n = CallThunk(f_MsgAddr, 0&, msgObjPtrIndex)    ' find empty slot
    If n < 1& Then                                  ' table is full
        ReDim arrRealloc(0 To 2, 0 To 1)
        n = lSize \ 2&                              ' nr slots existing (array counter\2)
        If m_Debug Then Debug.Print "resizing record collection to"; n + 3; "items"
        For p = 0& To 2&                            ' reallocate for new record + 2 buffered
            Select Case p                           ' set array pointer, current size, new size
            Case 0  ' 2 entries per record (8 bytes)
                lSizeNow = n * 8&: lSize = lSizeNow + 24&       ' 24 = 8 * 3 new records
                CopyMemory arrRealloc(p, 0), ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrObjVtbls), 4&
            Case 1  ' 2 entries per record (8 bytes) + 4 byte counter
                lSizeNow = n * 8& + 4&: lSize = lSizeNow + 24&  ' 24 = 8 * 3 new records
                arrRealloc(p, 0) = lPtr
            Case 2  ' 3 entries per record (12 bytes)
                lSizeNow = n * 12&: lSize = lSizeNow + 36&      ' 36 = 12 * 3 new records
                CopyMemory arrRealloc(p, 0), ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrObjOptions), 4&
            End Select
            
            arrRealloc(p, 1) = CoTaskMemRealloc(arrRealloc(p, 0), lSize) ' reallocate array
            If arrRealloc(p, 1) = 0& Then           ' if failure, abort loop
                bFail = True: Exit For
            Else                                    ' zero out the 3 new records
                FillMemory ByVal zzSafeOffset32(arrRealloc(p, 1), lSizeNow), lSize - lSizeNow, 0&
            End If
        Next
        For p = 0& To 2&                            ' set new array pointers in thunk
            If arrRealloc(p, 1) Then                ' even if above loop failed (old pointers released)
                If Not arrRealloc(p, 0) = arrRealloc(p, 1) Then ' replace array pointer in thunk
                    CopyMemory ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrObjVtbls + p * 4&), arrRealloc(p, 1), 4&
                End If
                If p = 1& Then
                    If bFail = False Then           ' if no failure
                        lPtr = arrRealloc(p, 1)
                        n = n + n + 6&              ' update new slot index & counter element
                        CopyMemory ByVal lPtr, n, 4&
                    End If
                End If
            End If
        Next
        Erase arrRealloc()
        
        If bFail Then ' sanity check; reallocation should not have failed for such small arrays
            ' That should never, never happen. But hey, that's why we do sanity checks
            If m_Debug Then Debug.Print "failed to reallocate records collection"
            
            n = CallThunk(f_MsgAddr, lRedirect, msgRedirectIndex)
            CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrRedirects), 4&
            zzOverlayArray VarPtrArray(arrData), lPtr, arrSafeArray(), n * 4& + 2&, False
            arrData(n - 1&) = arrData(n - 1&) - 1&      ' decrement redirection client count
            If arrData(n - 1&) = 0& Then                ' zeroize record if this was only client
                arrData(n) = 0: arrData(n + 1&) = 0&
                arrData(n + 2&) = 0&: arrData(n + 3&) = 0&
                CoTaskMemFree lRedirect                 ' and free the array
            End If
            zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, False
            ' zzCreateRedirection increments thunk client count, decrement it
            CopyMemory n, ByVal p_ThunkAddr, 4&          ' update thunk client count
            CopyMemory ByVal p_ThunkAddr, n - 1&, 4&
            
            If ptrOptions Then CoTaskMemFree ptrOptions
            Exit Function
        End If
    Else
        n = n + n
    End If
    
    ' update the arrObjects record
    zzOverlayArray VarPtrArray(arrData), zzSafeOffset32(lPtr, n * 4& - 4&), arrSafeArray(), 2&, False
    arrData(0) = lStdPicPtr: arrData(1) = lIPicPtr
    zzOverlayArray VarPtrArray(arrData()), 0&, arrSafeArray(), 0&, False
    
    ' update the arrVTables record
    CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrObjVtbls), 4&
    zzOverlayArray VarPtrArray(arrData), zzSafeOffset32(lPtr, n * 4& - 8&), arrSafeArray(), 2&, False
    arrData(0) = nIPicVtable: arrData(1) = RECORD_VERSION
    zzOverlayArray VarPtrArray(arrData()), 0&, arrSafeArray(), 0&, False
    
    ' update the arrGDIplus record
    If ptrOptions Then
        zzOverlayArray VarPtrArray(arrData), ptrOptions, arrSafeArray(), 4&, False
        If hImage Then arrData(0) = hImage
        If pStream Then arrData(2) = pStream: arrData(3) = StrmSize
        zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, False
        CallThunk f_MsgAddr, lIPicPtr, msgObjSetGDIpArr, ptrOptions
    End If
        
    ' set flags and redirect passed picture
    CallThunk f_MsgAddr, lIPicPtr, msgObjSetFlags, lFlags
    CopyMemory ByVal lStdPicPtr, lRedirect, 4&
    CopyMemory ByVal lIPicPtr, zzSafeOffset32(lRedirect, nIPicVTblOffset), 4&
    
    If m_Debug Then Debug.Print lIPicPtr; " image managed with flags: 0x"; Right$("0000000" & Hex(lFlags), 8)
    
    zzAddClient = True

End Function

Private Function zzConvertColor(ByVal lColor As Long) As Long

    ' helper function to convert RGB to BGR for GDI+ usage. Returned color is always 100% opaque, on purpose
    If lColor < 0& Then lColor = GetSysColor(lColor And &HFF&)
    zzConvertColor = (lColor And &HFF00&) _
                    Or (lColor And &HFF) * &H10000 _
                    Or (lColor And &HFF0000) \ &H10000 Or &HFF000000
End Function

Private Function zzManageBMP(thePicture As StdPicture, ManageStyle As ManagementStyle, _
                            IStream As stdole.IUnknown, StrmSize As Long, _
                            lFlags As Long, bKOF As Boolean, FillColor As Long) As StdPicture
                            
    ' bKof: KeepOriginalFormat parameter in LoadPictureEx
    ' lFlags will contain tfIStream if original format is to be cached
    
    ' When new picture created
    ' New Style     bKOF    Result
    ' ---------------------------------------------------------------------------
    ' VbOnly        True    style changed to VbPlus if format can't be cached by VB
    '               T/F     any transparency not rendered
    ' VbPlus        T/F     same as VbOnly, events can be requested
    ' Enhanced      T/F     if transparency exists, rendered & GDI+ image created for rendering
    ' AutoSelect    n/a     same as Enhanced, bKOF forced as False
    
    Dim pStream As Long, hBmp As Long
    Dim lObjPtr As Long, hImage As Long
    Dim tPic As StdPicture, uBMP As BITMAP
    
    If ManageStyle = mgtAutoSelect Then ManageStyle = mgtEnhanced: bKOF = False
    If (lFlags And tfIStream) Then
        If bKOF = False Then    ' remove stream; exists only if VB can't cache format
            lFlags = lFlags Xor tfIStream
        Else                    ' ensure style doesn't prevent caching format
            If ManageStyle = mgtVbOnly Then ManageStyle = mgtVbPlus
            pStream = ObjPtr(IStream)
        End If
    End If
    
    If ManageStyle > mgtVbOnly Then
        If ManageStyle = mgtEnhanced Then   ' moving to enhanced
            If (lFlags And tfMaskTransp) Then
                zzGetCompatibleBmp hImage, thePicture, (lFlags And tfPicHasTransp)
                If hImage = 0& Then GoTo ExitRoutine
                lFlags = lFlags Or tfGDIpImage
            Else
                GetObjectA thePicture.Handle, 24&, uBMP
                If uBMP.bmBitsPixel < 9& And uBMP.bmBits = 0& Then
                    zzBitmapFromHBMP thePicture.Handle, tPic, False, False
                    If tPic Is Nothing Then GoTo ExitRoutine
                End If
            End If                          ' update flags
            lFlags = lFlags Or tfScaleBicubic
        End If
    
        ' create the thunk record
        If tPic Is Nothing Then Set tPic = thePicture
        If zzAddClient(tPic, lFlags Or (ManageStyle - 1&) * tfShiftMgmt, hImage, pStream, StrmSize) = True Then
            If Not pStream = 0& Then CallThunk f_MsgAddr, pStream, msgStrmAddRef
        ElseIf hImage Then
            GdipDisposeImage hImage
        End If
    End If
    
ExitRoutine:
    If tPic Is Nothing Then Set zzManageBMP = thePicture Else Set zzManageBMP = tPic

End Function

Private Function zzManageGIF(ManageStyle As ManagementStyle, _
                            IStream As stdole.IUnknown, StrmSize As Long, hImage As Long, _
                            bKOF As Boolean, FillColor As Long, pEventParam As Variant) As StdPicture
                            
    ' bKof: KeepOriginalFormat parameter in LoadPictureEx
    
    ' When new picture created or changing currently managed style
    ' New Style     bKOF    Result
    ' ---------------------------------------------------------------------------
    ' VbOnly        True    style changed to Enhanced if format can't be cached by VB
    '               False   VB renders transparency, cannot be enhanced as GIF
    ' VbPlus        T/F     same as VbOnly, events can be requested, no frame navigation
    ' Enhanced      True    can navigate frames (animated GIF), can use higher scaling options
    '               False   converted to alpha-supported bitmap
    ' AutoSelect    n/a     same as Enhanced, setting bKOF to True
    
    Dim pStream As Long, cPosSet As Currency
    Dim lObjPtr As Long, hBmp As Long, lFlags As Long
    Dim tImage As Long, tPic As StdPicture
    Dim pProps() As Long, fBounds() As Single, bAbort As Boolean
    
    ReDim pProps(0 To 2, 1 To 1): ReDim fBounds(0 To 3)
    GdipGetImageBounds hImage, fBounds(0), SrcUnit_Pixel
        pProps(0, 1) = fBounds(2): pProps(1, 1) = fBounds(3): Erase fBounds()
        If m_PageGUID(0, 0) = 0& Then GdipImageGetFrameDimensionsList hImage, m_PageGUID(0, 0), 1&
        ' get frame count and shift into pProps(2,1) then append alpha format
        GdipImageGetFrameCount hImage, m_PageGUID(0, 0), pProps(2, 1)
        If ManageStyle = mgtAutoSelect Then
            ManageStyle = mgtEnhanced
            bKOF = CBool(pProps(2, 1) > 1&)
        End If
        lFlags = zzValidateAlphaChannel(hImage, 0&)
        pProps(2, 1) = pProps(2, 1) * &H10 Or (lFlags \ &H20000000)
        RaiseEvent PreLoadPicture(picGIF, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, FillColor, bAbort, pEventParam)
        If bAbort Then GdipDisposeImage hImage: Exit Function
        If ManageStyle < mgtVbOnly Or ManageStyle > mgtOwnerDrawn Then ManageStyle = mgtEnhanced
        If (pProps(2, 1) \ &H10) > 1& Then lFlags = lFlags Or tfMultiImage Or tfTransparent
        Erase pProps()
    lFlags = lFlags Or picGIF * tfShiftPicType
    
    If bKOF = False Then ' may remain VB GIF, but if managed, will always be bitmap w/o original format
        ' convert to alpha-supported bmp only if enhanced
        zzBitmapFromTPG hImage, tPic, lFlags
        If Not tPic Is Nothing Then
            lFlags = (lFlags And tfMaskTransp) Or picBMP * tfShiftPicType
            GdipDisposeImage hImage: hImage = 0&
            Set zzManageGIF = zzManageBMP(tPic, ManageStyle, Nothing, 0&, lFlags, False, FillColor)
            Exit Function
        End If
    End If
    
    pStream = ObjPtr(IStream)   ' create VB picture
    CallThunk f_MsgAddr, pStream, msgStrmSetSeek, VarPtr(0@), VarPtr(cPosSet)
    Set tPic = zzIStreamToPicture(pStream, bKOF, StrmSize)
    CallThunk f_MsgAddr, pStream, msgStrmSetSeek, VarPtr(cPosSet)
    If tPic Is Nothing Then     ' VB couldn't load GIF? Deal with it
        zzFillImage hImage, hBmp, zzConvertColor(FillColor)
        If hBmp = 0& Then GdipDisposeImage hImage: GoTo ExitRoutine
        Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
        If Not ManageStyle = mgtOwnerDrawn Then ManageStyle = mgtEnhanced
        lFlags = lFlags Or tfIStream
    Else
        pStream = 0&
    End If
    
    If ManageStyle = mgtVbOnly Or tPic Is Nothing Then  ' unmanaging
        GdipDisposeImage hImage
    Else
        If ManageStyle = mgtEnhanced Then
            If (lFlags And (tfMaskTransp Or tfMultiImage)) Then ' want hImage
                lFlags = lFlags Or tfGDIpImage
            ElseIf hImage Then  ' we can dispose of hImage if applies
                GdipDisposeImage hImage: hImage = 0&
            End If
            lFlags = lFlags Or tfScaleBicubic   ' default when enhanced
        End If
        
        If zzAddClient(tPic, lFlags Or (ManageStyle - 1&) * tfShiftMgmt, hImage, pStream, StrmSize) = True Then
            If Not pStream = 0& Then CallThunk f_MsgAddr, pStream, msgStrmAddRef
        ElseIf hImage Then
            GdipDisposeImage hImage: hImage = 0&
        End If
    End If
            
ExitRoutine:
    Set zzManageGIF = tPic

End Function

Private Function zzManageICO(thePicture As StdPicture, ManageStyle As ManagementStyle, _
                            IStream As stdole.IUnknown, StrmSize As Long, hImage As Long, _
                            lFlags As Long, bKOF As Boolean) As StdPicture
                            
    Dim pStream As Long, tImage As Long, lObjPtr As Long
                            
    ' bKof: KeepOriginalFormat parameter in LoadPictureEx
    
    ' When new picture created or changing currently managed style
    ' New Style     bKOF    Result
    ' ---------------------------------------------------------------------------
    ' VbOnly        True    style changed to VbPlus if format not cached by VB
    '               T/F     alpha may not be rendered correctly
    ' VbPlus        T/F     same as VbOnly, events can be requested
    ' Enhanced      T/F     alpha rendered properly & GDI+ image created for rendering/scaling
    ' AutoSelect    n/a     same as Enhanced, bKOF forced as False
    
    If ManageStyle = mgtAutoSelect Then ManageStyle = mgtEnhanced: bKOF = False
    If hImage = 0& Then             ' failed creation during zzValidateIcon or unmanaged
        If ManageStyle = mgtEnhanced Then ManageStyle = mgtVbPlus
    ElseIf Not ManageStyle = mgtEnhanced Then
        GdipDisposeImage hImage: hImage = 0&
    End If
    If bKOF = True Then
        pStream = ObjPtr(IStream)
        If pStream Then
            lFlags = lFlags Or tfIStream
            If ManageStyle = mgtVbOnly Then ManageStyle = mgtVbPlus
        End If
    End If
    
    If ManageStyle = mgtVbOnly Then
        If hImage Then GdipDisposeImage hImage: hImage = 0&
    Else
        If ManageStyle = mgtEnhanced Then
            If hImage = 0& Then     ' absolutely required if enhanced
                zzBitmapFromHICON Nothing, thePicture.Handle, tImage, -2&, 0&, 0&
                If tImage = 0& Then GoTo ExitRoutine ' can't enhance if no GDI+ image
                tImage = hImage
            End If
            lFlags = lFlags Or tfGDIpImage Or tfScaleBicubic
        Else
            If hImage Then GdipDisposeImage hImage: hImage = 0&
        End If
        
        If zzAddClient(thePicture, lFlags Or (ManageStyle - 1&) * tfShiftMgmt Or tfTransparent, hImage, pStream, StrmSize) = True Then
            If Not pStream = 0& Then CallThunk f_MsgAddr, pStream, msgStrmAddRef
        ElseIf hImage Then
            GdipDisposeImage hImage
        End If
    End If
    
ExitRoutine:
    Set zzManageICO = thePicture

End Function

Private Function zzManageJPG(ManageStyle As ManagementStyle, _
                            IStream As stdole.IUnknown, StrmSize As Long, _
                            hImage As Long, bKOF As Boolean, _
                            pEventParam As Variant) As StdPicture
                            
    Dim pStream As Long, cPosSet As Currency
    Dim lObjPtr As Long, hBmp As Long
    Dim tPic As StdPicture, lFlags As Long
    Dim pProps() As Long, fBounds() As Single, bAbort As Boolean
    
    ' bKof: KeepOriginalFormat parameter in LoadPictureEx
    
    ' When new picture created
    ' New Style     bKOF    Result
    ' ---------------------------------------------------------------------------
    ' VbOnly        True    style changed to VbPlus if format not cached by VB (CMYK color space)
    ' VbPlus        T/F     same as VbOnly, events can be requested
    ' Enhanced      T/F     orientation correction applied
    ' AutoSelect    n/a     same as Enhanced, bKOF forced as False, image format is Bitmap
    
    lFlags = picJPG * tfShiftPicType
    ReDim pProps(0 To 2, 1 To 1): ReDim fBounds(0 To 3)
    If ManageStyle = mgtAutoSelect Then bKOF = False: ManageStyle = mgtEnhanced
    ' gather property information and send event
    GdipGetImageBounds hImage, fBounds(0), SrcUnit_Pixel
        pProps(0, 1) = fBounds(2): pProps(1, 1) = fBounds(3): Erase fBounds()
        pProps(2, 1) = zzBitmapFromJPG(hImage, Nothing, False, True) ' check for orientation correction
        RaiseEvent PreLoadPicture(picJPG, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, -1&, bAbort, pEventParam)
        Erase pProps()
        If bAbort Then GdipDisposeImage hImage: Exit Function
    If ManageStyle < mgtVbOnly Or ManageStyle > mgtOwnerDrawn Then ManageStyle = mgtEnhanced
    
    zzBitmapFromJPG hImage, tPic, (ManageStyle = mgtEnhanced), False
    If tPic Is Nothing Then         ' no CMYK conversion/orientation correction needed
        CallThunk f_MsgAddr, ObjPtr(IStream), msgStrmSetSeek, VarPtr(0@), VarPtr(cPosSet)
        Set tPic = zzIStreamToPicture(ObjPtr(IStream), bKOF, StrmSize)
        CallThunk f_MsgAddr, ObjPtr(IStream), msgStrmSetSeek, VarPtr(cPosSet)
        If tPic Is Nothing Then     ' hmmm, VB couldn't load JPG, deal with it
            GdipCreateHBITMAPFromBitmap hImage, hBmp, -1&
            GdipDisposeImage hImage: hImage = 0&
            If hBmp = 0& Then GoTo ExitRoutine  ' failure
            Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
            If bKOF = True Then     ' cache stream
                lFlags = lFlags Or tfIStream
            ElseIf ManageStyle = mgtVbOnly Then ' done
                GoTo ExitRoutine
            End If
        End If
    Else    ' cache source, VB can't cache source
        lFlags = lFlags Or tfIStream
    End If
    If hImage Then GdipDisposeImage hImage: hImage = 0&
    
    If bKOF = False Then            ' not keeping format, manage as bitmap
        Set zzManageJPG = zzManageBMP(tPic, ManageStyle, Nothing, 0&, picBMP * tfShiftPicType, False, 0&)
        Exit Function
    ElseIf (lFlags And tfIStream) Then ' ensure manage style allows caching
        If ManageStyle = mgtVbOnly Then ManageStyle = mgtVbPlus
        pStream = ObjPtr(IStream)
    End If
        
    If ManageStyle > mgtVbOnly And (Not tPic Is Nothing) Then
        If ManageStyle = mgtEnhanced Then lFlags = lFlags Or tfScaleBicubic
    
        If zzAddClient(tPic, lFlags Or (ManageStyle - 1&) * tfShiftMgmt, 0&, pStream, StrmSize) Then
            If Not pStream = 0& Then CallThunk f_MsgAddr, pStream, msgStrmAddRef
        End If
    End If
            
ExitRoutine:
    zzManageJPG = tPic
   
End Function

Private Function zzManagePNG(ManageStyle As ManagementStyle, _
                            IStream As stdole.IUnknown, StrmSize As Long, _
                            hImage As Long, bKOF As Boolean, FillColor As Long, _
                            pEventParam As Variant) As StdPicture
                            
    ' bKof: KeepOriginalFormat parameter in LoadPictureEx
    
    ' When new picture created or changing currently managed style
    ' New Style     bKOF    Result
    ' ---------------------------------------------------------------------------
    ' VbOnly        True    style changed to VbPlus, format cached by thunk, transparency filled
    '               False   PNG converted to bitmap, transparency filled
    ' VbPlus        T/F     same as VbOnly, events can be requested
    ' Enhanced      True    transparency rendered
    '               False   transparency filled, PNG converted to bitmap
    ' AutoSelect    n/a     single page: coverted to alpha-supported bitmap and enhanced
    '                       multi page: enhanced, remains PNG, format not cached
    
    ' PNG will always have a stream if format is kept
    ' GDI+ image may exist, bound to that stream if image is enhanced and
    '   - first page transparency exists or multi-page format
    
    Dim pStream As Long, bAbort As Boolean
    Dim lObjPtr As Long, lFlags As Long
    Dim tImage As Long, tPic As StdPicture, hBmp As Long
    Dim pProps() As Long, fBounds() As Single
    
    ReDim fBounds(0 To 3): ReDim pProps(0 To 2, 1 To 1)
    ' get a few image properties & raise event
        GdipGetImageBounds hImage, fBounds(0), SrcUnit_Pixel
        pProps(0, 1) = fBounds(2): pProps(1, 1) = fBounds(3): Erase fBounds()
        If m_EnableAPNG Then            ' determine if APNG format
            pProps(2, 1) = zzValidateAPNG(ObjPtr(IStream), StrmSize, pProps(0, 1), pProps(1, 1))
            If pProps(2, 1) > 1& Then lFlags = lFlags Or tfMultiImage Else pProps(2, 1) = 1&
        Else
            pProps(2, 1) = 1&
        End If
        If ManageStyle = mgtAutoSelect Then bKOF = False
        lFlags = zzValidateAlphaChannel(hImage, 0&)
        pProps(2, 1) = pProps(2, 1) * &H10 Or (lFlags \ &H20000000)
        RaiseEvent PreLoadPicture(picPNG, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, FillColor, bAbort, pEventParam)
        If bAbort Then GdipDisposeImage hImage: Exit Function
        If ManageStyle < mgtAutoSelect Or ManageStyle > mgtOwnerDrawn Then ManageStyle = mgtAutoSelect
        If (pProps(2, 1) \ &H10) > 1& Then lFlags = lFlags Or tfMultiImage Or tfTransparent
        Erase pProps()
    If (lFlags And tfMultiImage) Then
        lFlags = lFlags Or picAPNG * tfShiftPicType
    Else
        lFlags = lFlags Or picPNG * tfShiftPicType
    End If

    If bKOF = False And (ManageStyle > mgtAutoSelect Or (lFlags And tfMultiImage) = 0&) Then
        ' managed as alpha-supported bitmap, convert to alpha-supported bmp only if enhanced
        zzBitmapFromTPG hImage, tPic, lFlags
        If Not tPic Is Nothing Then
            lFlags = (lFlags And tfMaskTransp) Or picBMP * tfShiftPicType
            GdipDisposeImage hImage: hImage = 0&
            Set zzManagePNG = zzManageBMP(tPic, ManageStyle, Nothing, 0&, lFlags, False, FillColor)
            GoTo Cleanup
        End If
    ElseIf ManageStyle = mgtAutoSelect Then
        ManageStyle = mgtEnhanced
    Else
        lFlags = lFlags Or tfIStream: pStream = ObjPtr(IStream)
    End If
    
    zzFillImage hImage, hBmp, zzConvertColor(FillColor)
    If hBmp = 0& Then GdipDisposeImage hImage: GoTo ExitRoutine
    Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
    If ManageStyle = mgtVbOnly Then
        GdipDisposeImage hImage: hImage = 0&
        Set zzManagePNG = zzManageBMP(tPic, ManageStyle, Nothing, 0&, picBMP * tfShiftPicType, False, FillColor)
        GoTo Cleanup
    End If
    
    If (lFlags And tfMultiImage) Then   ' create multi-page TIF as substitute for APNG
        tImage = zzTIFfromAPNG(hImage, ObjPtr(IStream), StrmSize)
        If tImage Then
            GdipDisposeImage hImage: hImage = tImage
        Else
            lFlags = (lFlags And Not (tfMaskPicType Or tfMultiImage)) Or picPNG * tfShiftPicType
        End If
    End If
    
    If ManageStyle = mgtEnhanced Then
        If (lFlags And (tfMultiImage Or tfMaskTransp)) Then
            lFlags = lFlags Or tfGDIpImage
        ElseIf hImage Then
            GdipDisposeImage hImage: hImage = 0&
        End If
        lFlags = lFlags Or tfScaleBicubic
    Else
        If hImage Then GdipDisposeImage hImage: hImage = 0&
    End If
    
    If zzAddClient(tPic, lFlags Or (ManageStyle - 1&) * tfShiftMgmt, hImage, pStream, StrmSize) Then
        If pStream Then CallThunk f_MsgAddr, pStream, msgStrmAddRef
    ElseIf hImage Then
        GdipDisposeImage hImage
    End If
            
ExitRoutine:
    Set zzManagePNG = tPic
    
Cleanup:
    If m_EnableAPNG Then
        Erase m_CRC32LUT
        Erase m_APNGdat.Frames()
    End If

End Function

Private Function zzManageTIF(ManageStyle As ManagementStyle, _
                            IStream As stdole.IUnknown, StrmSize As Long, _
                            hImage As Long, bKOF As Boolean, FillColor As Long, _
                            pEventParam As Variant) As StdPicture
                            
    ' bKof: KeepOriginalFormat parameter in LoadPictureEx
    
    ' When new picture created or changing currently managed style
    ' New Style     bKOF    Result
    ' ---------------------------------------------------------------------------
    ' VbOnly        True    style changed to VbPlus, format cached by thunk, transparency filled
    '               False   TIF converted to bitmap, transparency filled
    ' VbPlus        T/F     same as VbOnly, events can be requested
    ' Enhanced      True    transparency rendered, pages can be navigated
    '               False   transparency filled, TIF converted to bitmap
    ' AutoSelect    n/a     single page: coverted to alpha-supported bitmap and enhanced
    '                       multi page: enhanced, remains TIF, format not cached
    
    ' TIF will always have a stream if format is kept
    ' GDI+ image may exist, bound to that stream if image is enhanced and
    '   - first page transparency exists or multi-page format
    
    Dim pStream As Long, bAbort As Boolean
    Dim lObjPtr As Long, lFlags As Long
    Dim tImage As Long, tPic As StdPicture, hBmp As Long
    Dim pProps() As Long, fBounds() As Single
    
    ReDim fBounds(0 To 3): ReDim pProps(0 To 2, 1 To 1)
    If m_PageGUID(0, 1) = 0& Then IIDFromString StrPtr(TIFFPageDimension), m_PageGUID(0, 1)
    ' get a few image properties & raise event
        GdipGetImageBounds hImage, fBounds(0), SrcUnit_Pixel
        pProps(0, 1) = fBounds(2): pProps(1, 1) = fBounds(3): Erase fBounds()
        GdipImageGetFrameCount hImage, m_PageGUID(0, 1), pProps(2, 1)
        If ManageStyle = mgtAutoSelect Then bKOF = False
        lFlags = zzValidateAlphaChannel(hImage, 0&)
        pProps(2, 1) = pProps(2, 1) * &H10 Or (lFlags \ &H20000000)
        RaiseEvent PreLoadPicture(picTIF, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, FillColor, bAbort, pEventParam)
        If bAbort Then GdipDisposeImage hImage: Exit Function
        If ManageStyle < mgtAutoSelect Or ManageStyle > mgtOwnerDrawn Then ManageStyle = mgtAutoSelect
        If (pProps(2, 1) \ &H10) > 1& Then lFlags = lFlags Or tfMultiImage Or tfTransparent
        Erase pProps()
    lFlags = lFlags Or picTIF * tfShiftPicType

    If bKOF = False And (ManageStyle > mgtAutoSelect Or (lFlags And tfMultiImage) = 0&) Then
        ' managed as alpha-supported bitmap, convert to alpha-supported bmp only if enhanced
        zzBitmapFromTPG hImage, tPic, lFlags
        If Not tPic Is Nothing Then
            lFlags = (lFlags And tfMaskTransp) Or picBMP * tfShiftPicType
            GdipDisposeImage hImage: hImage = 0&
            Set zzManageTIF = zzManageBMP(tPic, ManageStyle, Nothing, 0&, lFlags, False, FillColor)
            Exit Function
        End If
    ElseIf ManageStyle = mgtAutoSelect Then
        ManageStyle = mgtEnhanced
    Else
        lFlags = lFlags Or tfIStream: pStream = ObjPtr(IStream)
    End If
    
    zzFillImage hImage, hBmp, zzConvertColor(FillColor)
    If hBmp = 0& Then GdipDisposeImage hImage: GoTo ExitRoutine
    Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
    If ManageStyle = mgtVbOnly Then
        GdipDisposeImage hImage: hImage = 0&
        Set zzManageTIF = zzManageBMP(tPic, ManageStyle, Nothing, 0&, picBMP * tfShiftPicType, False, FillColor)
        Exit Function
    End If
    
    If ManageStyle = mgtEnhanced Then
        If (lFlags And (tfMultiImage Or tfMaskTransp)) Then
            lFlags = lFlags Or tfGDIpImage
        ElseIf hImage Then
            GdipDisposeImage hImage: hImage = 0&
        End If
        lFlags = lFlags Or tfScaleBicubic
    Else
        If hImage Then GdipDisposeImage hImage: hImage = 0&
    End If
    
    If zzAddClient(tPic, lFlags Or (ManageStyle - 1&) * tfShiftMgmt, hImage, pStream, StrmSize) Then
        If pStream Then CallThunk f_MsgAddr, pStream, msgStrmAddRef
    ElseIf hImage Then
        GdipDisposeImage hImage
    End If
            
ExitRoutine:
    Set zzManageTIF = tPic

End Function

Private Function zzManageWMF(ManageStyle As ManagementStyle, _
                            IStream As stdole.IUnknown, StrmSize As Long, lType As PictureTypeConstants, _
                            hImage As Long, lFlags As Long, bKOF As Boolean, _
                            pEventParam As Variant) As StdPicture
                                
    ' routine processes both WMF & EMF. GDI+ EMFplus format not supported
    ' bKof: KeepOriginalFormat parameter in LoadPictureEx
    ' note: even when false, VB still creates a metafile stream for its own use, so always use True
    
    ' When new picture created or changing currently managed style
    ' New Style     bKOF    Result
    ' ---------------------------------------------------------------------------
    ' VbOnly        False   always treated as True unless non-placeable WMF
    ' VbPlus        T/F     same as VbOnly, events can be requested
    ' Enhanced      n/a     style changed to VbPlus, metafiles never enhanced
    ' AutoSelect    n/a     same as VbOnly, bKOF False for non-placeable WMF
    
    Dim pStream As Long, curPosition As Currency, hBmp As Long
    Dim pProps() As Long, bAbort As Boolean, tPic As StdPicture
    
    ReDim pProps(0 To 2, 1 To 1)
    pStream = ObjPtr(IStream)
    CallThunk f_MsgAddr, pStream, msgStrmSetSeek, VarPtr(0@), VarPtr(curPosition)
    Set tPic = zzIStreamToPicture(pStream, True, StrmSize)
    If tPic Is Nothing Then         ' failed? maybe non-placeable WMF
        If lType = vbPicTypeEMetafile Then
            lType = vbPicTypeMetafile
            CallThunk f_MsgAddr, pStream, msgStrmSetSeek, VarPtr(curPosition)
            zzMakeWMFplaceable tPic, hImage
            If tPic Is Nothing Then
                GdipDisposeImage hImage: GoTo ExitRoutine
            End If
            pProps(2, 1) = 1            ' non-placeable WMF
            lFlags = tfIStream
        Else
            GdipDisposeImage hImage
            Exit Function
        End If
    End If
    GdipDisposeImage hImage: hImage = 0&
    If tPic Is Nothing Then Exit Function
    
    If ManageStyle = mgtAutoSelect Then
        ManageStyle = mgtVbOnly
    ElseIf ManageStyle = mgtEnhanced Then
        ManageStyle = mgtVbPlus
    End If
    bKOF = CBool(pProps(2, 1) = 0&)
    Me.GetImageDimensions tPic, pProps(0, 1), pProps(1, 1), 96, 96
    RaiseEvent PreLoadPicture(lType, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, -1&, bAbort, pEventParam)
    Erase pProps()
    If bAbort Then Exit Function
    
    If ManageStyle < mgtVbOnly Or ManageStyle > mgtOwnerDrawn Then
        ManageStyle = mgtVbOnly: lFlags = 0&
    Else
        If ManageStyle = mgtEnhanced Then ManageStyle = mgtVbPlus
        If bKOF = False Then lFlags = 0&
    End If
    If (lFlags And tfIStream) Then pStream = ObjPtr(IStream)
    lFlags = lFlags Or lType * tfShiftPicType
    
    If ManageStyle > mgtVbOnly Then
        If zzAddClient(tPic, lFlags Or (ManageStyle - 1&) * tfShiftMgmt, 0&, pStream, StrmSize) = True Then
            If pStream Then CallThunk f_MsgAddr, pStream, msgStrmAddRef
        End If
    End If
    
ExitRoutine:
    Set zzManageWMF = tPic
    
End Function

Private Function zzSafeThunkAddress() As Boolean

    If m_hWndListener = 0& Then Exit Function

    Dim lOffset As Long
    Const OFFSET_CUSTOM As Long = 20    ' fixed byte position in target thunk
    
    p_ThunkAddr = SendMessage(m_hWndListener, msgListener_getThunk, 0&, ByVal 0&)
    If p_ThunkAddr = 0& Then Exit Function
    CopyMemory lOffset, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_CUSTOM), 4&
    f_MsgAddr = zzSafeOffset32(p_ThunkAddr, lOffset)
    zzSafeThunkAddress = True

    ' routine is called each time interface thunk needs to be queried/updated
    ' Reason: versioning. Under specific scenarios, it is possible that the
    '   thunk could be replaced by a newer version without the knowledge of
    '   this class version. To handle those scenarios, a few rules
    '   MUST ALWAYS be enforced in thunk creation/modification...
    
    ' 1) The main thunk's structure can have function pointers changed from
    '       version to version. No info can be removed from any earlier version.
    '       Those pointers are cached at known offsets inside the thunk.
    '       Additionally, a new version can add stuff to the thunk, but any
    '       added stuff is always appended. Therefore, each version of the
    '       thunk is always compatible with earlier versions.
    
    ' 2) This class behavior is consistent from version to version...
    '    When the class initializes, checks are made and class adjusts as needed.
    '    The class looks for a window at a known location (child of VB hidden owner).
    '    This child window format is unchanging. It uses its own subclassing thunk
    '       to detect its destruction and then performs cleanup as needed. This
    '       thunk caches the main thunk address to be cleaned up.
    '
    '    If window does not exist then no thunk yet exists:
    '
    '       Class creates API window on hidden VB owner and window's subclasing
    '       thunk. Then it creates main thunk and updates window's thunk with
    '       the main thunk's address and version. Done
    '
    '   If window already exists then a thunk exists then additional checks made
    '
    '       Class checks thunk version and if same or newer, then the class
    '           simply uses the existing thunk
    '       If thunk version is older, then the class creates the newer thunk,
    '           updates the api window thunk with the newer thunk's address
    '           and version, transfers data from the older thunk, then
    '           destroys the older thunk. See zzUpgradeThunk
    
    ' 3) Since the main thunk has potential of changing its memory address,
    '   this class will always verify that address before making any calls
    '   to the thunk. Typically, calls  are made to the thunk only when a
    '   picture is to be subclassed/unsubclassed or user-defined options are
    '   changed relative to a subclassed picture.
    
    ' Bottom line. After this class initializes, it is guaranteed to be using
    '   a compatible thunk (pre-exsiting or not), even if the thunk was later
    '   replaced with a newer version. The only performance hit is a requirement
    '   to double check the thunk's address each and every call. Not a concern,
    '   since calls to the thunk should be relatively few and far between.

End Function

Private Function zzCreateThunk(bCreateListenerThunk As Boolean) As Boolean

    ' Coder note. See zzLocateThunk notes if thunk can no longer support backward compatibility

    ' This method creates up to 2 thunks: 1) for the listener window and 2) for VTable redirection
    ' VTable redirection thunk is fairly large and is basically a bas module in assembly that will
    '   reside in the VB/application process as long as VB/application is loaded. Since it resides
    '   in memory VB is unaware of, VB cannot inadvertently release the memory. This ensures that
    '   any managed picture always has something to callback to. This also prevents having to
    '   keep this class alive (unless you are receiving callbacks in your project).

    Const CB_PAGE_RWX    As Long = &H40         ' Allocate executable memory
    Const CB_MEM_COMMIT  As Long = &H1000       ' Commit allocated memory
    Const CB_MEM_RELEASE   As Long = &H8000&    ' Release allocated memory flag
    Const OFFSET_IUnknownRelease As Long = 24   ' thunk offset in cb() where IUnknown::Release reseides
    Const OFFSET_IPictureGetAttrs As Long = 41  ' thunk offset in cb() where IPicture::get_Attributes resides
    Const OFFSET_IPictureRender As Long = 62    ' thunk offset in cb() where IPicture::Render resides
    Const OFFSET_ThunkCustom As Long = 165      ' thunk offset in cb() where custom function resides
    Const OFFSET_ListenerOffset As Long = 32    ' thunk offset for start of listener's subclass procedure
    Const GWL_WNDPROC As Long = -4
    
    Dim FUNK_LEN As Long, cb() As Long, n As Long, hToken As Long
    Dim lValue As Long, lWinThunk As Long, hInstGDIplus As Long
    
    If bCreateListenerThunk Then                ' only when listener window 1st created
    
        If m_Debug Then Debug.Print "thunk being created"
    
        ReDim cb(0 To 3)                        ' start GDI+ and abort if failure
        cb(0) = 1
        hInstGDIplus = LoadLibrary("GdiPlus.dll")
        GdiplusStartup hToken, cb(0)
        If hToken Then
            FUNK_LEN = 36&                      ' reserve memory for listener's thunk
            lWinThunk = VirtualAlloc(0&, FUNK_LEN * 4&, CB_MEM_COMMIT, CB_PAGE_RWX)
            If lWinThunk Then
                ReDim cb(0 To FUNK_LEN - 1&)
               'cb(0) is main thunk's address (filled in when that thunk is created)
                cb(1) = hToken
                cb(2) = GetProcAddress(GetModuleHandleA("user32.dll"), "CallWindowProcA")
                lValue = GetModuleHandleA("kernel32.dll")
                cb(3) = GetProcAddress(lValue, "VirtualFree")
                cb(4) = GetProcAddress(lValue, "FreeLibrary")
                cb(5) = GetProcAddress(hInstGDIplus, "GdiplusShutdown")
                cb(6) = SetWindowLong(m_hWndListener, GWL_WNDPROC, zzSafeOffset32(lWinThunk, OFFSET_ListenerOffset))
                cb(7) = hInstGDIplus
                ' sanity check follows
                For n = 1& To 7&
                    If cb(n) = 0& Then Exit For
                Next
                If n < 7& Then
                    VirtualFree lWinThunk, 0&, CB_MEM_RELEASE: lWinThunk = 0&
                Else
                    cb(10) = lWinThunk
                    cb(8) = &HD231C031: cb(9) = &HBBE58960: cb(11) = &H7D81F631: cb(12) = &H800128: cb(13) = &H814F7400: cb(14) = &H8002287D: cb(15) = &H3C740000: cb(16) = &H2287D83: cb(17) = &H73FF1D75: cb(18) = &H1453FF04: cb(19) = &HFF1C73FF: cb(20) = &H33391053: cb(21) = &H680D74: cb(22) = &H56000080: cb(23) = &H53FF33FF: cb(24) = &HFF33890C
                    cb(25) = &H75FF3075: cb(26) = &H2875FF2C: cb(27) = &HFF2475FF: cb(28) = &H53FF1873: cb(29) = &H1C458908: cb(30) = &H10C261: cb(31) = &H892C458B: cb(32) = &H1C458903: cb(33) = &H38BF2EB: cb(34) = &HEB1C4589: cb(35) = &HEB&
                    CopyMemory ByVal lWinThunk, cb(0), FUNK_LEN * 4&   ' copy thunk to memory
                End If
            End If
        End If
        If lWinThunk = 0& Then
            If hToken Then GdiplusShutdown hToken
            FreeLibrary hInstGDIplus
            DestroyWindow m_hWndListener: m_hWndListener = 0&
            Exit Function
        End If
    End If
    
    FUNK_LEN = 537&                             ' reserve memory for main thunk
    p_ThunkAddr = VirtualAlloc(0&, FUNK_LEN * 4&, CB_MEM_COMMIT, CB_PAGE_RWX)
    If p_ThunkAddr = 0& Then Exit Function
    
    ReDim cb(0 To FUNK_LEN - 1&)
    
    ' the dll-like thunk, using primarily GDI+ for more flexibility/options, better scaling
    ' cb(0-21) are filled later

'    cb(22) = &HD231C031: cb(23) = &HBBE58960: cb(24) = &H12345678: cb(25) = &H3110EC83: cb(26) = &H431E8F6: cb(27) = &HC2890000: cb(28) = &H7401E183: cb(29) = &HE8C0310B: cb(30) = &H4B9&: cb(31) = &H8A048B49: cb(32) = &HFF2475FF: cb(33) = &H45890850: cb(34) = &H75F0391C: cb(35) = &H5ECE805: cb(36) = &HC4830000: cb(37) = &H4C26110: cb(38) = &H90909000: cb(39) = &HD231C031: cb(40) = &HBBE58960: cb(41) = &H12345678: cb(42) = &H3110EC83: cb(43) = &H287539F6: cb(44) = &HE8E83374: cb(45) = &HE8000003: cb(46) = &H436&: cb(47) = &HFFF8558B: cb(48) = &H75FF2875: cb(49) = &H4052FF24
'    cb(50) = &H8B1C4589: cb(51) = &HE181F44D: cb(52) = &H60000001: cb(53) = &H558B08E3: cb(54) = &H2C88328: cb(55) = &HC4830289: cb(56) = &H8C26110: cb(57) = &H1C45C700: cb(58) = &H80070057: cb(59) = &H9090F0EB: cb(60) = &HD231C031: cb(61) = &HBBE58960: cb(62) = &H12345678: cb(63) = &H3144EC83: cb(64) = &H447539F6: cb(65) = &H177840F: cb(66) = &H75390000: cb(67) = &H6E840F48: cb(68) = &H39000001: cb(69) = &H840F3475: cb(70) = &H165&: cb(71) = &HF387539: cb(72) = &H15C84: cb(73) = &HE0758900: cb(74) = &H372E8
'    cb(75) = &H41AE800: cb(76) = &HBBE80000: cb(77) = &H25000003: cb(78) = &H2000&: cb(79) = &HFCE80774: cb(80) = &HEB000005: cb(81) = &HF8558B11: cb(82) = &H51EC4D8D: cb(83) = &HFF2475FF: cb(84) = &HF0390C52: cb(85) = &H75890874: cb(86) = &H11CE91C: cb(87) = &H458B0000: cb(88) = &HBC458928: cb(89) = &H89E87589: cb(90) = &H7589E475: cb(91) = &HF4458BE0: cb(92) = &H750EE083: cb(93) = &HF4458B1D: cb(94) = &H30025: cb(95) = &H8B377400: cb(96) = &H25F445: cb(97) = &H74000030: cb(98) = &H424E82D: cb(99) = &HF0390000
'    cb(100) = &H4D832474: cb(101) = &H6DE802E0: cb(102) = &H39000003: cb(103) = &H1675E875: cb(104) = &H51E84D8D: cb(105) = &HEC75FF56: cb(106) = &H893C53FF: cb(107) = &HF039EC75: cb(108) = &H75830474: cb(109) = &H4D8B02E0: cb(110) = &H1E183E0: cb(111) = &H458B4475: cb(112) = &H10E083F4: cb(113) = &H4D833C74: cb(114) = &H70E801E0: cb(115) = &H8B000005: cb(116) = &H25F445: cb(117) = &H74000030: cb(118) = &H14753929: cb(119) = &H75890574: cb(120) = &H8379EB1C: cb(121) = &H7403E07D: cb(122) = &HF44D8B19: cb(123) = &H300E181: cb(124) = &HE740000
'    cb(125) = &H3B9E8: cb(126) = &H74F03900: cb(127) = &HEC753905: cb(128) = &H4D8B9075: cb(129) = &H2E183E0: cb(130) = &HD0E807E3: cb(131) = &HEB000003: cb(132) = &HF8558B2A: cb(133) = &HFF4C75FF: cb(134) = &H75FF4875: cb(135) = &H4075FF44: cb(136) = &HFF3C75FF: cb(137) = &H75FFD075: cb(138) = &HD875FFD4: cb(139) = &HFFDC75FF: cb(140) = &H75FFBC75: cb(141) = &H2052FF24: cb(142) = &H391C4589: cb(143) = &H1C751C75: cb(144) = &H83F44D8B: cb(145) = &H14E320E1: cb(146) = &H10E07D83: cb(147) = &H39E8057C: cb(148) = &H83000003: cb(149) = &HE802E065
'    cb(150) = &H4E3&: cb(151) = &H74E47539: cb(152) = &HE475FF06: cb(153) = &H394453FF: cb(154) = &HE74E875: cb(155) = &H83F44D8B: cb(156) = &H67502E1: cb(157) = &HFFE875FF: cb(158) = &HC4834053: cb(159) = &H2CC26144: cb(160) = &H1C45C700: cb(161) = &H800A017C: cb(162) = &H9090F0EB: cb(163) = &HD231C031: cb(164) = &HBBE58960: cb(165) = &H12345678: cb(166) = &H3110EC83: cb(167) = &H287D81F6: cb(168) = &H80&: cb(169) = &H458B597C: cb(170) = &H81388B24: cb(171) = &H82287D: cb(172) = &H22740000: cb(173) = &H812475FF: cb(174) = &H81287D
'    cb(175) = &HB740000: cb(176) = &H890457FF: cb(177) = &H9BE91C45: cb(178) = &HFF000001: cb(179) = &H45890857: cb(180) = &H190E91C: cb(181) = &H458B0000: cb(182) = &H74F03930: cb(183) = &H3075FF0D: cb(184) = &H5656016A: cb(185) = &HFF2475FF: cb(186) = &H458B1457: cb(187) = &HFF56562C: cb(188) = &H30FF0470: cb(189) = &HFF2475FF: cb(190) = &H67E91457: cb(191) = &H89000001: cb(192) = &H33391C75: cb(193) = &H15C840F: cb(194) = &H7D830000: cb(195) = &H8F0F1F28: cb(196) = &H13B&: cb(197) = &H186E8: cb(198) = &HFC753900: cb(199) = &H7539097F
'    cb(200) = &H3F850F28: cb(201) = &H39000001: cb(202) = &H8743075: cb(203) = &H8B30558B: cb(204) = &HA89F04D: cb(205) = &H2287D83: cb(206) = &H44742D7C: cb(207) = &H5287D83: cb(208) = &H7D83467C: cb(209) = &H5C7C0B28: cb(210) = &H95840F: cb(211) = &H7D830000: cb(212) = &H8C0F0F28: cb(213) = &H9B&: cb(214) = &H11287D83: cb(215) = &HB48C0F: cb(216) = &HC9E90000: cb(217) = &H8B000000: cb(218) = &H4589FC45: cb(219) = &H2875391C: cb(220) = &HF0840F: cb(221) = &H3E80000: cb(222) = &HE9000003: cb(223) = &HE6&: cb(224) = &HE91C4589
'    cb(225) = &HDE&: cb(226) = &H165E8: cb(227) = &H1C458900: cb(228) = &H3287D83: cb(229) = &HCC840F: cb(230) = &H458B0000: cb(231) = &HE907892C: cb(232) = &HC2&: cb(233) = &H135E8: cb(234) = &H287D8300: cb(235) = &H8B0B7505: cb(236) = &H47892C45: cb(237) = &HACE904: cb(238) = &H7F8B0000: cb(239) = &H1C7D8904: cb(240) = &H840FF739: cb(241) = &H9E&: cb(242) = &H6287D83: cb(243) = &H94840F: cb(244) = &H4D8B0000: cb(245) = &H7E98328: cb(246) = &H898F048B: cb(247) = &H83E91C45: cb(248) = &HE8000000: cb(249) = &HF6&
'    cb(250) = &H8B047F8B: cb(251) = &H47892C45: cb(252) = &HE873EB04: cb(253) = &HE6&: cb(254) = &H89087F8B: cb(255) = &H7D831C7D: cb(256) = &H62740C28: cb(257) = &H5E74F739: cb(258) = &H83284D8B: cb(259) = &H48B0DE9: cb(260) = &H1C45898F: cb(261) = &HC3E850EB: cb(262) = &H8B000000: cb(263) = &H7D832C45: cb(264) = &H5741028: cb(265) = &HEB084789: cb(266) = &H87F8B3D: cb(267) = &H36EB0789: cb(268) = &HA9E8&: cb(269) = &H47F8B00: cb(270) = &H2A74F739: cb(271) = &H3908478B: cb(272) = &H892374F0: cb(273) = &H108B2445: cb(274) = &H20E8&
'    cb(275) = &H8B17EB00: cb(276) = &H45892445: cb(277) = &H83C031F8: cb(278) = &H7420287D: cb(279) = &HD2E84001: cb(280) = &H89000000: cb(281) = &HC4831C4D: cb(282) = &H10C26110: cb(283) = &H8DD68900: cb(284) = &HFF51244D: cb(285) = &H56FF2475: cb(286) = &H51C93134: cb(287) = &HFF515151: cb(288) = &H56FF2475: cb(289) = &H1C4D8D14: cb(290) = &H84F8B51: cb(291) = &H2C75FF51: cb(292) = &HFF2475FF: cb(293) = &H75FF0C56: cb(294) = &H856FF24: cb(295) = &H89C3F631: cb(296) = &H7589FC75: cb(297) = &HF07589F8: cb(298) = &H8BF47589: cb(299) = &HA8B1C53
'    cb(300) = &H48B2BE3: cb(301) = &H24453B8A: cb(302) = &HEB490374: cb(303) = &H83C889F3: cb(304) = &HC80101E0: cb(305) = &H4589E8D1: cb(306) = &H187B8BFC: cb(307) = &H3E0C148: cb(308) = &H407548B: cb(309) = &H8BF05589: cb(310) = &H45890704: cb(311) = &H4D8BC3F8: cb(312) = &HC88949FC: cb(313) = &HC103E0C1: cb(314) = &HC10102E1: cb(315) = &H1207B8B: cb(316) = &HE7E8C3CF: cb(317) = &H8BFFFFFF: cb(318) = &HF4458907: cb(319) = &HFFDCE8C3: cb(320) = &H458BFFFF: cb(321) = &HC30789F4: cb(322) = &H8BE87589: cb(323) = &HE083F445: cb(324) = &HE8CA7402
'    cb(325) = &HFFFFFFC6: cb(326) = &H8B047F8B: cb(327) = &HE8458907: cb(328) = &HF4458BC3: cb(329) = &H7404E083: cb(330) = &HFFB0E8B4: cb(331) = &H7F8BFFFF: cb(332) = &H4478B04: cb(333) = &H24538BC3: cb(334) = &HE0D10A8B: cb(335) = &H48BC129: cb(336) = &HF845398A: cb(337) = &HE9839774: cb(338) = &HC3F37F04: cb(339) = &HE83C458B: cb(340) = &H51&: cb(341) = &H8BCC4589: cb(342) = &H46E84445: cb(343) = &H89000000: cb(344) = &H458BC445: cb(345) = &H3BE848: cb(346) = &HC9310000: cb(347) = &H4D89C129: cb(348) = &HF8558BC0: cb(349) = &H51C84D8D
'    cb(350) = &HFF2475FF: cb(351) = &H458B1C52: cb(352) = &H40452BC8: cb(353) = &H1CE8&: cb(354) = &HC8458900: cb(355) = &H892C458B: cb(356) = &H458BDC45: cb(357) = &HD8458930: cb(358) = &H8934458B: cb(359) = &H458BD445: cb(360) = &HD0458938: cb(361) = &H9EC68C3: cb(362) = &H73FF0000: cb(363) = &H53FF5028: cb(364) = &H458BC350: cb(365) = &H34453BC4: cb(366) = &HC9310D74: cb(367) = &H4D3BC129: cb(368) = &H16850F34: cb(369) = &H8BFFFFFF: cb(370) = &H453BC045: cb(371) = &H310D7438: cb(372) = &H3BC129C9: cb(373) = &H850F384D: cb(374) = &HFFFFFF01
'    cb(375) = &H8DC3C031: cb(376) = &HFF51E44D: cb(377) = &H53FFBC75: cb(378) = &H74F03938: cb(379) = &H1C45C70C: cb(380) = &H80004005: cb(381) = &HFFFEE4E9: cb(382) = &HF44D8BFF: cb(383) = &H300E181: cb(384) = &HE9C10000: cb(385) = &H83037408: cb(386) = &HFF5104C1: cb(387) = &H53FFE475: cb(388) = &HE0753934: cb(389) = &HFF562474: cb(390) = &H75FF3875: cb(391) = &H3075FF34: cb(392) = &HFF2C75FF: cb(393) = &H53FFE475: cb(394) = &HDC75FF4C: cb(395) = &HFFD875FF: cb(396) = &H75FFD475: cb(397) = &H1DBE8D0: cb(398) = &HE2E80000: cb(399) = &H56FFFFFE
'    cb(400) = &H26A5056: cb(401) = &HFFC075FF: cb(402) = &H75FFC475: cb(403) = &HCC75FFC8: cb(404) = &HFFD075FF: cb(405) = &H75FFD475: cb(406) = &HDC75FFD8: cb(407) = &HFFE875FF: cb(408) = &H53FFE475: cb(409) = &H1C758930: cb(410) = &HFE07539: cb(411) = &HFFFE6C84: cb(412) = &HD0458FFF: cb(413) = &H8FD4458F: cb(414) = &H458FD845: cb(415) = &HBFFC3DC: cb(416) = &HFFFE6DE8: cb(417) = &H8B3789FF: cb(418) = &HFE830477: cb(419) = &H8B2E7400: cb(420) = &HF88306: cb(421) = &HFF500474: cb(422) = &H468B4053: cb(423) = &HF88304: cb(424) = &HFF500474
'    cb(425) = &H468B4853: cb(426) = &HF88308: cb(427) = &H88B0674: cb(428) = &H851FF50: cb(429) = &H2C53FF56: cb(430) = &H7789F631: cb(431) = &H8778B04: cb(432) = &H7400FE83: cb(433) = &H83068B14: cb(434) = &H47400F8: cb(435) = &H5453FF50: cb(436) = &H2C53FF56: cb(437) = &H7789F631: cb(438) = &HFC4D8B08: cb(439) = &H8B03E1C1: cb(440) = &H34891C7B: cb(441) = &HF74890F: cb(442) = &H187B8BFC: cb(443) = &HFC0F7489: cb(444) = &HF80F7489: cb(445) = &H3AE8C031: cb(446) = &HC1FFFFFE: cb(447) = &H448B02E1: cb(448) = &H8948F40A: cb(449) = &H39F40A44
'    cb(450) = &HCE850FF0: cb(451) = &H89FFFFFD: cb(452) = &H448B0A34: cb(453) = &H7489F80A: cb(454) = &HFF50F80A: cb(455) = &H33392C53: cb(456) = &HFDB7850F: cb(457) = &H73FFFFFF: cb(458) = &H2C53FF1C: cb(459) = &HFF1873FF: cb(460) = &H73FF2C53: cb(461) = &H2C53FF20: cb(462) = &HFF2473FF: cb(463) = &H8BC32C53: cb(464) = &H8025F445: cb(465) = &HF000000: cb(466) = &HFFFD9085: cb(467) = &HF44D81FF: cb(468) = &H80&: cb(469) = &HFFFDA4E8: cb(470) = &H87F8BFF: cb(471) = &H840FF739: cb(472) = &HA4&: cb(473) = &H8DE0758B: cb(474) = &HC751144D
'    cb(475) = &H1E045: cb(476) = &H4D8D0000: cb(477) = &H4D8D51E0: cb(478) = &H4D8B51BC: cb(479) = &H83F089E8: cb(480) = &H27502E0: cb(481) = &H8B51C931: cb(482) = &H4025F445: cb(483) = &H74000020: cb(484) = &HC04D8B18: cb(485) = &H200025: cb(486) = &H31027400: cb(487) = &H75FF51C9: cb(488) = &HC875FFC4: cb(489) = &HEBCC75FF: cb(490) = &H4875FF0C: cb(491) = &HFF4475FF: cb(492) = &H75FF4075: cb(493) = &HD04D8D3C: cb(494) = &HD44D8D51: cb(495) = &HD84D8D51: cb(496) = &HDC4D8D51: cb(497) = &H2875FF51: cb(498) = &HFF2475FF: cb(499) = &H83F28937
'    cb(500) = &HFF5201E2: cb(501) = &H57FF0477: cb(502) = &HE0458B08: cb(503) = &H31E07589: cb(504) = &H147539F6: cb(505) = &H4D8B2275: cb(506) = &H1E183E0: cb(507) = &H558B1AE3: cb(508) = &HBC753928: cb(509) = &H55890575: cb(510) = &H390DEBBC: cb(511) = &H874BC55: cb(512) = &H475F039: cb(513) = &H10E04D83: cb(514) = &H80F47581: cb(515) = &HE8000000: cb(516) = &HFFFFFCE9: cb(517) = &HF44D8BC3: cb(518) = &H80E181: cb(519) = &H850F0000: cb(520) = &HFFFFFCB9: cb(521) = &H80F44D81: cb(522) = &HE8000000: cb(523) = &HFFFFFCCD: cb(524) = &H39087F8B
'    cb(525) = &HFFD174F7: cb(526) = &H75FFE875: cb(527) = &HD04D8D24: cb(528) = &HD44D8D51: cb(529) = &HD84D8D51: cb(530) = &HDC4D8D51: cb(531) = &HE475FF51: cb(532) = &H77FF37FF: cb(533) = &HC57FF04: cb(534) = &HAEEB&

cb(22) = &HD231C031: cb(23) = &HBBE58960: cb(24) = &H12345678: cb(25) = &H3110EC83: cb(26) = &H431E8F6: cb(27) = &HC2890000: cb(28) = &H7401E183: cb(29) = &HE8C0310B: cb(30) = &H4B9&: cb(31) = &H8A048B49: cb(32) = &HFF2475FF: cb(33) = &H45890850: cb(34) = &H75F0391C: cb(35) = &H5F4E805: cb(36) = &HC4830000: cb(37) = &H4C26110: cb(38) = &H90909000: cb(39) = &HD231C031: cb(40) = &HBBE58960: cb(41) = &H12345678: cb(42) = &H3110EC83: cb(43) = &H287539F6: cb(44) = &HE8E83374: cb(45) = &HE8000003: cb(46) = &H436&: cb(47) = &HFFF8558B: cb(48) = &H75FF2875: cb(49) = &H4052FF24: cb(50) = &H8B1C4589: cb(51) = &HE181F44D: cb(52) = &H60000001: cb(53) = &H558B08E3: cb(54) = &H2C88328: cb(55) = &HC4830289: cb(56) = &H8C26110: cb(57) = &H1C45C700: cb(58) = &H80070057: cb(59) = &H9090F0EB: cb(60) = &HD231C031: cb(61) = &HBBE58960: cb(62) = &H12345678: cb(63) = &H3144EC83
cb(64) = &H447539F6: cb(65) = &H177840F: cb(66) = &H75390000: cb(67) = &H6E840F48: cb(68) = &H39000001: cb(69) = &H840F3475: cb(70) = &H165&: cb(71) = &HF387539: cb(72) = &H15C84: cb(73) = &HE0758900: cb(74) = &H372E8: cb(75) = &H41AE800: cb(76) = &HBBE80000: cb(77) = &H25000003: cb(78) = &H2000&: cb(79) = &H4E80774: cb(80) = &HEB000006: cb(81) = &HF8558B11: cb(82) = &H51EC4D8D: cb(83) = &HFF2475FF: cb(84) = &HF0390C52: cb(85) = &H75890874: cb(86) = &H11CE91C: cb(87) = &H458B0000: cb(88) = &HBC458928: cb(89) = &H89E87589: cb(90) = &H7589E475: cb(91) = &HF4458BE0: cb(92) = &H750EE083: cb(93) = &HF4458B1D: cb(94) = &H30025: cb(95) = &H8B377400: cb(96) = &H25F445: cb(97) = &H74000030: cb(98) = &H424E82D: cb(99) = &HF0390000: cb(100) = &H4D832474: cb(101) = &H6DE802E0: cb(102) = &H39000003: cb(103) = &H1675E875: cb(104) = &H51E84D8D: cb(105) = &HEC75FF56
cb(106) = &H893C53FF: cb(107) = &HF039EC75: cb(108) = &H75830474: cb(109) = &H4D8B02E0: cb(110) = &H1E183E0: cb(111) = &H458B4475: cb(112) = &H10E083F4: cb(113) = &H4D833C74: cb(114) = &H78E801E0: cb(115) = &H8B000005: cb(116) = &H25F445: cb(117) = &H74000030: cb(118) = &H14753929: cb(119) = &H75890574: cb(120) = &H8379EB1C: cb(121) = &H7403E07D: cb(122) = &HF44D8B19: cb(123) = &H300E181: cb(124) = &HE740000: cb(125) = &H3B9E8: cb(126) = &H74F03900: cb(127) = &HEC753905: cb(128) = &H4D8B9075: cb(129) = &H2E183E0: cb(130) = &HD0E807E3: cb(131) = &HEB000003: cb(132) = &HF8558B2A: cb(133) = &HFF4C75FF: cb(134) = &H75FF4875: cb(135) = &H4075FF44: cb(136) = &HFF3C75FF: cb(137) = &H75FFD075: cb(138) = &HD875FFD4: cb(139) = &HFFDC75FF: cb(140) = &H75FFBC75: cb(141) = &H2052FF24: cb(142) = &H391C4589: cb(143) = &H1C751C75: cb(144) = &H83F44D8B: cb(145) = &H14E320E1
cb(146) = &H10E07D83: cb(147) = &H39E8057C: cb(148) = &H83000003: cb(149) = &HE802E065: cb(150) = &H4EB&: cb(151) = &H74E47539: cb(152) = &HE475FF06: cb(153) = &H394453FF: cb(154) = &HE74E875: cb(155) = &H83F44D8B: cb(156) = &H67502E1: cb(157) = &HFFE875FF: cb(158) = &HC4834053: cb(159) = &H2CC26144: cb(160) = &H1C45C700: cb(161) = &H800A017C: cb(162) = &H9090F0EB: cb(163) = &HD231C031: cb(164) = &HBBE58960: cb(165) = &H12345678: cb(166) = &H3110EC83: cb(167) = &H287D81F6: cb(168) = &H80&: cb(169) = &H458B597C: cb(170) = &H81388B24: cb(171) = &H82287D: cb(172) = &H22740000: cb(173) = &H812475FF: cb(174) = &H81287D: cb(175) = &HB740000: cb(176) = &H890457FF: cb(177) = &H9BE91C45: cb(178) = &HFF000001: cb(179) = &H45890857: cb(180) = &H190E91C: cb(181) = &H458B0000: cb(182) = &H74F03930: cb(183) = &H3075FF0D: cb(184) = &H5656016A: cb(185) = &HFF2475FF: cb(186) = &H458B1457
cb(187) = &HFF56562C: cb(188) = &H30FF0470: cb(189) = &HFF2475FF: cb(190) = &H67E91457: cb(191) = &H89000001: cb(192) = &H33391C75: cb(193) = &H15C840F: cb(194) = &H7D830000: cb(195) = &H8F0F1F28: cb(196) = &H13B&: cb(197) = &H186E8: cb(198) = &HFC753900: cb(199) = &H7539097F: cb(200) = &H3F850F28: cb(201) = &H39000001: cb(202) = &H8743075: cb(203) = &H8B30558B: cb(204) = &HA89F04D: cb(205) = &H2287D83: cb(206) = &H44742D7C: cb(207) = &H5287D83: cb(208) = &H7D83467C: cb(209) = &H5C7C0B28: cb(210) = &H95840F: cb(211) = &H7D830000: cb(212) = &H8C0F0F28: cb(213) = &H9B&: cb(214) = &H11287D83: cb(215) = &HB48C0F: cb(216) = &HC9E90000: cb(217) = &H8B000000: cb(218) = &H4589FC45: cb(219) = &H2875391C: cb(220) = &HF0840F: cb(221) = &HBE80000: cb(222) = &HE9000003: cb(223) = &HE6&: cb(224) = &HE91C4589: cb(225) = &HDE&: cb(226) = &H165E8: cb(227) = &H1C458900: cb(228) = &H3287D83
cb(229) = &HCC840F: cb(230) = &H458B0000: cb(231) = &HE907892C: cb(232) = &HC2&: cb(233) = &H135E8: cb(234) = &H287D8300: cb(235) = &H8B0B7505: cb(236) = &H47892C45: cb(237) = &HACE904: cb(238) = &H7F8B0000: cb(239) = &H1C7D8904: cb(240) = &H840FF739: cb(241) = &H9E&: cb(242) = &H6287D83: cb(243) = &H94840F: cb(244) = &H4D8B0000: cb(245) = &H7E98328: cb(246) = &H898F048B: cb(247) = &H83E91C45: cb(248) = &HE8000000: cb(249) = &HF6&: cb(250) = &H8B047F8B: cb(251) = &H47892C45: cb(252) = &HE873EB04: cb(253) = &HE6&: cb(254) = &H89087F8B: cb(255) = &H7D831C7D: cb(256) = &H62740C28: cb(257) = &H5E74F739: cb(258) = &H83284D8B: cb(259) = &H48B0DE9: cb(260) = &H1C45898F: cb(261) = &HC3E850EB: cb(262) = &H8B000000: cb(263) = &H7D832C45: cb(264) = &H5741028: cb(265) = &HEB084789: cb(266) = &H87F8B3D: cb(267) = &H36EB0789: cb(268) = &HA9E8&: cb(269) = &H47F8B00: cb(270) = &H2A74F739
cb(271) = &H3908478B: cb(272) = &H892374F0: cb(273) = &H108B2445: cb(274) = &H20E8&: cb(275) = &H8B17EB00: cb(276) = &H45892445: cb(277) = &H83C031F8: cb(278) = &H7420287D: cb(279) = &HD2E84001: cb(280) = &H89000000: cb(281) = &HC4831C4D: cb(282) = &H10C26110: cb(283) = &H8DD68900: cb(284) = &HFF51244D: cb(285) = &H56FF2475: cb(286) = &H51C93134: cb(287) = &HFF515151: cb(288) = &H56FF2475: cb(289) = &H1C4D8D14: cb(290) = &H84F8B51: cb(291) = &H2C75FF51: cb(292) = &HFF2475FF: cb(293) = &H75FF0C56: cb(294) = &H856FF24: cb(295) = &H89C3F631: cb(296) = &H7589FC75: cb(297) = &HF07589F8: cb(298) = &H8BF47589: cb(299) = &HA8B1C53: cb(300) = &H48B2BE3: cb(301) = &H24453B8A: cb(302) = &HEB490374: cb(303) = &H83C889F3: cb(304) = &HC80101E0: cb(305) = &H4589E8D1: cb(306) = &H187B8BFC: cb(307) = &H3E0C148: cb(308) = &H407548B: cb(309) = &H8BF05589: cb(310) = &H45890704
cb(311) = &H4D8BC3F8: cb(312) = &HC88949FC: cb(313) = &HC103E0C1: cb(314) = &HC10102E1: cb(315) = &H1207B8B: cb(316) = &HE7E8C3CF: cb(317) = &H8BFFFFFF: cb(318) = &HF4458907: cb(319) = &HFFDCE8C3: cb(320) = &H458BFFFF: cb(321) = &HC30789F4: cb(322) = &H8BE87589: cb(323) = &HE083F445: cb(324) = &HE8CA7402: cb(325) = &HFFFFFFC6: cb(326) = &H8B047F8B: cb(327) = &HE8458907: cb(328) = &HF4458BC3: cb(329) = &H7404E083: cb(330) = &HFFB0E8B4: cb(331) = &H7F8BFFFF: cb(332) = &H4478B04: cb(333) = &H24538BC3: cb(334) = &HE0D10A8B: cb(335) = &H48BC129: cb(336) = &HF845398A: cb(337) = &HE9839774: cb(338) = &HC3F37F04: cb(339) = &HE83C458B: cb(340) = &H51&: cb(341) = &H8BCC4589: cb(342) = &H46E84445: cb(343) = &H89000000: cb(344) = &H458BC445: cb(345) = &H3BE848: cb(346) = &HC9310000: cb(347) = &H4D89C129: cb(348) = &HF8558BC0: cb(349) = &H51C84D8D: cb(350) = &HFF2475FF
cb(351) = &H458B1C52: cb(352) = &H40452BC8: cb(353) = &H1CE8&: cb(354) = &HC8458900: cb(355) = &H892C458B: cb(356) = &H458BDC45: cb(357) = &HD8458930: cb(358) = &H8934458B: cb(359) = &H458BD445: cb(360) = &HD0458938: cb(361) = &H9EC68C3: cb(362) = &H73FF0000: cb(363) = &H53FF5028: cb(364) = &H458BC350: cb(365) = &H34453BC4: cb(366) = &HC9310D74: cb(367) = &H4D3BC129: cb(368) = &H16850F34: cb(369) = &H8BFFFFFF: cb(370) = &H453BC045: cb(371) = &H310D7438: cb(372) = &H3BC129C9: cb(373) = &H850F384D: cb(374) = &HFFFFFF01: cb(375) = &H8DC3C031: cb(376) = &HFF51E44D: cb(377) = &H53FFBC75: cb(378) = &H74F03938: cb(379) = &H1C45C70C: cb(380) = &H80004005: cb(381) = &HFFFEE4E9: cb(382) = &HF44D8BFF: cb(383) = &H300E181: cb(384) = &HE9C10000: cb(385) = &H83037408: cb(386) = &HFF5104C1: cb(387) = &H53FFE475: cb(388) = &HE0753934: cb(389) = &H4D8B2C74: cb(390) = &HBC4D3928
cb(391) = &HFF561375: cb(392) = &H75FF3875: cb(393) = &H3075FF34: cb(394) = &HFF2C75FF: cb(395) = &H53FFE475: cb(396) = &HDC75FF4C: cb(397) = &HFFD875FF: cb(398) = &H75FFD475: cb(399) = &H1DBE8D0: cb(400) = &HDAE80000: cb(401) = &H56FFFFFE: cb(402) = &H26A5056: cb(403) = &HFFC075FF: cb(404) = &H75FFC475: cb(405) = &HCC75FFC8: cb(406) = &HFFD075FF: cb(407) = &H75FFD475: cb(408) = &HDC75FFD8: cb(409) = &HFFE875FF: cb(410) = &H53FFE475: cb(411) = &H1C758930: cb(412) = &HFE07539: cb(413) = &HFFFE6484: cb(414) = &HD0458FFF: cb(415) = &H8FD4458F: cb(416) = &H458FD845: cb(417) = &HBFFC3DC: cb(418) = &HFFFE65E8: cb(419) = &H8B3789FF: cb(420) = &HFE830477: cb(421) = &H8B2E7400: cb(422) = &HF88306: cb(423) = &HFF500474: cb(424) = &H468B4053: cb(425) = &HF88304: cb(426) = &HFF500474: cb(427) = &H468B4853: cb(428) = &HF88308: cb(429) = &H88B0674: cb(430) = &H851FF50
cb(431) = &H2C53FF56: cb(432) = &H7789F631: cb(433) = &H8778B04: cb(434) = &H7400FE83: cb(435) = &H83068B14: cb(436) = &H47400F8: cb(437) = &H5453FF50: cb(438) = &H2C53FF56: cb(439) = &H7789F631: cb(440) = &HFC4D8B08: cb(441) = &H8B03E1C1: cb(442) = &H34891C7B: cb(443) = &HF74890F: cb(444) = &H187B8BFC: cb(445) = &HFC0F7489: cb(446) = &HF80F7489: cb(447) = &H32E8C031: cb(448) = &HC1FFFFFE: cb(449) = &H448B02E1: cb(450) = &H8948F40A: cb(451) = &H39F40A44: cb(452) = &HC6850FF0: cb(453) = &H89FFFFFD: cb(454) = &H448B0A34: cb(455) = &H7489F80A: cb(456) = &HFF50F80A: cb(457) = &H33392C53: cb(458) = &HFDAF850F: cb(459) = &H73FFFFFF: cb(460) = &H2C53FF1C: cb(461) = &HFF1873FF: cb(462) = &H73FF2C53: cb(463) = &H2C53FF20: cb(464) = &HFF2473FF: cb(465) = &H8BC32C53: cb(466) = &H8025F445: cb(467) = &HF000000: cb(468) = &HFFFD8885: cb(469) = &HF44D81FF: cb(470) = &H80&
cb(471) = &HFFFD9CE8: cb(472) = &H87F8BFF: cb(473) = &H840FF739: cb(474) = &HA4&: cb(475) = &H8DE0758B: cb(476) = &HC751144D: cb(477) = &H1E045: cb(478) = &H4D8D0000: cb(479) = &H4D8D51E0: cb(480) = &H4D8B51BC: cb(481) = &H83F089E8: cb(482) = &H27502E0: cb(483) = &H8B51C931: cb(484) = &H4025F445: cb(485) = &H74000020: cb(486) = &HC04D8B18: cb(487) = &H200025: cb(488) = &H31027400: cb(489) = &H75FF51C9: cb(490) = &HC875FFC4: cb(491) = &HEBCC75FF: cb(492) = &H4875FF0C: cb(493) = &HFF4475FF: cb(494) = &H75FF4075: cb(495) = &HD04D8D3C: cb(496) = &HD44D8D51: cb(497) = &HD84D8D51: cb(498) = &HDC4D8D51: cb(499) = &H2875FF51: cb(500) = &HFF2475FF: cb(501) = &H83F28937: cb(502) = &HFF5201E2: cb(503) = &H57FF0477: cb(504) = &HE0458B08: cb(505) = &H31E07589: cb(506) = &H147539F6: cb(507) = &H4D8B2275: cb(508) = &H1E183E0: cb(509) = &H558B1AE3: cb(510) = &HBC753928
cb(511) = &H55890575: cb(512) = &H390DEBBC: cb(513) = &H874BC55: cb(514) = &H474F039: cb(515) = &H10E04D83: cb(516) = &H80F47581: cb(517) = &HE8000000: cb(518) = &HFFFFFCE1: cb(519) = &HF44D8BC3: cb(520) = &H80E181: cb(521) = &H850F0000: cb(522) = &HFFFFFCB1: cb(523) = &H80F44D81: cb(524) = &HE8000000: cb(525) = &HFFFFFCC5: cb(526) = &H39087F8B: cb(527) = &HFFD174F7: cb(528) = &H75FFE875: cb(529) = &HD04D8D24: cb(530) = &HD44D8D51: cb(531) = &HD84D8D51: cb(532) = &HDC4D8D51: cb(533) = &HE475FF51: cb(534) = &H77FF37FF: cb(535) = &HC57FF04: cb(536) = &HAEEB&


    ' patch thunk before posting to memory
    cb(OFFSET_IUnknownRelease) = p_ThunkAddr
    cb(OFFSET_IPictureGetAttrs) = p_ThunkAddr
    cb(OFFSET_IPictureRender) = p_ThunkAddr
    cb(OFFSET_ThunkCustom) = p_ThunkAddr
    
    'cb(0)         thunk client count, initialized at zero & changed as needed by class & thunk
    cb(1) = THUNK_VERSION
    cb(2) = &H58    ' offset in thunk for 1st function (IUnknown::Release)
    cb(3) = &H9C    ' offset in thunk for 2nd function (IPicture::get_Attributes)
    cb(4) = &HF0    ' offset in thunk for 3rd function (IPicture::Render)
    cb(5) = &H28C   ' offset in thunk for 4th function (CallThunk function)
    ' coder notes: array positions (2-4) are also constants in zzCreateRedirection
    '              array position (5) is also a constant in zzSafeThunkAddress
    '              if values ever change here, change them in those 2 routines also
    'cb(6-9)       array pointers filled dynamically with call to zzInitializeArrays as needed
    cb(10) = zzRealDPI ' need real DPI for proper himertric > pixel conversion usage with GDI+
    ' patch thunk with its needed API functions
    cb(11) = GetProcAddress(GetModuleHandleA("ole32.dll"), "CoTaskMemFree") ' self-cleaning release of memory
    lValue = GetModuleHandleA("GdiPlus.dll")
    cb(12) = GetProcAddress(lValue, "GdipDrawImageRectRectI")       ' rendering with attributes/better quality
    cb(13) = GetProcAddress(lValue, "GdipSetInterpolationMode")     ' setting scale quality
    cb(14) = GetProcAddress(lValue, "GdipCreateFromHDC")            ' GDI+ hGraphics creation
    cb(15) = GetProcAddress(lValue, "GdipCreateBitmapFromHBITMAP")  ' create GDI+ bitmap on demand
    cb(16) = GetProcAddress(lValue, "GdipDisposeImage")             ' GDI+ bitmap destruction
    cb(17) = GetProcAddress(lValue, "GdipDeleteGraphics")           ' GDI+ hGraphics deletion
    cb(18) = GetProcAddress(lValue, "GdipDisposeImageAttributes")   ' GDI+ image attributes destruction
    cb(19) = GetProcAddress(lValue, "GdipSetClipRectI")             ' GDI+ clipping function
    If GetProcAddress(lValue, "GdipDrawImageFX") = 0& Then m_GDIpVersion = 1! Else m_GDIpVersion = 1.1!
    cb(20) = GetProcAddress(GetModuleHandleA("kernel32.dll"), "MulDiv")         ' used for converstion himetric to pixels
    cb(21) = GetProcAddress(GetModuleHandleA("oleaut32.dll"), "SysFreeString")  ' used to free user-supplied callback keys
    ' sanity check follows
    For n = 11& To 21&
        If cb(n) = 0& Then Exit For
    Next
    If n < 21& Then                                         ' failure to load above functions
        VirtualFree p_ThunkAddr, 0&, CB_MEM_RELEASE
        m_GDIpVersion = 0!: p_ThunkAddr = 0&
    Else
        CopyMemory ByVal p_ThunkAddr, cb(0), FUNK_LEN * 4&  ' copy thunk to memory
        ' update the listener window with thunk address
        SendMessage m_hWndListener, msgListener_setThunk, p_ThunkAddr, ByVal 0&
        zzCreateThunk = True
    End If
End Function

Private Function zzInitializeArrays() As Boolean

    ' note: thunk is self-cleaning. When no more clients are being served by the thunk,
    '   it will release all memory, except itself. Therefore, whenever the client count
    '   is queried and it is zero, we need to initialize startup arrays.
    
    ' The thunk uses 4 collections. Each are freed automatically when no longer needed.
    
    ' 1. arrObjs() is a collection containing pairs of entries.
    '       The first entry in the collection is a counter (number of contained items) but it
    '          doesn't include its own entry in count. Following the counter are the records
    '       1st item in pair: ObjPtr(subclassed stdPicture)
    '       2nd item in pair: ObjPtr(subclassd IPicture)
    ' 2. arrObjVtbls() is a collection containing pairs of entries
    '       1st item in pair: original VTable of managed IPicture object
    '       2nd item in pair: this class' RECORD_VERSION constant
    '       the record position in the collection is relative to arrObjs
    ' 3. arrObjOptions() is a collection containing records each having 3 items
    '       the record position in the collection is relative to arrObjs
    '       1st item in record: the Flags/Options value
    '       2nd item in recrod: pointer to a record of GDI+ releated items, as needed
    '       3rd item in record: pointer to a record of callbacks information, as needed
    ' 4. arrRedirects() is collection containing records each having 4 entries
    '       The first entry in the collection is a counter (number of contained items) but it
    '          doesn't include its own entry in count. Following the counter are the records
    '       each record describes a VTable redirection
    '       1st item in record: count of managed clients using this redirection
    '       2nd item in record: memory address of the redirection table
    '       3rd item in record: original StdPicture VTable
    '       4th item in record: original IPicture VTable cross-reference; same as found in arrObjVtbls()

    Dim lPtr(0 To 3) As Long, n As Long
                                                ' 1st 3 arrays are initialized for 3 records
    lPtr(0) = CoTaskMemAlloc(24&)               ' arrObjVtbls() (2 array entries per picture)
    If lPtr(0) Then
        FillMemory ByVal lPtr(0), 24&, 0&
        lPtr(1) = CoTaskMemAlloc(28&)           ' arrObjs() (2 array entries per picture) + 1 count entry
        If lPtr(1) Then
            FillMemory ByVal lPtr(1), 28&, 0&
            CopyMemory ByVal lPtr(1), 6&, 4&    ' update counter
            lPtr(2) = CoTaskMemAlloc(36&)       ' arrObjOptions() (3 array entries per picture)
            If lPtr(2) Then
                FillMemory ByVal lPtr(2), 36&, 0&
                lPtr(3) = CoTaskMemAlloc(36&)   ' arrRedirects() (4 entries per redirected vTable) + 1 count entry
                If lPtr(3) Then
                    FillMemory ByVal lPtr(3), 36&, 0& ' initialized to hold 2 records; shouldn't need be more than that
                    CopyMemory ByVal lPtr(3), 8&, 4& ' update counter
                End If
            End If
        End If
    End If
    
    If lPtr(3) Then                             ' update thunk with array pointers
        For n = 0& To 3&
            CopyMemory ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrObjVtbls + n * 4&), lPtr(n), 4&
        Next
        zzInitializeArrays = True
    Else
        For n = 0& To 2&                        ' reallocation failed; clean up those that didn't
            If lPtr(n) Then CoTaskMemFree lPtr(n)
        Next
    End If
        
End Function

Private Function zzCreateRedirection(nIPicTbl As Long, nStdPicTbl As Long, nIPicVTblOffset As Long) As Long

    ' creates/returns a redirection table containing 25 function addresses
    ' of those, we will only be redirecting 4 of them
    ' this table is freed automatically within the thunk when no longer needed
    
    Dim nSlot As Long, n As Long, lSize As Long
    Dim lRedirect As Long, lPtr As Long
    Dim arrData() As Long, arrSafeArray() As Long
    
    ' note: any changes to these constants must also be made in zzUpgradeThunk
    Const TABLE_SIZE As Long = 100              ' minimal size of a redirection table in bytes
    Const OFFSET_IUnkRelease As Long = 2        ' offset (Longs) for stdPic/IPicture IUnknown:Release
    Const OFFSET_Render As Long = 8             ' offset (Longs) for IPicture:Render
    Const OFFSET_GetAttrs As Long = 16          ' offset (Longs) for IPicture:get_Attributes
    Const DIFF_VTABLELOCS As Long = 7           ' number of Longs between VTable locations
    Const OFFSET_THUNKFPTR As Long = 8          ' thunk offset for its 1st function (IUnknown:Release)
    
    ' collection of redirected VTables
    ' - this collection should typically be no more than 2 records
    ' - each record consists of 4 entries:
    '       entry 1: count of redirected objects using this redirection table
    '       entry 2: memory address of redirection table (freed at some point)
    '       entry 3: redirected object's original StdPicture vTable address
    '       entry 4: redirected object's original IPicture vTable address
    
    CopyMemory n, ByVal p_ThunkAddr, 4&         ' get client count
    If n = 0& Then                              ' initialize arrays when count = 0
        If m_Debug Then Debug.Print "initializing arrays, no clients"
        If zzInitializeArrays() = False Then Exit Function
    End If
    CopyMemory ByVal p_ThunkAddr, n + 1&, 4&     ' update client count
    
    CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrRedirects), 4&
    CopyMemory lSize, ByVal lPtr, 4&            ' get size of redirection collection
    nIPicVTblOffset = DIFF_VTABLELOCS * 4&      ' location in redirect table where this VTable begins
    
    nSlot = CallThunk(f_MsgAddr, nIPicTbl, msgRedirectVTblIdx) ' ask for array location of redirection table for passed VTable
    If nSlot > 0& Then                              ' already redirected; nSlot will be multiple of 4
        zzOverlayArray VarPtrArray(arrData), lPtr, arrSafeArray(), lSize + 1&, False
        arrData(nSlot - 3&) = arrData(nSlot - 3&) + 1& ' increment client count
        lRedirect = arrData(nSlot - 2&)             ' get table pointer, remove overlay, done
        zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, False
        GoTo ExitRoutine
    End If
    
    ' redirection table not found, create a new one
    If m_Debug Then Debug.Print "new redirection table being created for vTable "; nIPicTbl
    
    lRedirect = CoTaskMemAlloc(TABLE_SIZE)
    If lRedirect = 0& Then GoTo ExitRoutine     ' can't create a redirection table
    
    nSlot = CallThunk(f_MsgAddr, 0&, msgRedirectVTblIdx) ' ask for next empty slot; nSlot will be multiple of 4
    If nSlot < 1& Then                              ' table is filled
        lSize = lSize + 4&                          ' new item count of redirection collection
        n = CoTaskMemRealloc(lPtr, lSize * 4& + 4&)
        If n = 0& Then                              ' failed to reallocate
            CoTaskMemFree lRedirect                 ' free redirection table just created above
            lRedirect = 0&
            GoTo ExitRoutine                        ' couldn't resize another 12 bytes?
        End If
        If Not lPtr = n Then
            lPtr = n                                ' update thunk with new collection pointer
            CopyMemory ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrRedirects), lPtr, 4&
        End If                                      ' add overlay and set values
        nSlot = lSize
        zzOverlayArray VarPtrArray(arrData), lPtr, arrSafeArray(), lSize + 1&, False
        arrData(0) = lSize                          ' update element count & ensure new entries zeroized
    Else
        zzOverlayArray VarPtrArray(arrData), lPtr, arrSafeArray(), lSize + 1&, False
    End If
    
    arrData(nSlot) = nIPicTbl                        ' set VTable cross-reference
    arrData(nSlot - 1) = nStdPicTbl
    arrData(nSlot - 2) = lRedirect                  ' set redirection table pointer (freed at some point)
    arrData(nSlot - 3) = 1                          ' set VTable client count & remove overlay
    zzOverlayArray VarPtrArray(arrData()), 0&, arrSafeArray(), 0&, False
    
    ' overlay redirection table and set its subclassed function pointers
    zzOverlayArray VarPtrArray(arrData), lRedirect, arrSafeArray(), TABLE_SIZE \ 4&, False
    
    ' copy original VTable function pointers
    CopyMemory arrData(0), ByVal nStdPicTbl, nIPicVTblOffset
    CopyMemory arrData(DIFF_VTABLELOCS), ByVal nIPicTbl, TABLE_SIZE - nIPicVTblOffset

    ' set redirection to thunk for selected functions
    CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_THUNKFPTR), 4&    ' thunk offset for IUnknown:Release
    arrData(OFFSET_IUnkRelease) = zzSafeOffset32(p_ThunkAddr, lPtr)
    arrData(DIFF_VTABLELOCS + OFFSET_IUnkRelease) = arrData(OFFSET_IUnkRelease)

    CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_THUNKFPTR + 4&), 4&  ' thunk offset for IPicture:get_Attributes
    arrData(DIFF_VTABLELOCS + OFFSET_GetAttrs) = zzSafeOffset32(p_ThunkAddr, lPtr)

    CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_THUNKFPTR + 8&), 4& ' thunk offset for IPicture:Render
    arrData(DIFF_VTABLELOCS + OFFSET_Render) = zzSafeOffset32(p_ThunkAddr, lPtr)
    
    zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, False
    
ExitRoutine:
    If lRedirect = 0& Then                              ' failure
        CopyMemory n, ByVal p_ThunkAddr, 4&             ' decrement thunk client count
        CopyMemory ByVal p_ThunkAddr, n - 1&, 4&
    Else
        zzCreateRedirection = lRedirect                 ' move to the stdPicture vTable
    End If
End Function

Private Sub zzOverlayArray(arrPtr As Long, dataPtr As Long, arrSafeArray() As Long, arrElements As Long, areBytes As Boolean)

    ' the overlaying of arrays on pointers has two purposes (both for convenience)
    ' 1. Prevents any chance of pointer math overflow
    ' 2. Prevents extra CopyMemory calls to read/write multiple items

    ' arrPtr: VarPtrArray(someArray)
    ' dataPtr: memory address where array data begins
    '   if zero, then arrPtr is released
    ' arrSafeArray(): any dynamic array; will be resized here
    ' arrElements: number of elements to include with overlay; ignored if dataPtr = 0
    ' arrBytes; ignored if dataPtr = 0
    '   if arrBytes is True, then arrPtr is for a byte array
    '   if arrBytes is False, then arrPtr is for a long array
    ' Array LBound will always be zero
    
    Dim n As Long
    
    If dataPtr = 0& Then
        CopyMemory ByVal arrPtr, 0&, 4&
    Else
        If areBytes Then n = 1 Else n = 4
        ReDim arrSafeArray(0 To 5)
        arrSafeArray(0) = 1                ' dimensions
        arrSafeArray(1) = n                ' bytes per array element
        arrSafeArray(2) = 0                ' locks
        arrSafeArray(3) = dataPtr          ' address to 1st array element data
        arrSafeArray(4) = arrElements      ' number elements in array
        arrSafeArray(5) = 0                ' LBound of array
        CopyMemory ByVal arrPtr, VarPtr(arrSafeArray(0)), 4&
    End If
    
End Sub

Private Function zzSafeOffset32(ByVal VBpointer As Long, ByVal AdjAmount As Double) As Long
    ' helper function to ensure adding/subtracting from 32bit pointer wraps around
    ' the high bit as needed. Since class can be used in 64 bit O/S with /LARGEADDRESSAWARE
    ' option during compilation; helps ensure pointer math across 2GB boundary.
    
    Const UINT_MaxPlus1 As Double = 4294967296#
    Const INT_MaxPlus1 As Double = 2147483648#
    Const SIGN_BIT As Long = &H80000000
    
    Dim dPointer As Double
    If Abs(AdjAmount) >= UINT_MaxPlus1 Then Err.Raise 6
    
    If VBpointer > -1& Then
        dPointer = VBpointer + AdjAmount
    Else
        dPointer = VBpointer + AdjAmount + UINT_MaxPlus1
    End If
    If dPointer < INT_MaxPlus1 Then
        If dPointer < 0# Then Err.Raise 6
        zzSafeOffset32 = dPointer
    Else
        zzSafeOffset32 = (dPointer - INT_MaxPlus1) Or SIGN_BIT
    End If

End Function

Private Function zzRealDPI(Optional ScreenDepth As Variant) As Long

    ' need real DPI for proper conversion of himetric to pixels within the thunk
    ' DPI can be calculated as: 1440 / screen.TwipsPerPixelX
    ' At 168 DPI (175%), the above formula fails to calculate the DPI correctly. This is because VB
    '   is fudging the TwipsPerPixel. At 168 DPI, TwipsPerPixel should be 8.57 but VB says: 8
    ' The himetric value returned by stdPicture.Width/Height, for example, when converted to
    '   pixels with VB's ScaleX/Y functions are incorrect. Having the real DPI, we can overcome
    '   this problem: pixels = himetric / 2540 * RealDPI.
    ' Why is this needed? Well, when rendering with GDI+, we provide it with the size of our
    ' picture within its API parameters. Best results when values are accurate.

    Dim dDC As Long
    Const LOGPIXELSX As Long = 88
    Const BITSPIXEL As Long = 12
    dDC = GetDC(0)
    zzRealDPI = GetDeviceCaps(dDC, LOGPIXELSX)
    If IsMissing(ScreenDepth) = False Then ScreenDepth = GetDeviceCaps(dDC, BITSPIXEL)
    ReleaseDC 0, dDC

End Function

Private Function zzHandleToStdPicture(hImage As Long, imgType As PictureTypeConstants) As IPicture

    ' function creates a stdPicture object from an image handle (bitmap or icon used in this class)
    
    'Private Type PictDesc
    '    Size As Long
    '    Type As Long
    '    hHandle As Long
    '    lParam As Long       for bitmaps only: Palette handle
    '                         for WMF only: extentX (integer) & extentY (integer)
    '                         for EMF/ICON: not used
    'End Type
    
    Dim lpPictDesc(0 To 3) As Long, aGUID(0 To 3) As Long
    
    lpPictDesc(0) = 16&
    lpPictDesc(1) = imgType
    lpPictDesc(2) = hImage
    aGUID(0) = &H7BF80980   ' Picture GUID {7BF80981-BF32-101A-8BBB-00AA00300CAB}
    aGUID(1) = &H101ABF32
    aGUID(2) = &HAA00BB8B
    aGUID(3) = &HAB0C3000
    Call OleCreatePictureIndirect(lpPictDesc(0), aGUID(0), 1&, zzHandleToStdPicture)
    
End Function

Private Function zzIStreamToPicture(theStream As Long, bKeepFormat As Boolean, lSize As Long) As IPicture
    
    ' function creates a stdPicture from the passed array
    ' Note: The array was already validated as not empty before this was called
    
    Dim aGUID(0 To 3) As Long
    aGUID(0) = &H7BF80980    ' Picture GUID {7BF80981-BF32-101A-8BBB-00AA00300CAB}
    aGUID(1) = &H101ABF32
    aGUID(2) = &HAA00BB8B
    aGUID(3) = &HAB0C3000
    Call OleLoadPicture(theStream, lSize, Abs(Not bKeepFormat), aGUID(0), zzIStreamToPicture)

End Function

Private Function zzGetEncoderClsID(strMimeType As String, ClassID() As Long) As Long
  
 ' Routine is a helper function save GDI+ image to stream/file
 
  Dim lCount As Long, lSize As Long
  Dim lIdx As Long, lPtr As Long, sMime As String
  Dim arrData() As Byte                 ' faux ImageCodecInfo structure(s)
  Const CodecInfoSize As Long = 76&     ' size of a GDI+ ImageCodecInfo structure
  Const OFFSET_MIME As Long = 48&       ' offset into that structure where the MIME member exists
    
    '-- Get the encoder count & array size, then retrieve them
    Call GdipGetImageEncodersSize(lCount, lSize)
    If (lSize = 0& Or lCount = 0&) Then Exit Function ' Failed!
    ReDim arrData(0 To lSize - 1&)
    Call GdipGetImageEncoders(lCount, lSize, arrData(0))
    
    ' cache size of string looking for & a dummy string
    lSize = Len(strMimeType): sMime = String$(lSize, vbNullChar)
    
    For lIdx = lCount - 1& To 0& Step -1&
        '-- compare MIME member of ImageCodecInfo structure to passed criteria
        CopyMemory lPtr, arrData(lIdx * CodecInfoSize + OFFSET_MIME), 4&
        If lSize = lstrlenW(lPtr) Then
            Call CopyMemory(ByVal StrPtr(sMime), ByVal lPtr, lSize * 2&)
            If StrComp(sMime, strMimeType, vbTextCompare) = 0 Then
                CopyMemory ClassID(0), arrData(lIdx * CodecInfoSize), 16&
                Exit For                ' found & done
            End If
        End If
    Next lIdx
    zzGetEncoderClsID = lIdx
    
End Function

Private Function zzGetImageData(thePicture As StdPicture, bAsArray As Boolean, bOK As Boolean) As Variant
    
    ' helper function to return an array or stream of picture's format data
    ' If thunk caches original format, data retrieved from there else from VB's IPicture.SaveFile method
    
    Dim lSize As Long, lObjPtr As Long, lMode As Long
    Dim hGlobal As Long, arrData() As Byte
    Dim IStream As stdole.IUnknown, iPic As IPicture
    
    bOK = False
    If thePicture Is Nothing Then Exit Function
    If thePicture.Handle = 0& Then Exit Function
    
    If Me.HasOriginalFormat(thePicture) Then    ' thunk or VB has original data cached
        lObjPtr = ObjPtr(thePicture)
        lSize = CallThunk(f_MsgAddr, lObjPtr, msgObjGetStrmSize)
        If lSize > 0& Then                      ' thunk has the data
            If bAsArray Then
                ReDim arrData(0 To lSize - 1&)
                CallThunk f_MsgAddr, lObjPtr, msgStreamRead, VarPtr(arrData(0))
                bOK = True
            Else                                ' read thunk's data into hGlobal
                hGlobal = GlobalAlloc(&H2&, lSize)
                If hGlobal = 0& Then Exit Function
                lMode = GlobalLock(hGlobal)
                If lMode = 0& Then
                    GlobalFree hGlobal
                Else                            ' create stream from hGlobal
                    CallThunk f_MsgAddr, lObjPtr, msgStreamRead, lMode
                    GlobalUnlock hGlobal
                    CreateStreamOnHGlobal hGlobal, 1&, IStream
                    If IStream Is Nothing Then
                        GlobalFree hGlobal
                    Else
                        bOK = True
                    End If
                End If
                hGlobal = 0&                    ' done. Flag prevents next block of code
            End If
        Else                                    ' VB has the data
            hGlobal = GlobalAlloc(&H2&, 0&)
        End If
    Else                                        ' get whatever VB gives to us
        hGlobal = GlobalAlloc(&H2&, 0&): lMode = 1&
    End If
    If hGlobal Then             ' retrieve from VB
        CreateStreamOnHGlobal hGlobal, 1&, IStream
        If IStream Is Nothing Then
            GlobalFree hGlobal
        Else
            Set iPic = thePicture
            If lMode Then
                iPic.SaveAsFile ByVal ObjPtr(IStream), 1&, lSize
            Else
                iPic.SaveAsFile ByVal ObjPtr(IStream), 0&, lSize
            End If
            Set iPic = Nothing
            If lSize > 0& Then
                If bAsArray Then    ' transfer stream to byte array
                    lMode = GlobalLock(hGlobal)
                    If lMode Then
                        ReDim arrData(0 To lSize - 1&)
                        CopyMemory arrData(0), ByVal lMode, lSize
                        GlobalUnlock hGlobal
                        bOK = True
                    End If
                Else
                    bOK = True
                End If
            End If
        End If
    End If
    If bOK Then
        If bAsArray Then zzGetImageData = arrData() Else Set zzGetImageData = IStream
    End If
    
End Function

Private Function zzLocateThunk() As Long

    ' locates/creates child window on top-level VB owner window & checks for existing thunk
    
    Dim lWnd As Long, hwndOwner As Long, hMod As Long
    Const WS_SYSMENU As Long = &H80000
    Const WS_VISIBLE As Long = &H10000000
    Const WS_CHILD As Long = &H40000000
    Const GW_OWNER As Long = 4
    Const GW_HWNDNEXT As Long = 2
    Const GWL_STYLE As Long = -16
    Const OFFSET_VERSION As Long = 4
    Const WINTITLE As String = "stdPicEx-Listener2.0"
    ' coder note: Should the need arise where a version can no longer support backward compatibility,
    '   increment the number at the end of WINTITLE constant. Doing so will prevent upgrading any
    '   existing thunk in the VB process. Both versions will co-exist. Also in this case, the major
    '   vesion of the thunk should be incremented for consistrency.

    lWnd = FindWindow(vbNullString, vbNullString)
    Do Until lWnd = 0       ' locate a top level window related to this process
        If GetWindowThreadProcessId(lWnd, ByVal 0&) = App.ThreadID Then
            If (GetWindowLong(lWnd, GWL_STYLE) And (WS_SYSMENU Or WS_VISIBLE)) = (WS_SYSMENU Or WS_VISIBLE) Then
                If GetWindow(lWnd, GW_OWNER) = 0 Then
                    hwndOwner = lWnd
                    Exit Do
                End If
            End If
        End If
        lWnd = GetWindow(lWnd, GW_HWNDNEXT)
    Loop
    If hwndOwner Then       ' now find the hidden VB owner window
        m_hWndListener = FindWindowEx(hwndOwner, 0&, "Static", WINTITLE)
        If m_hWndListener = 0& Then
            m_hWndListener = CreateWindowEx(0&, "Static", WINTITLE, WS_CHILD, 0&, 0&, 0&, 0&, hwndOwner, 0&, 0&, ByVal 0&)
            If zzCreateThunk(True) = False Then
                ' zzCreateThunk may destroy m_hwndListener if its tiny thunk (144 bytes) failed creation
                If m_hWndListener Then SendMessage m_hWndListener, msgListener_setThunk, 0&, ByVal 0&
                If m_Debug Then Debug.Print "thunk failed creation!!!"
            End If
            
        ElseIf SendMessage(m_hWndListener, msgListener_getThunk, 0&, ByVal 0&) = 0& Then
            ' this should never occur. It means the last time the thunk attempted creation, it failed.
            If m_Debug Then Debug.Print "thunk failed initial creation!!! trying again"
            zzCreateThunk False ' try again
        Else
            ' see if different version already exists
            Call zzSafeThunkAddress
            CopyMemory hMod, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_VERSION), 4&
            If hMod < THUNK_VERSION Then
                zzLocateThunk = p_ThunkAddr             ' triggers thunk upgrade
                If m_Debug Then Debug.Print "thunk being upgraded"
            Else
                hMod = GetModuleHandleA("GdiPlus.dll")  ' get the GDI+ version
                If hMod Then
                    If GetProcAddress(hMod, "GdipDrawImageFX") = 0& Then m_GDIpVersion = 1! Else m_GDIpVersion = 1.1!
                End If
                If m_Debug Then Debug.Print "thunk already exists"
            End If
        End If
    End If
End Function

Private Sub zzUpgradeThunk(pThunkOld As Long)

    ' routine silently upgrades thunk version if needed

    Dim n As Long, lPtr As Long
    Dim arrData() As Long, arrRedirects() As Long
    Dim arrSafeArray() As Long, arrSafeArray2() As Long
    
    ' following 6 constants must be identical to those in zzCreateRedirection
    Const TABLE_SIZE As Long = 100              ' minimal size of a redirection table in bytes
    Const OFFSET_IUnkRelease As Long = 2        ' offset (Longs) for stdPic/IPicture IUnknown:Release
    Const OFFSET_Render As Long = 8             ' offset (Longs) for IPicture:Render
    Const OFFSET_GetAttrs As Long = 16          ' offset (Longs) for IPicture:get_Attributes
    Const OFFSET_THUNKFPTR As Long = 8          ' thunk offset for its 1st function (IUnknown:Release)
    Const DIFF_VTABLELOCS As Long = 7           ' number of Longs between VTable locations
    Const CB_MEM_RELEASE   As Long = &H8000&
    
    If zzCreateThunk(False) = True Then
        ' copy the 4 old thunk collection/array pointers to new thunk
        CopyMemory ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrObjVtbls), _
                   ByVal zzSafeOffset32(pThunkOld, OFFSET_ArrObjVtbls), 16&
        ' copy the old thunk client count, then release old thunk (no longer needed)
        CopyMemory n, ByVal pThunkOld, 4&
        CopyMemory ByVal p_ThunkAddr, n, 4&
        VirtualFree pThunkOld, 0&, CB_MEM_RELEASE
        If n = 0& Then Exit Sub ' if no clients, nothing else to do here
        ' otherwise, clients will be calling into the old thunk from their redirected VTable - fix it
        
        ' now we are going to loop thru the redirect records and update redirection VTable function pointers
        CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrRedirects), 4&
        CopyMemory n, ByVal lPtr, 4&            ' number of redirect record items (nr records = count\4)
        
        zzOverlayArray VarPtrArray(arrRedirects), lPtr, arrSafeArray(), n + 1&, False
        For n = 1& To n Step 4&                 ' skip record count
            If arrRedirects(n) > 0& Then        ' else empty record
            
                ' overlay array on redirection VTable (2nd item in each record)
                zzOverlayArray VarPtrArray(arrData), arrRedirects(n + 1&), arrSafeArray2(), TABLE_SIZE \ 4&, False
            
                ' thunk offset for IUnknown:Release, both VTables
                CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_THUNKFPTR), 4&
                arrData(OFFSET_IUnkRelease) = zzSafeOffset32(p_ThunkAddr, lPtr)
                arrData(DIFF_VTABLELOCS + OFFSET_IUnkRelease) = arrData(OFFSET_IUnkRelease)
                ' thunk offset for IPicture:get_Attributes
                CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_THUNKFPTR + 4&), 4&
                arrData(DIFF_VTABLELOCS + OFFSET_GetAttrs) = zzSafeOffset32(p_ThunkAddr, lPtr)
                ' thunk offset for IPicture:Render
                CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_THUNKFPTR + 8&), 4&
                arrData(DIFF_VTABLELOCS + OFFSET_Render) = zzSafeOffset32(p_ThunkAddr, lPtr)
                
                zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray2(), 0&, False
            End If
        Next
        zzOverlayArray VarPtrArray(arrRedirects), 0&, arrSafeArray(), 0&, False
    End If


End Sub

Private Function zzFillImage(hImage As Long, hBmp As Long, TransparencyFillColor As Long) As Long

    ' replacement for GdipCreateHBITMAPFromBitmap to ensure alpha channel is reset to opaque
    ' function designed to be passed same parameters and return 0 for success, non-zero for failure

    Dim hDC As Long, tBmp As Long, hGraphics As Long
    Dim fBounds(0 To 3) As Single, arrBMI(0 To 9) As Long
    
    zzFillImage = 3&    ' out of memory error; likely only reason this routine can fail
    
    hGraphics = GetDC(0&): hDC = CreateCompatibleDC(hGraphics)
    If hDC = 0& Then
        ReleaseDC 0&, hGraphics
        Exit Function
    End If
    GdipGetImageBounds hImage, fBounds(0), SrcUnit_Pixel
    arrBMI(0) = 40&: arrBMI(1) = fBounds(2): arrBMI(2) = fBounds(3): arrBMI(3) = &H200001
    tBmp = CreateDIBSection(hGraphics, arrBMI(0), 0&, ByVal 0&, 0&, 0&)
    ReleaseDC 0&, hGraphics
    If tBmp = 0& Then GoTo ExitRoutine
    
    tBmp = SelectObject(hDC, tBmp)
    If GdipCreateFromHDC(hDC, hGraphics) = 0& Then
        GdipGraphicsClear hGraphics, TransparencyFillColor
        GdipDrawImageRectRectI hGraphics, hImage, 0&, 0&, arrBMI(1), arrBMI(2), fBounds(0), fBounds(1), fBounds(2), fBounds(3), SrcUnit_Pixel, 0&, 0&, 0&
        GdipDeleteGraphics hGraphics
        hBmp = SelectObject(hDC, tBmp)      ' return bitmap
        zzFillImage = 0&                    ' return success
    Else
        DeleteObject SelectObject(hDC, tBmp) ' clean up; failure
    End If
    
ExitRoutine:
    DeleteDC hDC

End Function

Private Function zzGetCompatibleBmp(hImage As Long, tPic As StdPicture, bRGBA As Boolean, _
                                    Optional bNoDependency As Boolean) As Boolean

    ' returns a new GDI+ image handle or 32bpp bitmap handle
    
    ' Pretty much the key graphics-related function for GDI+ rendering of alpha bitmaps
    ' while sharing data; thus efficiently reducing memory consumption.
    
    ' There is no way to share a stream between a VB picture object and GDI+ image.
    ' VB keeps its own stream for its pictures; not the one passed to VB.
    
    ' So the trick to reduce memory usage is to allow VB to keep its stream, because we
    ' can't really do anything about that, but to share the pixel data between the
    ' picture object's DIB and the GDI+ image. We make the GDI+ image tied to same
    ' DIB bits. Downside is that one cannot destroy the DIB without also disposing
    ' of the GDI+ image; else GDI+ will crash if image is rendered or bits accessed.
    ' This isn't a problem here because we do not expose the DIB to the user
    
    
    Dim hDib As Long, uBMP As BITMAP
    Dim hDC As Long, tImage As Long
    Dim rBounds(0 To 3) As Single   ' faux GDI+ RECTF structure
    Dim BMI() As Long               ' faux BitmapInfo structure
    Dim bmpData As BitmapData
    
    If bRGBA Then                   ' set desired pixel format
        bmpData.bpPixelFormat = PixelFormat32bppARGB
    Else
        bmpData.bpPixelFormat = PixelFormat32bppPARGB
    End If
    
    If hImage = 0& Then             ' create DIB-bound hImage
        GetObjectA tPic.Handle, 24&, uBMP
        If uBMP.bmBits = 0& Or uBMP.bmBitsPixel <> 32& Then Exit Function
        ' GDI+ wants its images top-down, but DIBs are bottom-up
        ' So we tell GDI+ to read from bottom-up by giving it a negative stride from DIB's bottom-left pixel
        With uBMP
            If bmpData.bpHeight < 0& Then   ' top-down DIB (rare), ingore above comments
                bmpData.bpStride = .bmWidth * 4&
                bmpData.bpScan0Ptr = .bmBits
            Else
                bmpData.bpStride = .bmWidth * -4&
                bmpData.bpScan0Ptr = zzSafeOffset32(.bmBits, (.bmHeight - 1&) * -bmpData.bpStride)
            End If
            ' this call creates the DIB-bound GDI+ image
            GdipCreateBitmapFromScan0 .bmWidth, .bmHeight, bmpData.bpStride, bmpData.bpPixelFormat, bmpData.bpScan0Ptr, hImage
        End With
        zzGetCompatibleBmp = Not (hImage = 0&)
    
    ElseIf bNoDependency Then
        ' passed hImage is tied to some source (DIB, IStream, File, etc)
        ' return the same pixel data, that is not tied to anything
        GdipGetImageBounds hImage, rBounds(0), SrcUnit_Pixel
        With bmpData
            .bpHeight = rBounds(3): .bpWidth = rBounds(2)
            ' create a source-less GDI+ image, same size as the one passed
            If GdipCreateBitmapFromScan0(.bpWidth, .bpHeight, 0&, .bpPixelFormat, 0&, tImage) Then Exit Function
            ' get a write pointer to its data (currently data are all zeroes)
            If GdipBitmapLockBits(tImage, VarPtr(.bpLeft), ImageLockModeWrite, .bpPixelFormat, VarPtr(.bpWidth)) = 0& Then
                uBMP.bmBits = .bpReserved: .bpReserved = 0&
                ' above LockBits initializes the bmpData structure with its write-pointer
                ' pass same structure to the original image, requesting read into the above's pointer
                If GdipBitmapLockBits(hImage, VarPtr(.bpLeft), ImageLockModeRead Or ImageLockModeUserInputBuf, .bpPixelFormat, VarPtr(.bpWidth)) = 0& Then
                    GdipBitmapUnlockBits hImage, VarPtr(.bpWidth)   ' commit the read
                    GdipDisposeImage hImage: hImage = tImage        ' replace passed hImage
                    zzGetCompatibleBmp = True
                End If
                .bpReserved = uBMP.bmBits
                GdipBitmapUnlockBits tImage, VarPtr(.bpWidth)       ' commit the write
            End If
        End With
        If Not tImage = hImage Then
            If tImage Then GdipDisposeImage tImage                  ' if we got here: failure
        End If
        
    Else                            ' create 32bpp DIB from hImage
        hDC = GetDC(0&)
        If hDC = 0& Then Exit Function
        ReDim BMI(0 To 9)
        GdipGetImageBounds hImage, rBounds(0), SrcUnit_Pixel
        BMI(0) = 40: BMI(1) = rBounds(2): BMI(2) = rBounds(3): BMI(3) = &H200001
        hDib = CreateDIBSection(hDC, BMI(0), 0&, uBMP.bmBits, 0&, 0&)
        ReleaseDC 0&, hDC: Erase BMI()
        If hDib = 0& Then Exit Function
        ' Here we simply tell GDI+ to write its pixel data to our DIB.
        ' But GDI+ is top-down and DIB is bottom-up
        ' So we tell GDI+ to write bottom-up by giving it a negative stride from DIB's bottom-left pixel
        With bmpData
            .bpWidth = rBounds(2): .bpHeight = rBounds(3): .bpStride = .bpWidth * -4&
            .bpScan0Ptr = zzSafeOffset32(uBMP.bmBits, (.bpHeight - 1&) * -.bpStride)
        End With
        If GdipBitmapLockBits(hImage, VarPtr(bmpData.bpLeft), ImageLockModeRead Or ImageLockModeUserInputBuf, bmpData.bpPixelFormat, VarPtr(bmpData.bpWidth)) Then
            DeleteObject hDib       ' failure
        Else
            GdipBitmapUnlockBits hImage, VarPtr(bmpData.bpWidth)
            Set tPic = zzHandleToStdPicture(hDib, vbPicTypeBitmap)
            zzGetCompatibleBmp = True
        End If
    End If
    
End Function

Private Function zzQueryFormat(hImage As Long) As Long

    ' method simply queries the passed GDI+ image type (GUID defined)

    Dim GUID(0 To 3) As Long
    If GdipGetImageRawFormat(hImage, VarPtr(GUID(0))) = 0& Then
        Select Case GUID(0) ' uniquely identifies image type
            Case &HB96B3CAE: zzQueryFormat = picJPG
            Case &HB96B3CB0: zzQueryFormat = picGIF
            Case &HB96B3CAF: zzQueryFormat = picPNG
            Case &HB96B3CB1: zzQueryFormat = picTIF
            Case &HB96B3CAC: zzQueryFormat = picEMF
            Case &HB96B3CAD: zzQueryFormat = picWMF
            ' note: following three should never trigger, bmp,ico,cur processed without GDI+
            Case &HB96B3CAB: zzQueryFormat = picBMP ' bitmap file
            Case &HB96B3CAA: zzQueryFormat = picBMP ' memory bitmap (Scan0)
            Case &HB96B3CB5: zzQueryFormat = picICO
            ' anything else is either EMFplus, EMFdual or unexpected
        End Select
    End If
End Function

Private Sub zzUnmanage(thePicture As StdPicture)

    ' This routine umnanages a previously managed stdPicture.
    ' It is nearly guaranteed that the quality and/or appearance will not be
    '   correct if the image contained transparency and/or alphablending
    ' Note: Image controls generally require a refresh, picturebox controls do not

    If thePicture Is Nothing Then Exit Sub

    Dim lObjPtr As Long, nVtable As Long, n As Long
    Dim iPic As IPicture, lPtr As Long
    
    Set iPic = thePicture: lObjPtr = ObjPtr(iPic): Set iPic = Nothing
    Me.SetCallBacks thePicture, , rcbkNoCallbacks
    nVtable = CallThunk(f_MsgAddr, lObjPtr, msgObjGetVTable)
    If nVtable Then ' replace with original VTable references
        n = CallThunk(f_MsgAddr, nVtable, msgRedirectVTblIdx)
        If n > 0& Then
            CopyMemory ByVal lObjPtr, nVtable, 4&
            CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrRedirects), 4&
            CopyMemory ByVal ObjPtr(thePicture), ByVal zzSafeOffset32(lPtr, n * 4& - 4&), 4&
            CallThunk f_MsgAddr, lObjPtr, msgUnsubclass
        End If
    End If
    
End Sub

Private Function zzValidateAlphaChannel(hImage As Long, hBmp As Long) As Long
       
    ' Method determines if the alhpa channel is used and how it is used
    ' Speedy? For complex/standard transparency, should exit routine very fast.
    '   For anything else, all pixels will be scanned unfortuntely.
    '   Just can't exit until format is known for sure.
    
    ' Routine pulled from my AlphaImage control & slightly tweaked
    ' 4 Alpha formats are tracked by this routine
    '   Alpha channel not used. If all alpha bytes are just 0 or just 255
    '       note: all zero alpha bytes are assumed to be no alpha channel in use; otherwise 100% transparent
    '   Simple Transparency: all alpha bytes are a mix of only 0 or 255
    '   Complex Transparency: any alpha byte has range 1 to 254 and R,G,B channel > alpha channel
    '   PreMultiplied RGB Transparency: all R,G,B channel values <= alpha channel
   
    Dim bAlpha As Long, lFormat As Long
    Dim lColor As Long, lPrevColor As Long
    Dim arrData() As Long, arrSafeArray() As Long
    Dim fRect() As Single, X As Long
    Dim bmpData As BitmapData, uBMP As BITMAP
    Const ZEROES As Long = &H100&

    On Error GoTo ExitRoutine
   
    ' ///// test the alpha channel. Loop aborts early if it can
    If hImage Then
        ReDim fRect(0 To 3)
        GdipGetImageBounds hImage, fRect(0), SrcUnit_Pixel
        With bmpData
            .bpWidth = fRect(2): .bpHeight = fRect(3): X = .bpWidth * .bpHeight
        End With
        Erase fRect()
        If GdipBitmapLockBits(hImage, VarPtr(bmpData.bpLeft), ImageLockModeRead, PixelFormat32bppARGB, VarPtr(bmpData.bpWidth)) Then Exit Function
        zzOverlayArray VarPtrArray(arrData), bmpData.bpScan0Ptr, arrSafeArray(), X, False
    Else
        If hBmp = 0& Then Exit Function
        GetObjectA hBmp, 24&, uBMP
        If uBMP.bmBits = 0& Then Exit Function          ' not DIB based
        If uBMP.bmBitsPixel < 32& Then Exit Function    ' 24bpp or less
        X = uBMP.bmWidth * uBMP.bmHeight
        zzOverlayArray VarPtrArray(arrData), uBMP.bmBits, arrSafeArray(), X, False
    End If
    
    lPrevColor = arrData(0) Xor 1&
    For X = 0& To X - 1&
        lColor = arrData(X)               ' get 32bit color
        If Not lColor = lPrevColor Then     ' and extact the alpha byte
            If lColor = 0& Then
                lFormat = lFormat Or ZEROES ' entire value is zero
                ' all zeroes indicates 100% transparent or 100% black image
                ' mix of zero & non-zero alpha values indicates transparency
            Else
                bAlpha = (lColor And &HFF000000) \ &H1000000 And &HFF
                If bAlpha = 0& Then
                    If (lColor And &HFFFFFF) Then  ' RGB value is non-zero
                        If (lFormat And Not ZEROES) > 2& Then
                            ' at least one other alpha value was > 0 and < 255
                            ' since this alpha is zero & RGB non-zero. Done:
                            lFormat = 8&: Exit For
                        End If
                        lFormat = lFormat Or 1& ' keep going, maybe all alphas are zero
                    End If
                ElseIf bAlpha = 255& Then
                    If (lFormat And 1&) Then
                        ' already seen alpha zero & non-zero RGB. Here we have 255 alpha. Done:
                        lFormat = 8&: Exit For
                    End If
                    lFormat = lFormat Or 2&
                   
                ' else if any RGB values > alpha then not-premultiplied
                ElseIf bAlpha < (lColor And &HFF&) Then
                    lFormat = 8&: Exit For ' definitly ARGB
                ElseIf bAlpha < (lColor And &HFF00&) \ &H100& Then
                    lFormat = 8&: Exit For ' definitly ARGB
                ElseIf bAlpha < (lColor And &HFF0000) \ &H10000 Then
                    lFormat = 8&: Exit For ' definitly ARGB
                Else
                    lFormat = lFormat Or 16& ' likely pARGB, but not sure yet
                End If
            End If
            lPrevColor = lColor
        End If
    Next
    zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, False
    If hImage Then GdipBitmapUnlockBits hImage, VarPtr(bmpData.bpWidth)
    
    ' ///// Step 4: Analyze result
    If (lFormat And Not ZEROES) = 8& Then   ' alpha, not premultiplied
        zzValidateAlphaChannel = tfPicHasTransp Or tfTransparent
    ElseIf lFormat = (ZEROES Or 2&) Then    ' simple transparency
        zzValidateAlphaChannel = tfPicHasTransp Or tfTransparent
    ElseIf (lFormat And 16&) Then           ' premultiplied RGB
        zzValidateAlphaChannel = tfPicHasPARGB Or tfTransparent
    End If                                  ' else assume alpha channel not used
   
ExitRoutine:
End Function

Private Function zzValidateBmp(IStream As stdole.IUnknown, lSize As Long, ManageStyle As Long, _
                                tPic As StdPicture, lDPI As Long, bKOF As Boolean, _
                                FillColor As Long, pEventParam As Variant) As Long
                                
    ' If bitmap to be managed and less than 16bpp (palette exists) need DIB vs DDB if managed
    '   reason: Thunk uses GdipCreateBitmapFromHBITMAP for dynamic scaling when managed.
    '           Since thunk does not check for, nor attempt to retrieve, a bmp palette,
    '           the hBitmap must be DIB else palette is not defined & could render wrong
    ' Also, if alpha channel valid, want DIB vs DDB when managed
                                
    Dim arrData() As Byte, arrSafeArray() As Long, arrBMI() As Long
    Dim hDC As Long, hDib As Long, pvBits As Long
    Dim lFlags As Long, lValue As Long
    Dim hLock As Long, hGlobal As Long, hImage As Long
    Dim tStream As stdole.IUnknown, tGlobal As Long
    Dim pProps(0 To 2, 1 To 1) As Long, bAbort As Boolean
    Dim fBounds(0 To 3) As Single

    If lSize < 16& Then Exit Function
    ' ^^ absolute minimum size for a valid bitmap, old format: 12-byte header + 4 bytes for 1x1 pixel bitmap
    
    GetHGlobalFromStream ObjPtr(IStream), hGlobal
    If hGlobal = 0& Then Exit Function
    
    hLock = GlobalLock(hGlobal)             ' get stream data
    If hLock = 0& Then Exit Function
    zzOverlayArray VarPtrArray(arrData()), hLock, arrSafeArray(), lSize, True
    If Not (arrData(0) = 66 And arrData(1) = 77) Then GoTo ExitRoutine
    ReDim arrBMI(-2 To 30)   ' max size needed for all supported headers (no palettes)
   
    CopyMemory arrBMI(0), arrData(14), 4&   ' get bitmap header size
    If arrBMI(0) = 12& Then                 ' old header, but VB still supports it
        arrBMI(1) = arrData(18) Or arrData(19) * &H100& ' dimensions are integer vs long
        arrBMI(2) = arrData(20) Or arrData(21) * &H100&
        CopyMemory arrBMI(3), arrData(22), 4&   ' get bitcount & validate planes
        If Not (arrBMI(3) And &HFFFF&) = 1 Then GoTo ExitRoutine
        lValue = (arrBMI(3) \ &H10000) And &HFFFF&
        On Error GoTo ExitRoutine
        Select Case lValue
        Case 1, 4, 8    ' paletted, colors are 3 bytes each
            lValue = (2 ^ lValue) * 3& + zzDWordAlign(arrBMI(1), lValue) * arrBMI(2) + arrBMI(0)
        Case 24         ' same as newer headers
            lValue = zzDWordAlign(lValue, arrBMI(1)) * arrBMI(2) + arrBMI(0)
        Case Else: GoTo ExitRoutine
        End Select                          ' validate source large enough
        If lValue + 14& > lSize Then GoTo ExitRoutine
        On Error GoTo 0
        lFlags = picBMP * tfShiftPicType         ' is a bitmap
        pProps(0, 1) = arrBMI(1): pProps(1, 1) = arrBMI(2)
        RaiseEvent PreLoadPicture(picBMP, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, FillColor, bAbort, pEventParam)
        Erase pProps()
        If bAbort Then GoTo ExitRoutine
        Set tPic = zzIStreamToPicture(ObjPtr(IStream), bKOF, lSize)
        pvBits = arrBMI(0) + 14&
       
    ElseIf lSize < arrBMI(0) + 14& Then     ' pre-validate source large enough
        GoTo ExitRoutine
    Else                                    ' get rest of header, bitcount & validate planes
        CopyMemory arrBMI(1), arrData(18), arrBMI(0) - 4&
        If Not (arrBMI(3) And &HFFFF&) = 1 Then GoTo ExitRoutine
        
        If arrBMI(6) > 0& Then lDPI = arrBMI(6) * 0.0254 ' return DPI if available
        
        lValue = (arrBMI(3) \ &H10000) And &HFFFF&
        Select Case lValue
        Case 0  ' must have compression as BI_JPG/BI_PNG else not a valid bitmap format
            If arrBMI(4) = 4 Or arrBMI(4) = 5 Then
                lFlags = picBMP * tfShiftPicType
                If arrBMI(5) + arrBMI(0) + 14& <= lSize Then
                    If zzIStreamFromSource("", arrData(), tGlobal, 0&, arrBMI(0) + 14&, arrBMI(5)) Then
                        If CreateStreamOnHGlobal(tGlobal, 1&, tStream) = 0& Then
                            If GdipLoadImageFromStream(ObjPtr(tStream), hImage) = 0& Then
                                GdipGetImageBounds hImage, fBounds(0), SrcUnit_Pixel
                                pProps(0, 1) = fBounds(2): pProps(1, 1) = fBounds(3)
                                Select Case zzQueryFormat(hImage)
                                Case picJPG
                                    RaiseEvent PreLoadPicture(picBMP, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, FillColor, bAbort, pEventParam)
                                    If bAbort = False Then
                                        GdipCreateHBITMAPFromBitmap hImage, hDib, -1&
                                        If hDib Then Set tPic = zzHandleToStdPicture(hDib, vbPicTypeBitmap)
                                    End If
                                Case picPNG
                                    lFlags = lFlags Or zzValidateAlphaChannel(hImage, 0&)
                                    pProps(2, 1) = (lFlags And tfMaskTransp) \ &H20000000
                                    RaiseEvent PreLoadPicture(picBMP, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, FillColor, bAbort, pEventParam)
                                    If bAbort = False Then
                                        If (lFlags And tfMaskTransp) Then
                                            zzGetCompatibleBmp hImage, tPic, (lFlags And tfPicHasTransp)
                                        Else
                                            zzFillImage hImage, hDib, -1&
                                            If hDib Then Set tPic = zzHandleToStdPicture(hDib, vbPicTypeBitmap)
                                        End If
                                    End If
                                End Select
                                GdipDisposeImage hImage: hImage = 0&: hDib = 0&
                                Erase pProps()
                                If bAbort Then GoTo ExitRoutine
                            End If
                        Else
                            GlobalFree tGlobal
                        End If
                        Set tStream = Nothing
                    End If
                End If
            End If
            GoTo ExitRoutine
        Case 1, 4, 8    ' paletted, colors are 4 bytes each
            If arrBMI(8) = 0& Then
                pvBits = (2 ^ lValue) * 4& + arrBMI(0) + 14&
            Else
                pvBits = arrBMI(8) * 4& + arrBMI(0) + 14&
            End If
            If arrBMI(4) = 1 Or arrBMI(4) = 2 Then  ' BI_RLE8,BI_RLE4
                lValue = pvBits + arrBMI(5)
            Else
                lValue = pvBits + zzDWordAlign(lValue, arrBMI(1)) * Abs(arrBMI(2))
            End If
        Case 16, 24, 32
            pvBits = arrBMI(0) + 14&
            Select Case arrBMI(4)
            Case 0
            Case 3: If Not (lValue = 24 Or arrBMI(0) > 40&) Then pvBits = pvBits + 12&
            Case 4, 5   ' BI_JPG/BI_PNG
                lFlags = picBMP * tfShiftPicType: GoTo ExitRoutine ' unusupported
            Case Else: GoTo ExitRoutine             ' corrupt or not bitmap format
            End Select
            If arrBMI(8) > 0& Then pvBits = pvBits + arrBMI(8) * 4&
            On Error GoTo ExitRoutine
            lValue = pvBits + zzDWordAlign(lValue, arrBMI(1)) * Abs(arrBMI(2))
            On Error GoTo 0
        Case Else: GoTo ExitRoutine
        End Select
        lFlags = picBMP * tfShiftPicType
        If lValue > lSize Then GoTo ExitRoutine
        If arrBMI(0) = 40& Then
            ' load via VB if not v4/v5 of header and: not managed or managed & not paletted
            Set tPic = zzIStreamToPicture(ObjPtr(IStream), bKOF, lSize)
        End If
    End If
   
    If tPic Is Nothing Then     ' else created via VB
        hDC = GetDC(0&)
        If arrBMI(4) = 1 Or arrBMI(4) = 2 Then ' compressed, can't create DIB with these settings
            CopyMemory arrBMI(-2), arrBMI(4), 8& ' temporarily cache & then zeroize
            CopyMemory arrData(30), 0@, 8&
        End If
        hDib = CreateDIBSection(hDC, arrData(14), 0&, ByVal 0&, 0&, 0&)
        If arrBMI(-2) > 0& Then CopyMemory arrData(30), arrBMI(-2), 8& ' restore cached compression
        If hDib = 0& Then GoTo ExitRoutine
        SetDIBits hDC, hDib, 0&, Abs(arrBMI(2)), arrData(pvBits), arrData(14), 0&
        ReleaseDC 0&, hDC: hDC = 0&
        Set tPic = zzHandleToStdPicture(hDib, vbPicTypeBitmap)
        If bKOF Then lFlags = lFlags Or tfIStream
    End If
    If arrBMI(3) \ &H10000 = 32& Then
        lFlags = lFlags Or zzValidateAlphaChannel(0&, tPic.Handle)
        pProps(2, 1) = (lFlags And tfMaskTransp) \ &H20000000
    End If
    pProps(0, 1) = arrBMI(1): pProps(1, 1) = arrBMI(2)
    RaiseEvent PreLoadPicture(picBMP, pProps(), ManageStyle, bKOF, 0&, 0&, 0&, 0&, FillColor, bAbort, pEventParam)
    If bAbort Then
        Set tPic = Nothing
        Exit Function
    End If

ExitRoutine:
    If Err Then Err.Clear
    On Error GoTo 0
    If hDC Then ReleaseDC 0&, hDC
    zzOverlayArray VarPtrArray(arrData()), 0&, arrSafeArray(), 0&, True
    GlobalUnlock hGlobal
    zzValidateBmp = lFlags
    
End Function

Private Function zzValidateIcon(IStream As stdole.IUnknown, lSize As Long, _
                                Manage As ManagementStyle, tPic As StdPicture, hImage As Long, _
                                IconIndex As Long, IconCx As Long, IconCy As Long, IconDepth As Long, _
                                bKOF As Boolean, pEventParam As Variant) As Long
                                
    ' both VB & GDI+ have problems with icons/cusors
    ' This routine attempts to handle them individually
    ' - cursors returned as color vs B&W while in IDE
    ' - PNG-encoded icons/cursors manually processed for XP and lower
    ' - customized sort/look-up routine for best-fit when multiple images in source
    ' - creates hImage if enhanced management
                                
    Dim hLock As Long, fRect() As Single
    Dim arrData() As Byte, arrSafeArray() As Long
    Dim lOffsets() As Long, aSort() As Long
    Dim n As Long, hDC As Long, hGlobal As Long
    Dim X As Long, Y As Long, lFlags As Long
    Dim lIndex As Long, lItemCount As Long
    Dim lValue As Long, hIcon As Long
    Dim mskShift As Long, bmpData As BitmapData
    Dim tStream As stdole.IUnknown
    Dim pProps() As Long, bAbort As Boolean
    Const BITSPIXEL As Long = 12

    GetHGlobalFromStream ObjPtr(IStream), hGlobal
    If hGlobal = 0& Then Exit Function
    hLock = GlobalLock(hGlobal)
    If hLock = 0& Then Exit Function
    On Error GoTo ExitRoutine    ' in case of overflows when adding offset+size below
    
    ' perform minimal validation of icon/cursor format
    zzOverlayArray VarPtrArray(arrData), hLock, arrSafeArray(), lSize, True
    If lSize < 56& Then GoTo ExitRoutine
    If Not (arrData(0) = 0 And arrData(1) = 0) Then GoTo ExitRoutine    ' 1st integer must be zero
    If Not (arrData(2) = 1 Or arrData(2) = 2) Then GoTo ExitRoutine     ' 2nd integer must be 0 or 1
    lItemCount = arrData(4) Or arrData(5) * &H100&
    lValue = lItemCount * 16& + 6&
    If lValue > lSize Or lValue = 6& Then GoTo ExitRoutine
    ReDim pProps(0 To 2, 1 To lItemCount)
    
    ' continue with validation
    ReDim lOffsets(0 To 2, 0 To lItemCount - 1)
    n = 14&
    For lItemCount = 0& To lItemCount - 1&
        ' read each size/offset value & validate within range of file size
        CopyMemory lOffsets(0, lItemCount), arrData(n), 8&
        If lOffsets(0, lItemCount) < 0& Or lOffsets(1, lItemCount) < lValue Then GoTo ExitRoutine ' invalid size/offset
        ' calc the start and end of each data block
        lOffsets(2, lItemCount) = lOffsets(0, lItemCount) + lOffsets(1, lItemCount)
        If lOffsets(2, lItemCount) > lSize Then GoTo ExitRoutine
        n = n + 16&
    Next
    On Error GoTo 0
    
    If arrData(2) = 2 Then lFlags = picCUR * tfShiftPicType Else lFlags = picICO * tfShiftPicType
    ' simple loop to ensure no data block starts inside another; looking for corruption
    For Y = 0& To lItemCount - 2&
        For X = Y + 1& To lItemCount - 1&
            If (lOffsets(0, Y) > lOffsets(0, X)) Then
                If (lOffsets(2, Y) < lOffsets(0, X)) Then GoTo ExitRoutine
            End If
        Next
    Next
    ' validation complete, treat as icon/cursor; gather properties for PreLoadPicture event
    
    For lItemCount = 0& To lItemCount - 1&
        Y = lOffsets(1, lItemCount)             ' offset to bitmapinfo header
        CopyMemory lValue, arrData(Y), 4&       ' test for PNG
        If lValue = &H474E5089 Then             ' get dimensions/depth from PNG header
            CopyMemory X, arrData(Y + 16&), 4&
            pProps(0, lItemCount + 1&) = zzReverseLong(X)
            CopyMemory X, arrData(Y + 20&), 4&
            pProps(1, lItemCount + 1&) = zzReverseLong(X)
            n = arrData(lItemCount * 16& + 12&) ' use icondir bitcount if reasonable
            If (n = 0& Or n > 32&) Or arrData(2) = 2 Then ' else fetch it from header
                Select Case arrData(Y + 25&)
                    Case 4, 6: n = 32&
                    Case 2: n = 24&
                    Case Else: n = arrData(Y + 24&)
                End Select
            End If
            pProps(2, lItemCount + 1&) = n
        Else                                ' get real width/height
            CopyMemory pProps(0, lItemCount + 1&), arrData(Y + 4&), 4&
            CopyMemory X, arrData(Y + 8&), 4&
            pProps(1, lItemCount + 1&) = X \ 2&
            CopyMemory pProps(2, lItemCount + 1&), arrData(Y + 14&), 2&
        End If
    Next
    RaiseEvent PreLoadPicture((lFlags And tfMaskPicType) \ tfShiftPicType, pProps(), Manage, bKOF, IconIndex, IconCx, IconCy, IconDepth, 0&, bAbort, pEventParam)
    If bAbort Then GoTo ExitRoutine
    
    ' sanity checks & set desired size
    If IconDepth < 0& Then IconDepth = 0&
    If IconCx < 1& Or IconCy < 1& Then
        If IconIndex = 0& Then      ' use system settings
            IconCx = GetSystemMetrics(11)   ' SM_CXICON
            IconCy = GetSystemMetrics(12)   ' SM_CYICON
        ElseIf IconIndex < 0& Then
            IconCx = GetSystemMetrics(49)   ' SM_CXSMICON
            IconCy = GetSystemMetrics(50)   ' SM_CYSMICON
        Else
            IconCx = 0&: IconCy = 0&        ' actual size
        End If
    End If
    
    If lItemCount = 1& Then     ' no look-up needed
        lIndex = 0&
    ElseIf IconIndex > 0& Then  ' use passed index, no look-up needed
        If IconIndex > lItemCount Then lIndex = lItemCount - 1& Else lIndex = IconIndex - 1&
        
    Else                        ' find best match, simple sort algo
        ReDim aSort(0 To 1, 0 To lItemCount - 1&)
        For lItemCount = 0& To lItemCount - 1&
            lValue = (pProps(0, lItemCount + 1&) + pProps(1, lItemCount + 1&)) * &H100& Or pProps(2, lItemCount + 1&)
            For X = 0& To lItemCount - 1&       ' add to array, sorted
                If aSort(1, X) > lValue Then
                    For Y = lItemCount To X + 1 Step -1&
                        aSort(0, Y) = aSort(0, Y - 1)
                        aSort(1, Y) = aSort(1, Y - 1)
                    Next
                    Exit For
                End If
            Next
            aSort(0, X) = lItemCount: aSort(1, X) = lValue
        Next
        ' note: when sorted, bits 0xFFFFFF00 contain size and 0xFF contains bit depth
        ' this produces the sorted list first by size then by depth, within duplicate sizes
        
        ' now find best size from the sorted list, exclude the depth for this part
        lValue = (IconCx + IconCy) * &H100&
        For X = 0& To lItemCount - 1&
            If (aSort(1, X) And &HFFFFFF00) >= lValue Then Exit For
        Next
        If X < lItemCount Then
            ' now find the best bit depth
            If IconDepth = 0& Then Call zzRealDPI(IconDepth)
            lValue = lValue Or IconDepth
            If (aSort(1, X) And &HFF) < IconDepth Then
                For X = X + 1& To lItemCount - 1&
                    If (aSort(1, X) And &HFFFFFF00) > (aSort(1, X - 1&) And &HFFFFFF00) Then
                        X = X - 1&: Exit For
                    End If
                    If (aSort(1, X) And &HFF) >= IconDepth Then Exit For
                Next
            End If
        End If
        If X = lItemCount Then lIndex = aSort(0, X - 1&) Else lIndex = aSort(0, X)
        Erase aSort()
    End If
    ' lIndex contains our best-match reference
    
    Erase pProps()
    CopyMemory lValue, arrData(lOffsets(1, lIndex)), 4& ' bitmap header first 4 bytes
    If lValue = &H474E5089 Then                     ' PNG
        lFlags = lFlags Or tfPicHasTransp Or tfTransparent
        If arrData(2) = 2 Then                      ' haven't seen PNG cursor yet, but who knows?
            CopyMemory n, arrData(lOffsets(1, lIndex) - 4&), 4&
            CopyMemory arrData(lOffsets(1, lIndex) - 4&), arrData(lIndex * 16& + 10&), 4&
            hIcon = CreateIconFromResourceEx(arrData(lOffsets(1, lIndex) - 4&), lOffsets(0, lIndex) + 4&, 0&, &H30000, IconCx, IconCy, 0&)
            CopyMemory arrData(lOffsets(1, lIndex) - 4&), n, 4&
        Else
            hIcon = CreateIconFromResourceEx(arrData(lOffsets(1, lIndex)), lOffsets(0, lIndex), 1&, &H30000, IconCx, IconCy, 0&)
        End If
        If hIcon Then
            Set tPic = zzHandleToStdPicture(hIcon, vbPicTypeIcon)
            If Not Manage = mgtEnhanced Then GoTo ExitRoutine
        End If
        ' ^^ may have failed if on XP or lower. Want or need hImage, do that now
        If zzIStreamFromSource("", arrData(), lValue, 0&, lOffsets(1, lIndex), lOffsets(0, lIndex)) = False Then GoTo ExitRoutine
        If CreateStreamOnHGlobal(lValue, 1&, tStream) = 0& Then
            GdipLoadImageFromStream ObjPtr(tStream), hImage
            If hImage = 0& Then GoTo ExitRoutine
        Else
            GlobalFree lValue: GoTo ExitRoutine
        End If
                                                    ' cache hotspot if applies, and continue on...
        If arrData(2) = 2 Then CopyMemory n, arrData(lOffsets(lIndex * 16& + 10&)), 4&
        GlobalUnlock hGlobal: hLock = 0&
        zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, False
        
        Erase lOffsets()
        ReDim fRect(0 To 3)                         ' to prevent keeping stream around, create stand-alone image
        GdipGetImageBounds hImage, fRect(0), SrcUnit_Pixel
        If hIcon Then                           ' ensure hImage same size as icon/cursor
            Me.GetImageDimensions tPic, IconCx, IconCy
            If Not (IconCx = fRect(2) And IconCy = fRect(3)) Then
                zzXeroxFormat tPic, Nothing, 0&, False, IconCx, IconCy, mgtVbOnly, False, , , , hImage
                Set tStream = Nothing: GoTo ExitRoutine
            End If
        End If
        On Error Resume Next
        With bmpData
            .bpWidth = fRect(2): .bpHeight = fRect(3): .bpStride = .bpWidth * 4&
            .bpPixelFormat = PixelFormat32bppPARGB
            ReDim arrData(0 To .bpStride * .bpHeight - 1&)
        End With
        Erase fRect()
        If Err Then
            GdipDisposeImage hImage: hImage = 0&
            GoTo ExitRoutine
        End If
        On Error GoTo 0
        bmpData.bpScan0Ptr = VarPtr(arrData(0))      ' copy GDI+ bits
        If GdipBitmapLockBits(hImage, VarPtr(bmpData.bpLeft), ImageLockModeRead Or ImageLockModeUserInputBuf, bmpData.bpPixelFormat, VarPtr(bmpData.bpWidth)) Then
            GdipDisposeImage hImage: hImage = 0&
            GoTo ExitRoutine
        End If
        GdipBitmapUnlockBits hImage, VarPtr(bmpData.bpWidth)    ' now create new image & set its bits
        GdipDisposeImage hImage: hImage = 0&
        GdipCreateBitmapFromScan0 bmpData.bpWidth, bmpData.bpHeight, 0&, bmpData.bpPixelFormat, 0&, hImage
        If hImage = 0& Then GoTo ExitRoutine
        bmpData.bpReserved = 0&
        If GdipBitmapLockBits(hImage, VarPtr(bmpData.bpLeft), ImageLockModeWrite Or ImageLockModeUserInputBuf, bmpData.bpPixelFormat, VarPtr(bmpData.bpWidth)) Then
            GdipDisposeImage hImage: hImage = 0:
            GoTo ExitRoutine
        End If
        GdipBitmapUnlockBits hImage, VarPtr(bmpData.bpWidth)
        Erase arrData(): Set tStream = Nothing
        If hIcon Then GoTo ExitRoutine              ' done
        
        ' hIcon failed to be created, on XP or lower. We will do this another way
        lValue = zzDWordAlign(1, bmpData.bpWidth)
        On Error Resume Next
        ReDim arrData(-4 To (bmpData.bpStride + lValue) * bmpData.bpHeight + 39&) ' size & copy hotspot if applies
        If Err Then
            GdipDisposeImage hImage: hImage = 0&
            GoTo ExitRoutine
        End If
        On Error GoTo 0                             ' transfer cursor hotspot, cached from above
        If (lFlags And tfMaskPicType) \ tfShiftPicType = picCUR Then CopyMemory arrData(-4&), n, 4&
        arrData(0) = 40                             ' fill bitmapinfo header
        With bmpData
            CopyMemory arrData(4), .bpWidth, 4&
            CopyMemory arrData(8), .bpHeight + .bpHeight, 4&
            arrData(12) = 1: arrData(14) = 32           ' read png data into array
            .bpScan0Ptr = VarPtr(arrData(.bpStride * (.bpHeight - 1&) + 40&))
            .bpReserved = 0&: .bpPixelFormat = PixelFormat32bppARGB: .bpStride = -.bpStride
        End With
        If GdipBitmapLockBits(hImage, VarPtr(bmpData.bpLeft), ImageLockModeRead Or ImageLockModeUserInputBuf, bmpData.bpPixelFormat, VarPtr(bmpData.bpWidth)) Then
            GdipDisposeImage hImage: hImage = 0&
            GoTo ExitRoutine
        End If
        GdipBitmapUnlockBits hImage, VarPtr(bmpData.bpWidth)
        bmpData.bpStride = -bmpData.bpStride        ' create mask
        lIndex = bmpData.bpStride * bmpData.bpHeight + 40& ' start of mask bits
        For Y = 0& To bmpData.bpHeight - 1&
            mskShift = 128&: n = lIndex + Y * lValue ' mask bits scanline
            X = Y * bmpData.bpStride + 40&               ' color bits scanline
            For X = X + 3& To X + bmpData.bpStride - 1& Step 4&
                If arrData(X) < 128 Then arrData(n) = arrData(n) Or mskShift
                If mskShift = 1& Then
                    mskShift = 128&: n = n + 1&
                Else
                    mskShift = mskShift \ 2&
                End If
            Next
        Next                                        ' create icon/cursor
        If (lFlags And tfMaskPicType) \ tfShiftPicType = picCUR Then X = -4& Else X = 0&
        hIcon = CreateIconFromResourceEx(arrData(X), UBound(arrData) + 1& - X, Abs(X = 0&), &H30000, IconCx, IconCy, 0&)
        Erase arrData()
        If hIcon = 0& Then
            GdipDisposeImage hImage: hImage = 0&    ' failure overall
        Else
            Set tPic = zzHandleToStdPicture(hIcon, vbPicTypeIcon)
            If Manage = mgtEnhanced Then            ' ensure hImage same size as icon/cursor
                Me.GetImageDimensions tPic, IconCx, IconCy
                If Not (IconCx = bmpData.bpWidth And IconCy = bmpData.bpHeight) Then
                    zzXeroxFormat tPic, Nothing, 0&, False, IconCx, IconCy, mgtVbOnly, False, , , , hImage
                End If
            Else
                GdipDisposeImage hImage: hImage = 0&
            End If
        End If
        
    Else
        If arrData(2) = 2 Then                      ' get cursor hotspot
            Y = lIndex * 16& + 10&
            X = arrData(Y) Or arrData(Y + 1&) * &H100&
            Y = arrData(Y + 2&) Or arrData(Y + 3&) * &H100&
        End If                                      ' call routine to build icon/hImage from array
        If Manage = mgtAutoSelect Then lValue = mgtEnhanced Else lValue = Manage
        lFlags = zzBitmapFromHICON(tPic, 0&, hImage, lValue, IconCx, IconCy, _
                                    VarPtr(arrData(lOffsets(1, lIndex))), 0&, _
                                    lOffsets(0, lIndex), Not (arrData(2) = 2), X, Y)
        Erase lOffsets()
    End If

ExitRoutine:
    On Error GoTo 0
    If hLock Then
        zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), lSize, False
        GlobalUnlock hGlobal
    End If
    If tPic Is Nothing Then
        If hImage Then GdipDisposeImage hImage: hImage = 0&
    End If
    zzValidateIcon = lFlags

End Function

Private Function zzBitmapFromHBMP(hBmp As Long, tPic As StdPicture, bValidateAlpha As Boolean, bWrapOnly As Boolean) As Long

    ' routine simply creates a DIB section vs DDB
    ' return are flags: type and alhpa channel or zero
    ' tPic is filled if function successful

    Dim uBMP As BITMAP, lFlags As Long, tBmp As Long
    Const LR_CREATEDIBSECTION As Long = &H2000
    
    If GetObjectA(hBmp, 24&, uBMP) = 0& Then Exit Function
    lFlags = picBMP * tfShiftPicType
    If bWrapOnly Then ' just wrap it in a stdPicture
        Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
        GoTo ExitRoutine
    End If
    
    hBmp = CopyImage(hBmp, 0&, 0&, 0&, LR_CREATEDIBSECTION)
    If hBmp = 0& Then GoTo ExitRoutine
    Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
    If bValidateAlpha = True And uBMP.bmBitsPixel = 32& Then
        If uBMP.bmBitsPixel = 32& Then lFlags = lFlags Or zzValidateAlphaChannel(0&, hBmp)
    End If
    
ExitRoutine:
    zzBitmapFromHBMP = lFlags
    
End Function

Private Function zzBitmapFromHICON(tPic As StdPicture, srcIcon As Long, hImage As Long, Manage As ManagementStyle, _
                                    IconCx As Long, IconCy As Long, _
                                    Optional ByVal ColorSource As Long, Optional ByVal MaskSource As Long, _
                                    Optional SourceArraySize As Long, Optional isIcon As Boolean = True, _
                                    Optional xHotSpot As Long, Optional yHotSpot As Long) As Long

    ' routine creates a 32bpp ARGB bitmap from passed icon and/or creates hIcon from passed source data
    ' Manage:
    '   -1 = wrap passed srcIcon. tPic created
    '   -2 = process source, do not create tPic, create hImage
    '   mgtEnhanced = process source, create tPic & hImage
    '   other = process source, create tPic not hImage
    ' srcIcon
    '   if non-zero, ColorSource & MaskSource not used
    '   if zero then ColorSource & MaskSource must be provided
    '       if source is a pair of bitmaps then
    '           ColorSource is color bitmap, MaskSource is mask bitmap
    '           note: if B&W image, pass ColorSource = MaskSource
    '       if source is an array then
    '           ColorSource is pointer to where bitmap info header starts
    '           ColorMask is pointer to mask bits or zero if this routine calcs position
    

    Dim aDst() As Long, aBMI() As Long, aICI() As Long      ' faux BitmapInfo headers & ICONINFO structures
    Dim X As Long, Y As Long, z As Long
    Dim aMask() As Byte, aColor() As Long
    Dim arrSafeArrayC() As Long, arrSafeArrayM() As Long
    Dim hDib As Long, hIcon As Long, lFlags As Long
    Dim hDC As Long, pvSrcBits As Long, iPic As StdPicture
    Dim pvBits As Long, lBpp As Long, bmpData As BitmapData
    Dim lMskScan As Long, lMskShift As Long
    
    If (IconCx < 1& Or IconCy < 1&) Then IconCx = 0&: IconCy = 0&
    If srcIcon Then                     ' passed hIcon/hCursor handle?
        ReDim aICI(0 To 4)
        If GetIconInfo(srcIcon, aICI(0)) = 0& Then Exit Function
        If aICI(0) Then
            lFlags = picICO * tfShiftPicType: isIcon = True
        Else
            lFlags = picCUR * tfShiftPicType: isIcon = False
        End If
        If Manage = -1& Then            ' special case, wrap icon/cursor only
            Set tPic = zzHandleToStdPicture(srcIcon, vbPicTypeIcon)
            GoTo ExitRoutine
        ElseIf Not Manage = -2& Then    ' else special case, no picture returned, just hImage
            hIcon = CopyImage(srcIcon, 1&, IconCx, IconCy, 0&)
            If hIcon = 0& Then          ' this should not fail unless low on system memory
                If aICI(4) Then DeleteObject aICI(4)
                If aICI(3) Then DeleteObject aICI(3)
                Exit Function
            End If                      ' set return picture object
            Set tPic = zzHandleToStdPicture(hIcon, vbPicTypeIcon)
            If Not Manage = mgtEnhanced Then GoTo ExitRoutine
        End If                          ' set sources for hImage creation
        MaskSource = aICI(3): isIcon = CBool(aICI(0))
        If aICI(4) Then ColorSource = aICI(4) Else ColorSource = MaskSource
    Else
        If isIcon Then lFlags = picICO * tfShiftPicType Else lFlags = picCUR * tfShiftPicType
    End If
    
    ReDim aDst(0 To 9): aDst(0) = 40: aDst(3) = &H200001
    If SourceArraySize Then
        If Not Manage = -2& Then            ' else special case, no picture returned, just hImage
            If isIcon = False Then          ' cache previous 4 bytes; replace with hotspot
                Y = zzSafeOffset32(ColorSource, -4&)
                CopyMemory X, ByVal Y, 4&
                CopyMemory ByVal Y, xHotSpot Or (yHotSpot And &H7FFF) * &H10000, 4&
                hIcon = CreateIconFromResourceEx(ByVal Y, SourceArraySize + 4&, 0&, &H30000, IconCx, IconCy, 0&)
                CopyMemory ByVal Y, X, 4& ' restore previous 4 bytes
            Else
                hIcon = CreateIconFromResourceEx(ByVal ColorSource, SourceArraySize, Abs(isIcon), &H30000, IconCx, IconCy, 0&)
            End If
            If hIcon = 0& Then Exit Function
            Set tPic = zzHandleToStdPicture(hIcon, vbPicTypeIcon)
            If Not Manage = mgtEnhanced Then GoTo ExitRoutine
        End If
        CopyMemory X, ByVal ColorSource, 4&     ' fill destination bmp header & locate bits
        ReDim aBMI(0 To 268)
        CopyMemory aBMI(0), ByVal ColorSource, X ' fill header, except palette
        aDst(1) = aBMI(1): aDst(2) = Abs(aBMI(2) \ 2&)
        lBpp = (aBMI(3) And &HFF0000) \ &H10000 ' get bitcount
        pvSrcBits = 40&                         ' start tracking bits location
        If lBpp = 16& Or lBpp = 32& Then        ' shouldn't apply for icons, but easy enough check
            If aBMI(4) = 3 Then                 ' biCompression=BI_BITFIELDS
                pvSrcBits = pvSrcBits + 12&     ' if so, add 12 bytes to bits location
                CopyMemory aBMI(40), ByVal zzSafeOffset32(ColorSource, 40), 12&
            End If
        End If
        If lBpp < 9 Then                        ' get palette size & colors
            If aBMI(8) = 0 Then X = (2 ^ lBpp) * 4& Else X = aBMI(8) * 4&
            CopyMemory aBMI(pvSrcBits), ByVal zzSafeOffset32(ColorSource, pvSrcBits), X
            pvSrcBits = pvSrcBits + X           ' update bits location
        End If
        If MaskSource = 0& Then                 ' calculate offset for mask
            MaskSource = zzSafeOffset32(ColorSource, pvSrcBits + zzDWordAlign(lBpp, aDst(1)) * aDst(2))
        End If                                  ' set location for bits & change height to half
        pvSrcBits = zzSafeOffset32(ColorSource, pvSrcBits)
        CopyMemory ByVal zzSafeOffset32(ColorSource, 8), aDst(2), 4&
    Else
        If Not Manage = -2& Then            ' else special case, no picture returned, just hImage
            If srcIcon = 0& Then
                ReDim aICI(0 To 4)          ' create icon from passed bitmaps
                aICI(0) = Abs(isIcon): aICI(1) = xHotSpot: aICI(2) = yHotSpot
                aICI(3) = ColorSource: aICI(4) = MaskSource
                hIcon = CreateIconIndirect(aICI(0))
                If IconCx Then
                    hDib = CopyImage(hIcon, 2& - aICI(0), IconCx, IconCy, 0&)
                    DestroyIcon hIcon: hIcon = hDib: hDib = 0&
                End If
                Erase aICI()
                If hIcon = 0& Then Exit Function
                Set tPic = zzHandleToStdPicture(hIcon, vbPicTypeIcon)
                If Not Manage = mgtEnhanced Then GoTo ExitRoutine
            End If
        End If
        hDC = GetDC(0&)
        ReDim aBMI(0 To 268): aBMI(0) = 40  ' sized large enough for 8bpp w/256 color palette
        GetDIBits hDC, ColorSource, 0&, 0&, ByVal 0&, aBMI(0), 0&   ' get header
        aDst(1) = aBMI(1): aDst(2) = Abs(aBMI(2))
        If ColorSource = MaskSource Then aDst(2) = aDst(2) \ 2&     ' adjust when B&W
        lBpp = (aBMI(3) And &HFF0000) \ &H10000                     ' get bitcount
        If lBpp < 9& Then
            X = aBMI(8): Y = aBMI(9)                                ' these are erased, so cache them
            GetDIBits hDC, ColorSource, 0&, 0&, ByVal 0&, aBMI(0), 0& ' get palette colors
            aBMI(8) = X: aBMI(9) = Y                                ' restore erased values
        ElseIf aBMI(4) = 3 Then                                     ' compression=BI_BITFIELDS
            GetDIBits hDC, ColorSource, 0&, 0&, ByVal 0&, aBMI(0), 0&   ' get header
        End If
    End If
    
    If hDC = 0& Then hDC = GetDC(0&)                                ' create DIB
    hDib = CreateDIBSection(hDC, aDst(0), 0&, pvBits, 0&, 0&)
    If hDib = 0& Then
        If SourceArraySize Then CopyMemory ByVal zzSafeOffset32(ColorSource, 8), aBMI(2), 4& ' restore original height
        ReleaseDC 0&, hDC: Exit Function
    End If
    
    If SourceArraySize Then     ' set DIB pixels from array
        SetDIBits hDC, hDib, 0&, aDst(2), ByVal pvSrcBits, ByVal ColorSource, 0&
        CopyMemory ByVal zzSafeOffset32(ColorSource, 8), aBMI(2), 4& ' restore original height
    Else
        X = aDst(2)             ' set DIB pixels from bitmap
        If ColorSource = MaskSource Then aDst(2) = aBMI(2)
        GetDIBits hDC, ColorSource, 0&, X, ByVal pvBits, aDst(0), 0&
        If ColorSource = MaskSource Then aDst(2) = X
    End If

    If lBpp = 32& Then lFlags = lFlags Or zzValidateAlphaChannel(0&, hDib)
    If (lFlags And tfMaskTransp) = 0& Then ' process mask if not 32bpp with valid alpha channel
        lMskScan = zzDWordAlign(1, aDst(1))
        If SourceArraySize Then
            zzOverlayArray VarPtrArray(aMask), MaskSource, arrSafeArrayM(), lMskScan * aDst(2), True
        Else
            ReDim aMask(0 To lMskScan * aDst(2) - 1&)
            If ColorSource = MaskSource Then    ' b&w icon/cursor
                X = aDst(2)
            Else                                ' create b&w header
                aBMI(3) = &H10001: aBMI(4) = 0&: aBMI(5) = 0&: aBMI(8) = 2&: aBMI(9) = 2&
                aBMI(10) = 0&: aBMI(11) = vbWhite: aBMI(2) = aDst(2): X = 0&
            End If
            GetDIBits hDC, MaskSource, X, aDst(2), aMask(0), aBMI(0), 0&
        End If
        ReleaseDC 0&, hDC: hDC = 0&
        zzOverlayArray VarPtrArray(aColor), pvBits, arrSafeArrayC(), aDst(1) * aDst(2), False
        For Y = 0& To aDst(2) - 1&          ' for each scan line, set mask bits position
            lMskShift = 128&: pvSrcBits = Y * lMskScan
            For X = 1& To aDst(1)           ' for each pixel, set alpha byte as needed
                If (aMask(pvSrcBits) And lMskShift) = 0& Then
                    aColor(z) = aColor(z) Or &HFF000000
                ElseIf lBpp = 1& Then       ' adjust inverse pixel as needed
                    If aColor(z) = vbWhite Then aColor(z) = &HFF000000 Else lFlags = lFlags Or tfPicHasTransp
                Else
                    lFlags = lFlags Or tfPicHasTransp
                End If
                If lMskShift = 1& Then      ' reset mask shift & move mask pixel along
                    lMskShift = 128&: pvSrcBits = pvSrcBits + 1&
                Else
                    lMskShift = lMskShift \ 2&
                End If
                z = z + 1&                  ' move color pixel along
            Next
        Next                                ' clean up
        zzOverlayArray VarPtrArray(aColor), 0&, arrSafeArrayC(), 0&, False
        If SourceArraySize Then
            zzOverlayArray VarPtrArray(aMask), 0&, arrSafeArrayM(), 0&, True
        Else
            Erase aMask()
        End If
    Else
        ReleaseDC 0&, hDC: hDC = 0&
    End If
    Erase aBMI()
    If (lFlags And tfMaskTransp) Then lFlags = lFlags Or tfTransparent
        
    ' all of the above was to prep for GDI+ image creation... managed icons only
    GdipCreateBitmapFromScan0 aDst(1), aDst(2), 0&, PixelFormat32bppPARGB, 0&, hImage
    If hImage Then
        With bmpData
            .bpWidth = aDst(1): .bpHeight = aDst(2): .bpStride = .bpWidth * -4&
            .bpPixelFormat = PixelFormat32bppARGB
            .bpScan0Ptr = zzSafeOffset32(pvBits, (.bpHeight - 1&) * -.bpStride)
        End With
        GdipBitmapLockBits hImage, VarPtr(bmpData.bpLeft), ImageLockModeWrite Or ImageLockModeUserInputBuf, bmpData.bpPixelFormat, VarPtr(bmpData.bpWidth)
        GdipBitmapUnlockBits hImage, VarPtr(bmpData.bpWidth)
        If Not tPic Is Nothing Then
            Me.GetImageDimensions tPic, IconCx, IconCy
            If Not (IconCx = bmpData.bpWidth And IconCy = bmpData.bpHeight) Then
                DeleteObject hDib: hDib = 0&        ' no longer needed
                zzXeroxFormat Nothing, Nothing, 0&, False, IconCx, IconCy, mgtVbOnly, False, , , , hImage
            End If
        End If
    End If
    
ExitRoutine:
    If hDib Then DeleteObject hDib
    If srcIcon Then
        If aICI(3) Then DeleteObject aICI(3)
        If aICI(4) Then DeleteObject aICI(4)
    End If
    zzBitmapFromHICON = lFlags

End Function

Private Function zzBitmapFromTPG(hImage As Long, tPic As StdPicture, lFlags As Long) As Boolean

    ' Method returns stdPicture from multi-image format in alpha-supported format
    ' specifically: GIF, TIF, PNG
    
    Dim hBmp As Long
    
    If (lFlags And tfMaskTransp) Then
        zzGetCompatibleBmp hImage, tPic, (lFlags And tfPicHasTransp)
    Else
        zzFillImage hImage, hBmp, -1&
        If hBmp Then Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
    End If
    zzBitmapFromTPG = Not (tPic Is Nothing)

End Function

Private Function zzBitmapFromJPG(hImage As Long, tPic As StdPicture, bManaged As Boolean, bOConly As Boolean) As Boolean

    ' attempts to overcome two specific issues that VB can't handle
    ' 1) JPG in CMYK color space. VB fails to load these (invalid picture)
    ' 2) Non-standard orientation which is only available via the JPG's metadata which VB does not process
    ' bOConly simply checks for orientation correction
    
    Dim lSize As Long, lValue As Long
    Dim arrData() As Byte, hBmp As Long
    Dim lOrient As Long, tImage As Long
    Const PropertyTagOrientation  As Long = &H112&
    Const PixelFormatCMYK As Long = &H200F
    
    If bOConly = False Then
        GdipGetImagePixelFormat hImage, lValue
        If lValue = PixelFormatCMYK Then ' deal with CMYK color space
            If GdipCreateHBITMAPFromBitmap(hImage, hBmp, -1&) Then Exit Function
        End If
    End If
    If (bManaged Or bOConly) Then
        GdipGetPropertyItemSize hImage, PropertyTagOrientation, lSize
        If lSize = 18& Then
            ReDim arrData(0 To lSize - 1&)
            If GdipGetPropertyItem(hImage, PropertyTagOrientation, lSize, arrData(0)) = 0& Then
                CopyMemory lSize, arrData(4), 4&
                If lSize = 2& Then
                    CopyMemory lValue, arrData(8), 4&
                    If lValue = 3& Then
                        lOrient = arrData(16) Or arrData(17) * &H100&
                        Select Case lOrient
                        Case 2, 4: lOrient = lOrient + 2    ' RotateNoneFlipX, Rotate180FlipX
                        Case 6, 8: lOrient = lOrient - 5    ' Rotate90FlipNone, Rotate270FlipNone
                        Case 1, 3: lOrient = lOrient - 1    ' Rotate180FlipNone
                        Case 5, 7                           ' Rotate90FlipX, Rotate270FlipX
                        Case Else: lOrient = 0&             ' invalid value
                        End Select
                    End If
                End If
            End If
        End If
        If lOrient > 0& Then
            If bOConly Then zzBitmapFromJPG = True: GoTo ExitRoutine
            If hBmp Then   ' appears to be an issue flippping/rotating CMYK image, so...
                ' copy image to HBMP, then create new hImage from that
                GdipDisposeImage hImage: hImage = 0&
                If GdipCreateBitmapFromHBITMAP(hBmp, 0&, hImage) = 0& Then
                    DeleteObject hBmp: hBmp = 0&
                End If
            End If
            If hImage Then
                GdipImageRotateFlip hImage, lOrient
                GdipCreateHBITMAPFromBitmap hImage, hBmp, -1&
            End If
        End If
    End If
    
ExitRoutine:
    If hBmp Then
        Set tPic = zzHandleToStdPicture(hBmp, vbPicTypeBitmap)
        zzBitmapFromJPG = True
    End If

End Function

Private Function zzTIFfromAPNG(hImage As Long, ByVal pStream As Long, ByVal lSize As Long) As Long

    ' GDI+ can't load APNG format and a multi-frame/page PNG doesn't technically exist
    ' To work around this, here is what we do:
    '   Create a multi-page TIFF
    '   Render each APNG frame into its own TIFF page
    '   If navigating APNG, behind the scenes, really navigating multi-page TIFF
    
    ' To render the APNG frame, we need to rebuild each frame from an unrecognized
    '   fDat chunk to a recognized IDAT chunk. This is fairly easy, since the
    '   fDat chunk is simply an IDAT chunk with 4 extra bytes. Those extra bytes
    '   along with the different chunk name does require a new CRC calculation.
    ' Note: GDI+ doesn't error on invalid CRCs, but we recalculate CRC for
    '   completeness should GDI+ be updated in the future to honor the CRC values.

    Dim hGlobal As Long, hLock As Long, lPtr As Long
    Dim arrSafeArray() As Long, arrData() As Byte
    Dim lValue As Long, lFrame As Long
    Dim tStream As stdole.IUnknown, IStream As stdole.IUnknown
    Dim tPage As Long, tCanvas As Long, hGraphics As Long
    Dim arrBuffer() As Long, uEncCLSID(0 To 3) As Long
    Dim uEncParams As EncoderParameters, bmpErase As BitmapData
    Dim lDepth As Long, lCompress As Long, lParamVal As Long
    
    Const chnk_IDAT As Long = &H54414449 'Image data
    Const chnk_IEND As Long = &H444E4549 'End of Image
    Const MimeType As String = "image/tiff"
    Const TIFFCompress As String = "{E09D739D-CCD4-44EE-8EBA-3FBF8BE4FC58}"
    Const TIFFBitDepth As String = "{66087055-AD66-4C7C-9A18-38A2310B8337}"
    Const SaveFlag As String = "{292266fc-ac40-47bf-8cfc-a85b89a655de}"
    Const EncoderValueCompressionLZW As Long = &H2
    Const EncoderValueMultiFrame As Long = 18&
    Const EncoderValuePageDims As Long = 23&
    Const EncoderValueFlush As Long = 20&
    Const EncoderParameterValueTypeShort As Long = &H3&
    Const EncoderParameterValueTypeLong As Long = &H4&
    Const PropertyTagFrameDelay As Long = &H5100
    Const PropertyTagLoopCount As Long = &H5101
    
    hGlobal = GlobalAlloc(&H2, 0&)              ' create IStream for return image
    If hGlobal = 0& Then Exit Function
    CreateStreamOnHGlobal hGlobal, 1&, IStream
    If IStream Is Nothing Then
        GlobalFree hGlobal: Exit Function
    End If
    
    hGlobal = GlobalAlloc(&H2, lSize)           ' copy APNG source stream for "frame" stream
    If hGlobal = 0& Then Exit Function          ' this will be updated per APNG frame
    hLock = GlobalLock(hGlobal)
    If hLock = 0& Then
        GlobalFree hGlobal: Exit Function
    End If
    GetHGlobalFromStream pStream, lValue
    If lValue Then lPtr = GlobalLock(lValue)
    If lPtr = 0& Then
        GlobalUnlock hLock: GlobalFree hGlobal
        GoTo ExitRoutine
    End If
    CopyMemory ByVal hLock, ByVal lPtr, lSize
    GlobalUnlock lValue
    GlobalUnlock hGlobal
    
    CreateStreamOnHGlobal hGlobal, 1&, tStream  ' create the "frame" stream
    If tStream Is Nothing Then
        GlobalFree hGlobal: Exit Function
    End If
    pStream = ObjPtr(tStream)
    
    ' create our GDI+ canvas
    If GdipCreateBitmapFromScan0(m_APNGdat.Size(0), m_APNGdat.Size(1), 0&, PixelFormat32bppARGB, 0&, tCanvas) Then GoTo ExitRoutine
    
    GetHGlobalFromStream pStream, hGlobal
    If hGlobal = 0& Then Exit Function
    
    ' if code 2 (GIF code 3) exists, we'll need a buffer to keep previous frame data; do that...
    If (m_APNGdat.Flags And 1) Then ReDim arrBuffer(0 To m_APNGdat.Size(0) * m_APNGdat.Size(1))
    ' Don't let first frame have disposal code of 2. It's pointless
    If (m_APNGdat.Frames(0).Disposal And &HFF&) = 2 Then m_APNGdat.Frames(0).Disposal = (m_APNGdat.Frames(0).Disposal And &HFF00&) Or 1
    ' Don't let last frame have any disposal code either. It's pointless
    lFrame = m_APNGdat.FrameCount - 1&
    m_APNGdat.Frames(lFrame).Disposal = (m_APNGdat.Frames(lFrame).Disposal And &HFF00&)
    
    bmpErase.bpPixelFormat = PixelFormat32bppARGB
    For lFrame = 0& To m_APNGdat.FrameCount - 1&
        If lFrame = 0& And (m_APNGdat.Flags And 2) = 0& Then
            ' IDAT included in animation
            tPage = hImage
        Else ' when we convert fdAT to IDAT, we need to ensure a proper CRC32 value. Do that now
            hLock = GlobalLock(hGlobal): If hLock = 0& Then GoTo ExitRoutine
            zzOverlayArray VarPtrArray(arrData), hLock, arrSafeArray(), lSize, True
            With m_APNGdat.Frames(lFrame)                                       ' update the stream
                lPtr = m_APNGdat.Offset                                         ' location in stream to start update
                CopyMemory arrData(16), zzReverseLong(.Size(2)), 4&             ' make png bounds same size as frame
                CopyMemory arrData(20), zzReverseLong(.Size(3)), 4&
                For lValue = 0& To .DatCount - 1&                               ' build IDAT from fDat
                    CopyMemory arrData(lPtr), zzReverseLong(.fDat(lValue).length), 4& ' insert chunk length
                    CopyMemory arrData(lPtr + 4), chnk_IDAT, 4&                 ' and chunk name as IDAT
                    CopyMemory arrData(lPtr + 8&), arrData(.fDat(lValue).Pointer), .fDat(lValue).length
                    CopyMemory arrData(lPtr - 4&), zzCRCArray(arrData(), lPtr + 4&, .fDat(lValue).length + 4&, 0&), 4&
                    lPtr = lPtr + .fDat(lValue).length + 12&                    ' ^ copy chunk
                Next
            End With
            CopyMemory arrData(lPtr), 0&, 4&                                     ' append IEND
            CopyMemory arrData(lPtr + 4&), chnk_IEND, 4&                         ' and done with this frame
            CopyMemory arrData(lPtr + 8&), &H826042AE, 4&                        ' CRC value for IEND
            zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), 0&, True    ' remove overlay
            GlobalUnlock hGlobal
            CallThunk f_MsgAddr, pStream, msgStrmSetSeek, VarPtr(0@)
            If GdipLoadImageFromStream(pStream, tPage) Then GoTo ExitRoutine     ' abort on error
        End If
        
        If (m_APNGdat.Frames(lFrame).Disposal And &HFF&) = 2 Then
            ' copy area to be rendered; will be restored after frame is drawn
            With bmpErase
                .bpLeft = 0&: .bpWidth = m_APNGdat.Size(0)
                .bpTop = m_APNGdat.Frames(lFrame).Size(1)
                .bpHeight = m_APNGdat.Frames(lFrame).Size(3)
                .bpScan0Ptr = VarPtr(arrBuffer(0))
                .bpStride = .bpWidth * 4&
                If GdipBitmapLockBits(tCanvas, VarPtr(.bpLeft), ImageLockModeRead Or ImageLockModeUserInputBuf, .bpPixelFormat, VarPtr(.bpWidth)) Then GoTo ExitRoutine
                GdipBitmapUnlockBits tCanvas, VarPtr(.bpWidth)
                .bpReserved = 0&
            End With
        End If
        
        If GdipGetImageGraphicsContext(tCanvas, hGraphics) Then GoTo ExitRoutine
        GdipSetCompositingMode hGraphics, ((m_APNGdat.Frames(lFrame).Disposal \ &H100) Xor 1&)
        With m_APNGdat.Frames(lFrame)
            GdipDrawImageRectRectI hGraphics, tPage, .Size(0), .Size(1), .Size(2), .Size(3), 0&, 0&, .Size(2), .Size(3), SrcUnit_Pixel, 0&, 0&, 0&
        End With
        GdipDeleteGraphics hGraphics: hGraphics = 0&
        
        If lFrame = 0& Then                             ' setup encoding parameters
            If Not tPage = hImage Then GdipDisposeImage tPage
            tPage = 0&: uEncParams.Count = 3&
            With uEncParams.Parameter(0)                ' compression
                lCompress = EncoderValueCompressionLZW
                .NumberOfValues = 1
                .Type = EncoderParameterValueTypeLong
                 IIDFromString StrPtr(TIFFCompress), .GUID(0)
                .Value = VarPtr(lCompress)
            End With
            With uEncParams.Parameter(1)                ' bit depth
                lDepth = 32&
                .NumberOfValues = 1
                .Type = EncoderParameterValueTypeLong
                IIDFromString StrPtr(TIFFBitDepth), .GUID(0)
               .Value = VarPtr(lDepth)
            End With
            With uEncParams.Parameter(2)                ' multi-page
                lParamVal = EncoderValueMultiFrame      ' value will change 3 times
                .NumberOfValues = 1
                .Type = EncoderParameterValueTypeLong
                IIDFromString StrPtr(SaveFlag), .GUID(0)
               .Value = VarPtr(lParamVal)
            End With
            ' get TIFF CLISD & save 1st frame to stream
            If zzGetEncoderClsID(MimeType, uEncCLSID()) = -1& Then GoTo ExitRoutine
            If GdipSaveImageToStream(tCanvas, IStream, uEncCLSID(0), uEncParams) Then GoTo ExitRoutine
        
        Else
            GdipDisposeImage tPage: tPage = 0&          ' add frame to the stream
            lParamVal = EncoderValuePageDims
            If GdipSaveAddImage(tCanvas, tCanvas, uEncParams) Then GoTo ExitRoutine
        End If
        
        ' post-frame actions
        Select Case (m_APNGdat.Frames(lFrame).Disposal And &HFF&)
        Case 0  ' do nothing, drawing remains unchanged
        Case 1  ' blank out frame's area. Note: Same as GIF's Code 2
            If GdipGetImageGraphicsContext(tCanvas, hGraphics) Then GoTo ExitRoutine
            With m_APNGdat.Frames(lFrame)
                GdipSetClipRectI hGraphics, .Size(0), .Size(1), .Size(2), .Size(3), 0&
                GdipGraphicsClear hGraphics, 0&
            End With
            GdipDeleteGraphics hGraphics: hGraphics = 0&
        Case 2  ' copy previously cached scanlines.  Note: Same as GIF's Code 3
            With bmpErase
                If GdipBitmapLockBits(tCanvas, VarPtr(.bpLeft), ImageLockModeWrite Or ImageLockModeUserInputBuf, .bpPixelFormat, VarPtr(.bpWidth)) Then GoTo ExitRoutine
                GdipBitmapUnlockBits tCanvas, VarPtr(.bpWidth)
                .bpReserved = 0&
            End With
        End Select
    Next
    
    Erase arrBuffer()                                   ' clean up/finalize
    Set tStream = Nothing
    lParamVal = EncoderValueFlush                       ' close the TIF
    If GdipSaveAdd(tCanvas, uEncParams) = 0& Then
        GdipDisposeImage tCanvas: tCanvas = 0&
        pStream = ObjPtr(IStream)
        CallThunk f_MsgAddr, pStream, msgStrmSetSeek, VarPtr(0@)
        If GdipLoadImageFromStream(pStream, tPage) = 0& Then ' create TIFF GDI+ image
            ' now store frame intervals and loop count on the image
            ReDim arrBuffer(0 To m_APNGdat.FrameCount + 3&)
            arrBuffer(3) = VarPtr(arrBuffer(4))         ' location in array for property data
            If m_APNGdat.Loops > 0& Then
                arrBuffer(0) = PropertyTagLoopCount
                arrBuffer(1) = 2&                       ' loop count always 2 bytes
                arrBuffer(2) = EncoderParameterValueTypeShort
                arrBuffer(4) = m_APNGdat.Loops
                GdipSetPropertyItem tPage, arrBuffer(0)
            End If
            ' now the frame durations, see loop count info above for array item descriptions
            arrBuffer(0) = PropertyTagFrameDelay
            arrBuffer(1) = m_APNGdat.FrameCount * 4&
            arrBuffer(2) = EncoderParameterValueTypeLong
            For lFrame = 0& To m_APNGdat.FrameCount - 1&
                arrBuffer(lFrame + 4&) = m_APNGdat.Frames(lFrame).Delay
            Next
            GdipSetPropertyItem tPage, arrBuffer(0)
            Erase arrBuffer()
            zzTIFfromAPNG = tPage: tPage = 0&
        End If
    End If
    
ExitRoutine:
    If hGraphics Then GdipDeleteGraphics hGraphics
    If tPage Then GdipDisposeImage tPage
    If tCanvas Then GdipDisposeImage tCanvas
    
End Function

Private Function zzValidateAPNG(pStream As Long, lSize As Long, Width As Long, Height As Long) As Long

    ' Routine will minimally parse a PNG file to determine if it's in APNG format
    ' The class EnableAPNGSupport property must be set to true
    
    ' https://wiki.mozilla.org/APNG_Specification
    ' If the PNG is not APNG, routine exits quickly. Otherwise, the entire PNG is scanned
    '   to collect information that will be used to create a GDI+ compatible APNG which,
    '   in reality, will be a multi-page TIFF behind the scenes

    Dim hGlobal As Long, hLock As Long, lPtr As Long
    Dim arrSafeArray() As Long, arrData() As Byte
    Dim n As Long, p As Long, lValue As Long
    Dim chunkLen As Long, chunkName As Long
    
    Const CRCpolynomial As Long = &HEDB88320
    Const chnk_IHDR As Long = &H52444849 'Image header
    Const chnk_IDAT As Long = &H54414449 'Image data
    Const chnk_IEND As Long = &H444E4549 'End of Image
    ' //// APNG chunk names
    Const chnk_acTL = &H4C546361    ' Animation Ctrl Chunk: must appear before first IDAT
    Const chnk_fcTL = &H4C546366    ' Frame Ctrl Chunk: if before IDAT then IDAT is first frame; preceedes fdAT for additional frames
    Const chnk_fdAT = &H54416466    ' Frame Data Chunk. Same as IDAT except additonal 4 byte sequence identifier prepended
    
    GetHGlobalFromStream pStream, hGlobal
    If hGlobal = 0& Then Exit Function
    hLock = GlobalLock(hGlobal)
    If hLock = 0& Then Exit Function
    
    ReDim m_CRC32LUT(0 To 255)      ' create a CRC lookup table (LUT) for validating PNG CRC chunks
    For n = 0& To 255&
        lValue = n
        For p = 8& To 1& Step -1&
            If (lValue And 1&) Then
                lValue = (((lValue And &HFFFFFFFE) \ 2&) And &H7FFFFFFF) Xor CRCpolynomial
            Else
                lValue = ((lValue And &HFFFFFFFE) \ 2&) And &H7FFFFFFF
            End If
        Next
        m_CRC32LUT(n) = lValue
    Next
    With m_APNGdat
        .Frame = 0&
        .FrameCount = 0&
        .Loops = 0&
        .Offset = 0&
        Erase .Frames()
        .Size(0) = Width: .Size(1) = Height
        .Flags = 0&
    End With
    
    zzOverlayArray VarPtrArray(arrData), hLock, arrSafeArray(), lSize, True
    lPtr = 8&             ' skip the PNG signature, start at IHDR chunk
    Do ' scan & minimally process PNG file for eventual hand off to GDI+
        ' Chunks consist of 4 bytes for the length of the chunk
        '                 + 4 bytes for chunk name
        '                 + n bytes for the chunk(s)
        '                 + 4 bytes for a CRC value (crc includes: data chunks + name chunk)
        CopyMemory chunkLen, arrData(lPtr), 4& ' length of the current chunk
        chunkLen = zzReverseLong(chunkLen)  ' longs are big endian, need little endian for Windows
        If chunkLen < 0& Then Exit Do       ' if corrupted data, abort. Note: zero-length chunk is valid
        
        CopyMemory chunkName, arrData(lPtr + 4&), 4& ' extract the chunk name and then the CRC value
        CopyMemory lValue, arrData(lPtr + chunkLen + 8&), 4&
        
        Select Case chunkName
        ' when scanning, we are focusing on IDAT & fdAT chunks within the stream
        ' These offsets will be cached so they can be inserted into a new stream for GDI+
        ' A lot of work to make GDI+ process the APNG, but worth it. GDI+ is much faster than manual processing
        
        Case chnk_IDAT ' APNG terms: Default image to be displayed if parser does not support APNG
                       '             Also the 1st frame in animated PNG only if a fcTL and acTL preceeded this
            If m_APNGdat.FrameCount < 2& Then Exit Do  ' we do not have an APNG file or it's invalid
            If (m_APNGdat.Frame And &HFFFF&) = 1& Then ' will be the first frame
                With m_APNGdat.Frames(0)
                    ReDim Preserve .fDat(0 To .DatCount)
                    .fDat(.DatCount).length = chunkLen
                    .fDat(.DatCount).Pointer = lPtr + 8&
                    .DatCount = .DatCount + 1&
                End With
            Else                    ' skipped; is default PNG for non-APNG parsers, but not for APNG parsers
                m_APNGdat.Flags = m_APNGdat.Flags Or &H2    ' IDAT not included in the animation
            End If
            If m_APNGdat.Offset = 0& Then m_APNGdat.Offset = lPtr  ' location where IDATs start
            
        Case chnk_fdAT ' APNG terms: Same as IDAT except it has an additional 4 byte prefix indicating sequence number
            If zzAPNGchunk_fdAT(arrData(), chunkLen, lPtr + 4&, lValue) Then Exit Do
            With m_APNGdat.Frames(m_APNGdat.Frame \ &H10000 - 1&)
                ReDim Preserve .fDat(0 To .DatCount)
                .fDat(.DatCount).length = chunkLen - 4&
                .fDat(.DatCount).Pointer = lPtr + 12&
                .DatCount = .DatCount + 1&
            End With
            
        Case chnk_acTL ' APNG terms: animated control chunk -- if present, then an APNG format & must exist before IDAT
            ' process this chunk. Contains frame & loop count
            If zzAPNGchunk_acTL(arrData(), chunkLen, lPtr + 4&, lValue) Then Exit Do
            
        Case chnk_fcTL ' APNG terms: frame control chunk -- one per frame & preceedes series of fdAT chunks, must not preceed acTL
            ' notes: if IDAT is 1st frame, no fdAT will exist btwn this fcTL and next fcTL
            '        if IDAT is not 1st frame, this fcTL occurred after IDAT
            '        fdAT chunks can be separated by other ancillary chunks
            If zzAPNGchunk_fcTL(arrData(), chunkLen, lPtr + 4&, lValue) Then Exit Do
                
        Case chnk_IEND ' APNG/PNG: the end of the stream. If additonal bytes follow, they are not used
            zzValidateAPNG = m_APNGdat.FrameCount
            Exit Do
            
        Case Else ' other PNG chunks
            ' if they appear before last IDAT they'll be included in the IStream we'll create
            ' otherwise they will be truncated. Any chunks appearing after last IDAT and before IEND
            ' are ancillary and not needed for proper rendering of PNG (generally, they are text-type chunks)
            ' fdAT & all but 1 max fcTL chunks will appear between last IDAT and IEND,
            ' so they will be stripped out too & is not an issue for what we are doing.
        End Select
        lPtr = lPtr + chunkLen + 12& ' move to next chunk position in the stream
    Loop
    

ExitRoutine:
    If hLock Then
        zzOverlayArray VarPtrArray(arrData), 0&, arrSafeArray(), lSize, False
        GlobalUnlock hGlobal
    End If

End Function

Private Function zzCRCArray(theArray() As Byte, StartPos As Long, CRCLen As Long, curCRCValue As Long) As Long

    ' Standard CRC algorithm, converting result to newtwork byte order
    ' Returns -1 failure or 0 success, or the CRC value depending on parameters...
    
    ' This has been specifically modified to replicate zLIB's CRC32 function
    ' Params:
    '   theArray(): any initialized byte array
    '   StartPos: the 1st byte position to begin CRC
    '   CRCLen: how many bytes to CRC
    '   curCRCValue: If provided, compare this to result for validation
    '                If not provided, return the CRC value
    
    Dim i As Long, crc32val As Long, lPtr As Long
    
    crc32val = &HFFFFFFFF 'start with -1&
    For i = StartPos To StartPos + CRCLen - 1&
        lPtr = (crc32val And &HFF) Xor theArray(i)
        crc32val = (((crc32val And &HFFFFFF00) \ &H100&) And &HFFFFFF) Xor m_CRC32LUT(lPtr)
    Next
    zzCRCArray = zzReverseLong(Not (crc32val)) ' change result to newtwork byte order
    If curCRCValue Then zzCRCArray = (zzCRCArray = curCRCValue) 'return either 0 or -1

End Function

Private Function zzAPNGchunk_acTL(Stream() As Byte, bufLen As Long, StreamOffset As Long, crcValue As Long) As Long
'    0   num_frames     (unsigned int)    Number of frames
'    4   num_plays      (unsigned int)    Number of times to loop this APNG.  0 indicates infinite looping.
'   note: StreamOffset is 4 bytes before this chunk's data begins
    On Error Resume Next
    Dim lRtn As Long, lValue As Long
    
    If m_APNGdat.FrameCount Then
        lRtn = 1& ' this chunk already processed; there cannot be more than one of these
    Else
        lRtn = Not (zzCRCArray(Stream(), StreamOffset, bufLen + 4&, crcValue))
        If lRtn = 0& Then
            CopyMemory m_APNGdat.FrameCount, Stream(StreamOffset + 4&), 4&
            m_APNGdat.FrameCount = zzReverseLong(m_APNGdat.FrameCount)
            If m_APNGdat.FrameCount < 2& Then ' must =>1 per specifications else invalid aPNG
                lRtn = 1&
            ElseIf m_APNGdat.FrameCount > &HFFF& Then ' way too big; gotta be something wrong
                lRtn = 1&
            Else
                ReDim Preserve m_APNGdat.Frames(0 To m_APNGdat.FrameCount - 1&)
                CopyMemory m_APNGdat.Loops, Stream(StreamOffset + 8&), 4&
                m_APNGdat.Loops = zzReverseLong(m_APNGdat.Loops)
                If m_APNGdat.Loops < 0& Then m_APNGdat.Loops = 0& ' zero=indefinite looping else exact loop count
            End If
        End If
    End If
    zzAPNGchunk_acTL = lRtn
End Function

Private Function zzAPNGchunk_fcTL(Stream() As Byte, bufLen As Long, StreamOffset As Long, crcValue As Long) As Long
'    0    sequence_number       (unsigned int)   Sequence number of the animation chunk, starting from 0
'    4    width                 (unsigned int)   Width of the following frame
'    8    height                (unsigned int)   Height of the following frame
'   12    x_offset              (unsigned int)   X position at which to render the following frame
'   16    y_offset              (unsigned int)   Y position at which to render the following frame
'   20    delay_num             (unsigned short) Frame delay fraction numerator
'   22    delay_den             (unsigned short) Frame delay fraction denominator
'   24    dispose_op            (byte)           Type of frame area disposal to be done after rendering this frame
'   25    blend_op              (byte)           Type of frame area rendering for this frame
'   note: StreamOffset is 4 bytes before this chunk's data begins
    On Error Resume Next
    Dim lRtn As Long, lValue As Long, Sequence As Long
    
    ' per APNG specs. the acTL chunk (tells us how many frames) is not guaranteed to precede
    ' the first fcTL chunk. This is handled here
    
    If m_APNGdat.FrameCount = 0& Then ' acTL chunk not processed yet
        ReDim m_APNGdat.Frames(0 To 0)
    End If
    lRtn = Not (zzCRCArray(Stream(), StreamOffset, bufLen + 4&, crcValue))
    If lRtn = 0& Then
        CopyMemory Sequence, Stream(StreamOffset + 4&), 4&
        Sequence = zzReverseLong(Sequence)
        If Sequence = (m_APNGdat.Frame And &HFFFF&) Then
            m_APNGdat.Frame = (m_APNGdat.Frame \ &H10000 + 1&) * &H10000 Or Sequence + 1& ' set next expected sequence & next frame
            With m_APNGdat.Frames(m_APNGdat.Frame \ &H10000 - 1&)
                CopyMemory .Size(2), Stream(StreamOffset + 8&), 4&
                .Size(2) = zzReverseLong(.Size(2))
                CopyMemory .Size(0), Stream(StreamOffset + 16&), 4&
                .Size(0) = zzReverseLong(.Size(0))
                If .Size(0) + .Size(2) > m_APNGdat.Size(0) Or .Size(2) < 1& Or .Size(0) < 0& Then
                    lRtn = 1&
                Else
                    CopyMemory .Size(3), Stream(StreamOffset + 12&), 4&
                    .Size(3) = zzReverseLong(.Size(3))
                    CopyMemory .Size(1), Stream(StreamOffset + 20&), 4&
                    .Size(1) = zzReverseLong(.Size(1))
                    If .Size(1) + .Size(3) > m_APNGdat.Size(1) Or .Size(3) < 1& Or .Size(1) < 0& Then
                        lRtn = 1&
                    Else
                        CopyMemory .Delay, Stream(StreamOffset + 24&), 4&
                        .Delay = zzReverseLong(.Delay)
                        ' denominator determines fraction: 100ths, 1000ths, 10ts, etc
                        ' convert to 100ths of seconds for this class
                        Select Case (.Delay And &HFFFF&)
                        Case 1000:   .Delay = (.Delay \ &H10000) / 10&
                        Case 0, 100: .Delay = .Delay \ &H10000
                        Case Else:   .Delay = (.Delay \ &H10000) / ((.Delay And &HFFFF&) / 100&)
                        End Select
                        .Disposal = Stream(StreamOffset + 29&) * &H100 Or Stream(StreamOffset + 28&)
                        If Stream(StreamOffset + 28&) = 2 Then m_APNGdat.Flags = m_APNGdat.Flags Or 1&
                        ' disposal codes
                        '0 = APNG_DISPOSE_OP_NONE: no disposal is done on this frame before rendering the next; the contents of the output buffer are left as is.
                        '1 = APNG_DISPOSE_OP_BACKGROUND: the Frame 's region of the output buffer is to be cleared to fully transparent black before rendering the next frame.
                        '2 = APNG_DISPOSE_OP_PREVIOUS: the Frame 's region of the output buffer is to be reverted to the previous contents before rendering the next frame.
                        ' ROP codes
                        '0   APNG_BLEND_OP_SOURCE ... completely overwrites previous frame
                        '1   APNG_BLEND_OP_OVER ... blended onto previous frame
                    End If
                End If
            End With
        Else
            lRtn = 1&   ' per APNG specs, if out-of-order sequence, treat as error
        End If
    End If
    zzAPNGchunk_fcTL = lRtn

End Function

Private Function zzAPNGchunk_fdAT(Stream() As Byte, bufLen As Long, StreamOffset As Long, crcValue As Long) As Long

'    0    sequence_number       (unsigned int)   Sequence number of the animation chunk, starting from 0
'    4    frame_data            X bytes          Frame data for this frame
'   note: StreamOffset is 4 bytes before this chunk's data begins
    Dim lRtn As Long, lValue As Long, Sequence As Long
    On Error Resume Next
    
    If m_APNGdat.FrameCount = 0& Then
        lRtn = 1&                   ' no acTL chunk processed; this chunk is invalid
    Else
        lRtn = Not (zzCRCArray(Stream(), StreamOffset, bufLen + 4&, crcValue))
        If lRtn = 0& Then
            CopyMemory Sequence, Stream(StreamOffset + 4&), 4&
            Sequence = zzReverseLong(Sequence)
            If Sequence = (m_APNGdat.Frame And &HFFFF&) Then
                m_APNGdat.Frame = (m_APNGdat.Frame And &HFFFF0000) Or Sequence + 1& ' set next expected sequence
            Else
                lRtn = 1&   ' per APNG specs, if out-of-order sequence, treat as error
            End If
        End If
    End If
    zzAPNGchunk_fdAT = lRtn

End Function

Private Sub zzMakeWMFplaceable(tPic As StdPicture, hImage As Long)

    ' attempts to add WMF header to WMF without header

    Dim hHandle As Long, lCount As Long
    Dim gStream As stdole.IUnknown
    Dim cx As Long, cy As Long
    Dim hLock As Long, hGlobal As Long
    
    GdipGetHemfFromMetafile hImage, hHandle             ' convert to GDI WMF
    GdipDisposeImage hImage: hImage = 0&
    lCount = GdipEmfToWmfBits(hHandle, 0&, 0&, 8&, 0&)  ' 8& = MM_ANISOTROPIC; get size of bits
    If lCount Then
        hGlobal = GlobalAlloc(&H2, lCount + 22&)
        If hGlobal = 0& Then Exit Sub
        hLock = GlobalLock(hGlobal)
        If hLock = 0& Then GoTo ExitRoutine
        
        ' transfer bits, offsetting for placeable header
        If GdipEmfToWmfBits(hHandle, lCount, zzSafeOffset32(hLock, 22&), 8&, 0&) Then
            DeleteEnhMetaFile hHandle: hHandle = 0&
            If Screen.Width > Screen.Height Then
                cx = 256& * Screen.TwipsPerPixelX
                cy = (Screen.Height / Screen.Width) * cx
            Else
                cy = 256& * Screen.TwipsPerPixelY
                cx = (Screen.Width / Screen.Height) * cy
            End If                                                  ' add placeable header
            CopyMemory ByVal hLock, &H9AC6CDD7, 4&                  ' WMF magic number
            CopyMemory ByVal zzSafeOffset32(hLock, 4&), 0@, 6&      ' Handle, Left, Top
            CopyMemory ByVal zzSafeOffset32(hLock, 10&), cx, 2&     ' Right
            CopyMemory ByVal zzSafeOffset32(hLock, 12&), cy, 2&     ' Bottom
            CopyMemory ByVal zzSafeOffset32(hLock, 14&), 1440, 2&   ' units per inch
            CopyMemory ByVal zzSafeOffset32(hLock, 16&), 0&, 4&     ' reserved
            lCount = 22289& Xor cx Xor cy Xor 1440&
            ' ^^ 22289 = 0 Xor &HCDD7& Xor &H9AC6&
            CopyMemory ByVal zzSafeOffset32(hLock, 20&), lCount, 2& ' checksum
            GlobalUnlock hGlobal: hLock = 0&
            CreateStreamOnHGlobal hGlobal, 1&, gStream
            If gStream Is Nothing Then
                GlobalFree hGlobal
            Else
                Set tPic = zzIStreamToPicture(ObjPtr(gStream), False, 0&)
            End If
        End If
    End If

ExitRoutine:
    If hHandle Then DeleteEnhMetaFile hHandle
    If hLock Then
        GlobalUnlock hGlobal
        GlobalFree hGlobal
    End If
    
End Sub

Private Function zzIStreamFromSource(sFileName As String, arrData() As Byte, _
                                    hGlobal As Long, lSize As Long, _
                                    Optional arrStart As Long, Optional arrSize As Long) As Boolean

    ' simply reads a file (unicode-supported) or array and transfers data to a stream

    Dim lRead As Long, hFile As Long, hLock As Long

    Const GENERIC_READ As Long = &H80000000
    Const OPEN_EXISTING = &H3
    Const FILE_SHARE_READ = &H1
    Const FILE_ATTRIBUTE_ARCHIVE As Long = &H20
    Const FILE_ATTRIBUTE_HIDDEN As Long = &H2
    Const FILE_ATTRIBUTE_READONLY As Long = &H1
    Const FILE_ATTRIBUTE_SYSTEM As Long = &H4
    Const FILE_ATTRIBUTE_NORMAL = &H80&
    Const LR_LOADFROMFILE As Long = &H10
   
    If sFileName = vbNullString Then
        On Error Resume Next
        lSize = Abs(UBound(arrData) - LBound(arrData)) + 1&
        If Err Then         ' uninitialized array
            Err.Clear
            On Error GoTo 0
            Exit Function
        End If              ' check for: UBound=-1 & LBound=0
        If LBound(arrData) > UBound(arrData) Then Exit Function
        If arrSize = 0& Then arrSize = lSize: arrStart = LBound(arrData)
        hGlobal = GlobalAlloc(&H2&, arrSize)
        If hGlobal Then
            hLock = GlobalLock(hGlobal)
            If hLock Then CopyMemory ByVal hLock, arrData(arrStart), arrSize
        End If
        On Error GoTo 0
    
    Else
        ' attempt to open the file with just read access
        lRead = FILE_ATTRIBUTE_ARCHIVE Or FILE_ATTRIBUTE_HIDDEN Or FILE_ATTRIBUTE_NORMAL _
                Or FILE_ATTRIBUTE_READONLY Or FILE_ATTRIBUTE_SYSTEM
        hFile = CreateFileW(StrPtr(sFileName), GENERIC_READ, FILE_SHARE_READ, ByVal 0&, OPEN_EXISTING, lRead, 0&)
        If hFile = -1& Then Exit Function               ' failure
        lSize = GetFileSize(hFile, 0&)                  ' create stream of equal file size
        If lSize > 0& Then
            hGlobal = GlobalAlloc(&H2&, lSize)
            If hGlobal Then
                hLock = GlobalLock(hGlobal)             ' lock it for writing
                If hLock Then ReadFile hFile, ByVal hLock, lSize, lRead, ByVal 0&
            End If
        End If
        CloseHandle hFile
        If (lRead < lSize Or hGlobal = 0&) Then
            If hLock Then GlobalUnlock hGlobal: hLock = 0&
        End If
    End If
    
    If hLock Then                                       ' success
        GlobalUnlock hGlobal
        zzIStreamFromSource = True
    ElseIf hGlobal Then                                 ' failure
        GlobalFree hGlobal: hGlobal = 0&
    End If

End Function

Private Function zzReverseLong(ByVal inLong As Long) As Long

    ' fast function to reverse a long value from big endian to little endian
    ' PNG files contain reversed longs, as do ID3 v3,4 tags
    zzReverseLong = _
      (((inLong And &HFF000000) \ &H1000000) And &HFF&) Or _
      ((inLong And &HFF0000) \ &H100&) Or _
      ((inLong And &HFF00&) * &H100&) Or _
      ((inLong And &H7F&) * &H1000000)
    If (inLong And &H80&) Then zzReverseLong = zzReverseLong Or &H80000000
    
End Function

Private Function zzXeroxFormat(thePicture As StdPicture, rtnPic As StdPicture, _
                                rtnImage As Long, SendToEvents As Boolean, _
                                Width As Long, Height As Long, _
                                Manage As ManagementStyle, bAsIcon As Boolean, _
                                Optional AlphaTypePARGB As Boolean = True, _
                                Optional FillTransparency As Boolean, _
                                Optional FillTransparencyColor As Long, _
                                Optional srcHImage As Long) As Long
    ' a bit complex due to various options...
    ' thePicture is what should be resized/copy/converted
    ' rtnPic is the resized picture
    ' rtnImage is GDI+ himage returned, depends on Manage parameter
    ' Width,Height self-explanatory
    ' Manage set if to be managed
    ' srcHImage is passed only if it should be resized and replaced
    ' other parameters self-explanatory

    Dim tDC As Long, hDC As Long, hHandle As Long
    Dim lValue As Long, hGraphics As Long
    Dim uBMP As BITMAP, fRect(0 To 3) As Single
    Dim hImage As Long, hAttr As Long, lFlags As Long
    Dim X As Long, Y As Long, m As Long
    Dim arrSafeArray() As Long, arrBMI() As Long
    Dim arrDataL() As Long, arrData() As Byte
    Dim IStream As stdole.IUnknown
    Dim tPic As StdPicture, iPic As IPicture
    Dim mskShift As Long, mskPtr As Long, mskScanWidth As Long
    Dim lState As Long, bmpData As BitmapData
        ' 0x0001 has transparency
        ' 0x0002 metafile
        ' 0x0004 managed
        ' 0x0008 GIF
        ' 0x0010 manged hImage
        ' 0x0020 passed hSrcImage
    If Width < 1& And Height < 1& Then
        Me.GetImageDimensions thePicture, Width, Height
    ElseIf Height < 1& Then
        Me.GetImageDimensions thePicture, 0&, Height
    ElseIf Width < 1& Then
        Me.GetImageDimensions thePicture, Width, 0&
    End If
    
    If srcHImage Then
        hImage = srcHImage
        lState = Abs(Not zzValidateAlphaChannel(hImage, 0&) = 0&) Or &H30
    Else
        lState = Abs(CallThunk(f_MsgAddr, ObjPtr(thePicture), msgObjPtrIndex) > 0&) * 4&
        If SendToEvents = True Then
            If lState Then
                If (CallThunk(f_MsgAddr, ObjPtr(thePicture), msgObjGetFlags) And tfCBflags) = 0& Then _
                    SendToEvents = False
            Else
                SendToEvents = False
            End If
        End If
    End If
    
    If SendToEvents = False And srcHImage = 0& Then
        If (thePicture.Type = vbPicTypeMetafile Or thePicture.Type = vbPicTypeEMetafile) Then
            lState = lState Or 3&     ' WMF/EMF + transparency (assumed)
        Else
            If (lState And 4&) Then hImage = CallThunk(f_MsgAddr, ObjPtr(thePicture), msgObjGetHImage)
            If hImage Then
                If Me.HasTransparency(thePicture) Then lState = lState Or tfTransparent
                lState = lState Or &H10
            Else
                If thePicture.Type = vbPicTypeIcon Then
                    lValue = zzBitmapFromHICON(Nothing, thePicture.Handle, hImage, -2&, 0&, 0&)
                    If hImage = 0& Then Exit Function
                    If (lValue And tfMaskTransp) Then lState = lState Or tfTransparent
                    
                ElseIf thePicture.Type = vbPicTypeBitmap Then
                    If (lState And 4&) = 0& Then                ' unmanaged
                        Set iPic = thePicture
                        If (iPic.Attributes And PICTURE_TRANSPARENT) = 0& Then  ' no transparency
                            GetObjectA thePicture.Handle, 24&, uBMP
                        Else
                            lState = lState Or 9&               ' transparency + GIF
                        End If
                        Set iPic = Nothing
                    Else
                        GetObjectA thePicture.Handle, 24&, uBMP
                    End If
                    If uBMP.bmBitsPixel = 32& Then
                        lValue = zzValidateAlphaChannel(0&, thePicture.Handle)
                        If lValue Then
                            zzGetCompatibleBmp hImage, thePicture, (lValue And tfPicHasTransp)
                            If hImage = 0& Then Exit Function
                            lState = lState Or tfTransparent
                        End If
                    End If
                    If (hImage = 0&) And ((lState And 9&) <> 9&) Then
                        ' is not transparent GIF and no hImage yet
                        If Not (uBMP.bmBits = 0& And uBMP.bmBitsPixel <= 8&) Then
                            ' if not paletted or is a DIB, want hImage else load via GDI+
                            GdipCreateBitmapFromHBITMAP thePicture.Handle, 0&, hImage
                        End If
                    End If
                End If
                If hImage = 0& Then
                    If Me.GetImageData(thePicture, arrData()) = False Then Exit Function
                    If zzIStreamFromSource("", arrData(), lValue, 0&) = False Then Exit Function
                    Erase arrData()
                    If CreateStreamOnHGlobal(lValue, 1&, IStream) = 0& Then
                        GdipLoadImageFromStream ObjPtr(IStream), hImage
                        If hImage = 0& Then Exit Function
                    Else
                        GlobalFree lValue: Exit Function
                    End If
                End If
            End If
        End If
    End If
    
' create sized bitmap
    tDC = GetDC(0&)
    If tDC = 0& Then GoTo ExitRoutine
    ReDim arrBMI(0 To 9)
    arrBMI(0) = 40: arrBMI(1) = Width: arrBMI(2) = Height: arrBMI(3) = &H200001
    hHandle = CreateDIBSection(tDC, arrBMI(0), 0&, uBMP.bmBits, 0&, 0&)
    If hHandle = 0& Then GoTo ExitRoutine
    hDC = CreateCompatibleDC(tDC)
    If hDC = 0& Then GoTo ExitRoutine
    ReleaseDC 0&, tDC: tDC = 0&
    
    If FillTransparency = False Then        ' if not filled, prep DIB
        If (lState And 3&) = 3& Then lValue = 255 Else lValue = 0 ' metafile filled with 255
        FillMemory ByVal uBMP.bmBits, Width * Height * 4&, lValue
    End If
    hHandle = SelectObject(hDC, hHandle)
    If FillTransparency Then                ' fill if requested
        If FillTransparencyColor < 0& Then FillTransparencyColor = GetSysColor(FillTransparencyColor And &HFF)
        lValue = CreateSolidBrush(FillTransparencyColor)
        ReDim arrDataL(0 To 3)
        arrDataL(2) = Width: arrDataL(3) = Height
        FillRect hDC, arrDataL(0), lValue
        DeleteObject lValue: Erase arrDataL()
        lState = lState And Not 1&          ' remove transparency bit
    End If
    If SendToEvents = True Or (lState And 2&) Then  ' use stdPicture.Render
        thePicture.Render (hDC), 0!, 0!, (Width), (Height), 0!, thePicture.Height, thePicture.Width, -thePicture.Height, ByVal 0&
        hGraphics = 1&                      ' flag indicating 'success'
    ElseIf GdipCreateFromHDC(hDC, hGraphics) = 0& Then
        GdipGetImageBounds hImage, fRect(0), SrcUnit_Pixel
        If (lState And tfTransparent) = 0& Then  ' opaque?
            GdipCreateImageAttributes hAttr ' create attr to help prevent introducing semi-transparency along edges
            If hAttr Then GdipSetImageAttributesWrapMode hAttr, 3&, 0&, 0&  ' WrapModeTileFlipXY
        End If
        GdipSetInterpolationMode hGraphics, 7&          ' InterpolationModeHighQualityBicubic
        GdipDrawImageRectRectI hGraphics, hImage, 0&, 0&, Width, Height, fRect(0), fRect(1), fRect(2), fRect(3), SrcUnit_Pixel, hAttr, 0&, 0&
        If hAttr Then GdipDisposeImageAttributes hAttr  ' clean up
        GdipDeleteGraphics hGraphics
    End If
    hHandle = SelectObject(hDC, hHandle): DeleteDC hDC
    
    If hGraphics = 0& Then                              ' failure
        DeleteObject hHandle: hHandle = 0&
        If srcHImage Then GdipDisposeImage srcHImage: srcHImage = 0&
        GoTo ExitRoutine
    End If
    If (lState And 3&) = 3& Then   ' fix up alpha channel after WMF/EMF renders on transparency
        zzOverlayArray VarPtrArray(arrDataL()), uBMP.bmBits, arrSafeArray(), Width * Height, False
        For X = 1& To UBound(arrDataL) - 1&
            ' all bytes were initally set to 255 for entire DIB. When metafile is rendered,
            '   it changes any pixel's alpha byte, that it touched, to zero. So, we need to
            '   change that byte back to 255 & change any untouched pixel to full zero/transparency
            If (arrDataL(X) And &HFF000000) Then
                arrDataL(X) = 0&
            Else
                arrDataL(X) = arrDataL(X) Or &HFF000000
            End If
        Next
        zzOverlayArray VarPtrArray(arrDataL()), 0&, arrSafeArray(), 0&, False
    ElseIf SendToEvents Then
        lState = lState Or Abs(Not (zzValidateAlphaChannel(0&, hHandle) = 0&))
    End If
    
    ' done if returning bitmap, otherwise...
    If hImage Then
        If (lState And &H10&) = 0& Then GdipDisposeImage hImage
        hImage = 0&
    End If
    
    If bAsIcon Then     ' create bitmap header & icon mask
        mskScanWidth = zzDWordAlign(1, Width)
        uBMP.bmWidthBytes = Width * 4&
        ReDim arrData(0 To (uBMP.bmWidthBytes + mskScanWidth) * Height + 39&)
        arrBMI(2) = arrBMI(2) + arrBMI(2)
        CopyMemory arrData(0), arrBMI(0), 40&: Erase arrBMI()
        CopyMemory arrData(40), ByVal uBMP.bmBits, uBMP.bmWidthBytes * Height
        DeleteObject hHandle: hHandle = 0&
        
        lFlags = picICO * tfShiftPicType
        mskPtr = uBMP.bmWidthBytes * Height + 40&
        If (lState And tfMaskTransp) Then ' create mask if image not opaque
            lFlags = lFlags Or tfPicHasTransp Or tfTransparent
            For Y = 0& To Height - 1&
                m = mskPtr + Y * mskScanWidth: mskShift = 128&
                X = Y * uBMP.bmWidthBytes + 40&
                For X = X + 3& To X + uBMP.bmWidthBytes - 1& Step 4&
                    lValue = arrData(X)
                    If lValue < 128& Then arrData(m) = arrData(m) Or mskShift
                    If mskShift = 1& Then
                        mskShift = 128&: m = m + 1&
                    Else
                        mskShift = mskShift \ 2&
                    End If
                    If lValue > 0& And lValue < 255& Then
                        If arrData(X - 3) > 0 Then arrData(X - 3) = arrData(X - 3) * 255& \ lValue
                        If arrData(X - 2) > 0 Then arrData(X - 2) = arrData(X - 2) * 255& \ lValue
                        If arrData(X - 1) > 0 Then arrData(X - 1) = arrData(X - 1) * 255& \ lValue
                    End If
                Next
            Next
        End If
        If Manage = mgtEnhanced Then
            lFlags = zzBitmapFromHICON(rtnPic, 0&, rtnImage, mgtEnhanced, Width, Height, _
                                    VarPtr(arrData(0)), VarPtr(arrData(mskPtr)), UBound(arrData) + 1&, True)
            If rtnPic Is Nothing Then
                If rtnImage Then GdipDisposeImage rtnImage: rtnImage = 0&
            End If
        Else
            hHandle = CreateIconFromResourceEx(arrData(0), UBound(arrData) + 1&, 1&, &H30000, 0&, 0&, 0&)
            Erase arrData()
            If hHandle Then Set rtnPic = zzHandleToStdPicture(hHandle, vbPicTypeIcon)
        End If
        
    ElseIf srcHImage = 0& Then
        lFlags = picBMP * tfShiftPicType
        If (lState And tfTransparent) Then
            If AlphaTypePARGB = False Then
                zzOverlayArray VarPtrArray(arrDataL), uBMP.bmBits, arrSafeArray(), Width * Height, False
                For X = 0& To UBound(arrDataL)
                    lValue = ((arrDataL(X) And &HFF000000) \ &H1000000) And &HFF
                    If lValue > 0& And lValue < 255& Then
                        If (arrDataL(X) And &HFFFFFF) > 0& Then
                            arrDataL(X) = ((arrDataL(X) And &HFF) * 255& \ lValue) Or _
                                        (((arrDataL(X) And &HFF00&) \ &H100&) * 255& \ lValue) * &H100& Or _
                                        (((arrDataL(X) And &HFF0000) \ &H10000) * 255& \ lValue) * &H10000 Or _
                                        (arrDataL(X) And &HFF000000)
                        End If
                    End If
                Next
                zzOverlayArray VarPtrArray(arrDataL), 0&, arrSafeArray(), 0&, False
                lFlags = lFlags Or tfPicHasTransp Or tfTransparent
            Else
                lFlags = lFlags Or tfPicHasPARGB Or tfTransparent
            End If
        End If
        Set rtnPic = zzHandleToStdPicture(hHandle, vbPicTypeBitmap)
        If (lState And tfMaskTransp) Then
            If Manage = mgtEnhanced Then zzGetCompatibleBmp rtnImage, rtnPic, (lFlags And tfPicHasTransp)
        End If
    Else
        With bmpData
            .bpWidth = Width: .bpHeight = Height: .bpStride = .bpWidth * -4&
            .bpPixelFormat = PixelFormat32bppPARGB
            .bpScan0Ptr = zzSafeOffset32(uBMP.bmBits, (.bpHeight - 1&) * -.bpStride)
        End With
        If GdipCreateBitmapFromScan0(Width, Height, 0&, bmpData.bpPixelFormat, 0&, hImage) = 0& Then
            GdipBitmapLockBits hImage, VarPtr(bmpData.bpLeft), ImageLockModeWrite Or ImageLockModeUserInputBuf, bmpData.bpPixelFormat, VarPtr(bmpData.bpWidth)
            GdipBitmapUnlockBits hImage, VarPtr(bmpData.bpWidth)
            GdipDisposeImage srcHImage: srcHImage = hImage: hImage = 0&
            lState = lState Xor &H20
        End If
        DeleteObject hHandle: hHandle = 0&
    End If
    
ExitRoutine:
    If tDC Then ReleaseDC 0&, tDC
    If hDC = 0& Then
        If hHandle Then DeleteObject hHandle
    End If
    If hImage Then
        If (lState And &H10) = 0& Then GdipDisposeImage hImage
    End If
    If srcHImage Then
        If (lState And &H20) Then GdipDisposeImage srcHImage: srcHImage = 0&
    End If
    zzXeroxFormat = lFlags

End Function

Private Function zzDWordAlign(ByVal Depth As Long, ByVal Width As Long) As Long

    ' determine DWord aligned scan width for bitmaps
    ' https://support.microsoft.com/en-us/kb/80080
    zzDWordAlign = ((Width * Depth + &H1F&) And Not &H1F&) \ &H8&
    
End Function

Private Sub Class_Initialize()
    ' if for any reason, multiple versions of this class exist in the same project,
    ' then this constant determines whether a class' methods can be used on a
    ' picture managed by another class. The simple answer is: only when this
    ' constant is the same value in both classes. If not, you must pass the
    ' managed picture to the class version that managed it in order for changes
    ' to be applied to the management state/properties. The only one exception:
    ' UnmanagePicture can unmanage a managed picture regardless which version is newer
    
    Dim pThunkOld As Long
    pThunkOld = zzLocateThunk()
    If pThunkOld Then zzUpgradeThunk pThunkOld
    ' This constant will always be the major version of the THUNK_VERSION constant.
    RECORD_VERSION = THUNK_VERSION \ &H1000&
    
End Sub

Private Sub Class_Terminate()

    ' remove any callbacks to this class
    
    If m_EventsUsed = False Then Exit Sub

    Dim n As Long, lObjPtr As Long
    Dim arrData() As Long, lPtr As Long
    Dim lFlags As ThunkFlagsEnum, lCount As Long
    
    If zzSafeThunkAddress() = False Then Exit Sub
    CopyMemory lCount, ByVal p_ThunkAddr, 4& ' get client count & exit if zero
    If lCount = 0& Then Exit Sub
                                            ' get address to arrObjects & copy to array
    CopyMemory lPtr, ByVal zzSafeOffset32(p_ThunkAddr, OFFSET_ArrObjs), 4&
    CopyMemory n, ByVal lPtr, 4&       ' get its item count
    ReDim arrData(0 To n)
    CopyMemory arrData(0), ByVal lPtr, n * 4& + 4&
    ' note: copying data vs overlaying array simply because it could be technically
    '   possible that COM may release pictures while we are looping thru the array.
    '   By checking each item still exists, we can avoid a potential problem
    lObjPtr = ObjPtr(Me)                    ' loop thru each entry pair
    For n = 2& To n Step 2&
        If arrData(n) Then                  ' look for those using subclassing
            lFlags = CallThunk(f_MsgAddr, arrData(n), msgObjGetFlags)
            If (lFlags And tfPrePostCB) Then ' has callbacks & check if callback to me
                If CallThunk(f_MsgAddr, arrData(n), msgObjGetClassPtr) = lObjPtr Then
                    lPtr = CallThunk(f_MsgAddr, arrData(n), msgObjGetKey)
                    If lPtr Then SysFreeString lPtr                     ' free Key
                    lPtr = CallThunk(f_MsgAddr, arrData(n), msgObjGetCBaddr)
                    CoTaskMemFree lPtr                                  ' free record
                    CallThunk f_MsgAddr, arrData(n), msgObjSetCBaddr, 0& ' reset callbacks
                    CallThunk f_MsgAddr, arrData(n), msgObjSetFlags, lFlags And Not tfCBflags
                End If
            End If
            lCount = lCount - 1&
            If lCount = 0& Then Exit For
        End If
    Next
    
End Sub


' Summary of recent updates
'////////////////////////////////////////////////////////////////////////////////////////////////////
' 25 Apr 2018
'   a. GdipCreateHBITMAPfromBitmap is not setting the alpha channel to opaque as expected.
'       API used quite a bit, so required creating suitable substitue: zzFillImage
'   b. Found two thunk logic errors when rendering from an event to some other hDC.
'       1. The GDI+ clipping region fixed in previous version broke in that scenario.
'           The target DC clipping region was being applied to that DC and shouldn't. Fixed.
'       2. The IgnoreBufferDestParams event parameter wasn't being honored. Bonehead typo. Fixed
'   c. Major problem. At least not thunk related, but class related. Yet again, found a case where
'       the expected VTable layout was not as expected. This time, wildly different. And on a PC
'       where I have run this project time & time again. I abandoned the idea that the tables were
'       layed out in a predictable way. Modified class to address this problem and should be final
'       patch on this topic. One remaining assumption still holds: There are just 2 VTables related
'       to any VB picture: IPicture and Picture (which is IDispatch only). No exceptions found to date.
'       fix: redirection VTables consist of 7 functions for Picture/IDispatch & 18 for IPicture
'           and these tables are filled dynamically from the COM IPicture & Picture VTables.
'       note: stdPicture is coclass (Picture/IPicture). IPictureDisp is just another name for Picture
'   Change to thunk required revision number change: 2.0; changes to thunk records creation
'   Backward compatibility lost. If multiple versions of class in same project, each uses their own thunk

' 21 Apr 2018
'   a. Thunk was setting GDI+ clipping area based on wrong values. The values being used were the
'       destination coords provided by the user within the PreRender event. Values to be used
'       are the original coordinates sent to the user, not user-adjusted values. Problem is that GDI+
'       won't honor GDI clipping areas and if user passes coordinates outside of the GDI clipping
'       area bounds, it overrides the original/intended clipping and shouldn't. Fixed.
'   b. The individual zzManage[xxx] routines were rewritten to better deal with tracking of
'       original and implied image transparency which could be accidentally removed by the user via
'       calls to SetForceTransparency. Separate flag is used now instead of sharing an existing one.
'   c. In all of the public Set[xxx] methods, added optional parameter to auto-refresh passed
'       image control, form or picturebox picture object, if that scenario is applicable. Prevents
'       user from having to add an additional line of code to refresh that picture object after
'       changing a setting related to that picture object.
'   d. Added zzUpgradeThunk method
'   e. Minor: changed method zzLocateListener to zzLocateThunk
'   f. Major: added support for APNG (animated PNG format)
'       - several private methods added and/or modified for that support
'           zzAPNGchunk_acTL, zzAPNGchunk_fcTL, zzAPNGchunk_fdAT
'           zzValidateAPNG, zzTIFfromAPNG, zzCRCArray, zzGetEncoderClsID
'       - renamed GetGIFAnimationInfo to GetGifPngAnimationInfo
'       - renamed SetFrameGIF to SetFrameGifPng
'   g. Added public property Get/Let EnableAPNGSupport
'   h. Added PreLoadPicture event. Added supporting pLoadPicEventParam parameter to LoadPictureEx
'   i. Added public property Get GDIplusImage to return image for accessing metadata or other properties
'   j. Removed ManageStdPicture function which was a method for re-managing pictures because format wasn't
'       known by the user during LoadPictureEx. Now that the PreLoadPicture event is provided, no need.
'   k. With removal of ManageStdPicture, there isn't a way to unmanage or manage a pre-existing stdPicture
'       To resolve those two points:
'       1. Added new UnmanageStdPicture function
'       2. Updated LoadPictureEx to accept an existing stdPicture for managing
'   l. Added a pan/zoom & APNG example to the vbForums demo project.
'   Change to thunk required revision number change: 1.2; no change to thunk records creation/deletion

' 25 March 2018
'   a. Major change to handle a problem in VTable layout with non-US locale installs of VB. In short,
'       expected VTables to be stacked on each other with no gaps. In some locales, there appears to
'       be a 4-byte gap between two VTables. What this 4-byte value is used for, no idea. To fix the
'       problem, the class was modified to accept a reasonable gap between exptected VTables. Gap
'       size: 36 bytes. Fix actually required major changes in the thunk and its overall organization.
'       Changes were so massive, decided to silently not support backward compatibility. Should this
'       version & previous version (1.0) be loaded in same process, each version will use its own
'       thunk in that case.
'   b. Added mgtAutoSelect as default Management Style option in LoadPictureEx, ManageStdPicture,
'       and CopyStdPicture routines. See comments in LoadPictureEx for usage.
'   Change to thunk required revision number change: 1.1; changes to thunk records creation & deletion
'////////////////////////////////////////////////////////////////////////////////////////////////////

