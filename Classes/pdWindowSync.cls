VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "pdWindowSync"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Window Synchronization class
'Copyright 2015-2017 by Tanner Helland
'Created: 26/September/15
'Last updated: 06/February/16
'Last update: migrate to safer subclassing technique
'
'The right-side panel in the main PD window supports a number of collapsible panels.  Each panel lives on its own
' form, which helps keep the code organized (as there are so many panels, each with totally different UI needs).
'
'Because it's a pain to manually move/size those forms as panels are moved and/or sized, the parent form uses an
' array of picture boxes to control subpanel layout.  This class then does the messy business of synchronizing the
' various subpanel forms with their representative picture boxes, which allows us to keep the main toolbar and various
' subpanels nicely compartmentalized, while taking advantage of built-in Windows messaging for relaying size/position
' changes to the subpanels whenever the parent window needs to make changes.
'
'Note that this class requires a 1:1 correlation between parent and child hWnds.  You cannot map multiple children
' to the same parent, by design.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

Implements ISubclass

Private Declare Function GetClientRect Lib "user32" (ByVal hndWindow As Long, ByRef lpRect As winRect) As Long
Private Declare Sub SetWindowPos Lib "user32" (ByVal targetHwnd As Long, ByVal hWndInsertAfter As Long, ByVal x As Long, ByVal y As Long, ByVal cx As Long, ByVal cy As Long, ByVal wFlags As Long)
Private Declare Function SetParent Lib "user32" (ByVal hWndChild As Long, ByVal hWndNewParent As Long) As Long

'SetWindowPos flags
Private Enum SWP_FLAGS
    SWP_ASYNCWINDOWPOS = &H4000
    SWP_FRAMECHANGED = &H20
    SWP_NOACTIVATE = &H10
    SWP_NOMOVE = &H2
    SWP_NOOWNERZORDER = &H200
    SWP_NOREDRAW = &H8
    SWP_NOSENDCHANGING = &H400
    SWP_NOSIZE = &H1
    SWP_HIDEWINDOW = &H80
    SWP_SHOWWINDOW = &H40
    SWP_NOZORDER = &H4
    SWP_DRAWFRAME = &H20
    SWP_NOCOPYBITS = &H100
End Enum

'Subclassed window messages
Private Const WM_SIZE As Long = &H5

'Currently subclassed hWnds.  Each key is a parent hWnd, while each value is the associated child hWnd.
Private m_windowDict As pdDictionary

'Temporary window calculation rect; a single declaration here results in less churn than a local one inside the subclass proc.
Private m_newRect As winRect

Private Sub Class_Initialize()
    Set m_windowDict = New pdDictionary
End Sub

Private Sub Class_Terminate()
    EndSubclassing
End Sub

'Un-subclassing is normally a simple process, but because this class may subclass multiple windows simultaneously,
' a more elaborate shutdown process is required (where we unsubclass each window in turn).
Private Sub EndSubclassing()
    If (Not m_windowDict Is Nothing) Then
        If (m_windowDict.GetNumOfEntries > 0) Then
            Dim i As Long
            For i = 0 To m_windowDict.GetNumOfEntries - 1
                VB_Hacks.StopSubclassing m_windowDict.GetKeyByIndex(i), Me
                m_windowDict.DeleteEntry m_windowDict.GetKeyByIndex(i)
            Next i
        End If
    End If
End Sub

Public Sub SynchronizeWindows(ByVal parentHwnd As Long, ByVal childHwnd As Long)
    
    Dim strKey As String
    strKey = Trim$(Str$(parentHwnd))
    
    'Make sure this window doesn't already exist in the collection
    If g_IsProgramRunning Then
        
        'Failsafe check for duplicate requests
        If (Not m_windowDict.DoesKeyExist(strKey)) Then
        
            'Store the pair of hWnds
            m_windowDict.AddEntry strKey, childHwnd
            
            'Subclass size messages from the parent window
            VB_Hacks.StartSubclassing parentHwnd, Me, childHwnd
            
            'Make the associated window a child of the parent; this automates position and visibility handling
            SetParent childHwnd, parentHwnd
            
            'Perform an initial synchronization to position (0, 0) and the size of the parent window
            Dim parentRect As winRect
            GetClientRect parentHwnd, parentRect
            SetWindowPosition childHwnd, 0, 0
            SetWindowSize childHwnd, parentRect.x2, parentRect.y2
        
        Else
            #If DEBUGMODE = 1 Then
                pdDebug.LogAction "WARNING!  Duplicated hWnd passed to pdWindowSync.SynchronizeWindows.  Fix this!"
            #End If
        End If
        
    End If
    
End Sub

'Move or resize a window
Private Sub SetWindowPosition(ByVal srcHwnd As Long, ByVal newLeft As Long, ByVal newTop As Long, Optional ByVal notifyWindow As Boolean = True)
    
    'Per VB convention, the new left/top coordinates should be in parent coordinates.  If you want to position a
    ' window using *screen coordinates*, you'll need to write a new function (and/or manually convert the coordinates
    ' to screen space in advance).
    Dim swpFlags As SWP_FLAGS
    swpFlags = SWP_NOSIZE Or SWP_NOZORDER Or SWP_NOACTIVATE
    If (Not notifyWindow) Then swpFlags = swpFlags Or SWP_NOSENDCHANGING
    
    SetWindowPos srcHwnd, 0&, newLeft, newTop, 0&, 0&, swpFlags
    
End Sub

Private Sub SetWindowSize(ByVal srcHwnd As Long, ByVal newWidth As Long, ByVal newHeight As Long, Optional ByVal notifyWindow As Boolean = True)
    
    Dim swpFlags As SWP_FLAGS
    swpFlags = SWP_NOMOVE Or SWP_NOZORDER Or SWP_NOACTIVATE
    If Not notifyWindow Then swpFlags = swpFlags Or SWP_NOSENDCHANGING
    
    SetWindowPos srcHwnd, 0&, 0&, 0&, newWidth, newHeight, swpFlags
    
End Sub

Private Function ISubclass_WindowMsg(ByVal hWnd As Long, ByVal uiMsg As Long, ByVal wParam As Long, ByVal lParam As Long, ByVal dwRefData As Long) As Long
    
    If (uiMsg = WM_SIZE) Then
                
        'Retrieve a copy of the parent window's rect (because the windows are guaranteed to be borderless,
        ' GetClientRect works fine)
        GetClientRect hWnd, m_newRect
        
        'Resize the child window to precisely match the parent.
        SetWindowSize dwRefData, m_newRect.x2, m_newRect.y2
    
    'Normally we could let the default function perform tear-down for us, but because this class (uniquely) subclasses
    ' multiple windows simultaneously, we manually update our parent/child window collection to note that the parent
    ' window no longer exists.  (Note that the actual subclass removal is handled by the default PD handler.)
    ElseIf (uiMsg = WM_NCDESTROY) Then
        If (Not m_windowDict Is Nothing) Then m_windowDict.DeleteEntry Trim$(Str$(hWnd))
        
    End If
    
    ISubclass_WindowMsg = VB_Hacks.DefaultSubclassProc(hWnd, uiMsg, wParam, lParam)
    
End Function
