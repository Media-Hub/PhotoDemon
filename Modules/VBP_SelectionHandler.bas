Attribute VB_Name = "Selection_Handler"
'***************************************************************************
'Selection Interface
'Copyright 2013-2017 by Tanner Helland
'Created: 21/June/13
'Last updated: 13/January/15
'Last update: fix selection export to file functions to work with layers.  (Not sure how I missed that prior to 6.4's
'              launch, ugh!)  Thanks to Frans van Beers for reporting the issue.
'
'Selection tools have existed in PhotoDemon for awhile, but this module is the first to support Process varieties of
' selection operations - e.g. internal actions like "Process "Create Selection"".  Selection commands must be passed
' through the Process module so they can be recorded as macros, and as part of the program's Undo/Redo chain.  This
' module provides all selection-related functions that the Process module can call.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

Public Enum SelectionDialogType
    SEL_GROW = 0
    SEL_SHRINK = 1
    SEL_BORDER = 2
    SEL_FEATHER = 3
    SEL_SHARPEN = 4
End Enum

#If False Then
    Const SEL_GROW = 0
    Const SEL_SHRINK = 1
    Const SEL_BORDER = 2
    Const SEL_FEATHER = 3
    Const SEL_SHARPEN = 4
#End If

'This module caches the current selection mode and/or color, and the viewport pipeline retrieves these cached values as necessary
' during rendering.
Private m_CurSelectionMode As PD_SelectionRender, m_CurSelectionColor As Long

'Present a selection-related dialog box (grow, shrink, feather, etc).  This function will return a msgBoxResult value so
' the calling function knows how to proceed, and if the user successfully selected a value, it will be stored in the
' returnValue variable.
Public Function DisplaySelectionDialog(ByVal typeOfDialog As SelectionDialogType, ByRef ReturnValue As Double) As VbMsgBoxResult

    Load FormSelectionDialogs
    FormSelectionDialogs.ShowDialog typeOfDialog
    
    DisplaySelectionDialog = FormSelectionDialogs.DialogResult
    ReturnValue = FormSelectionDialogs.paramValue
    
    Unload FormSelectionDialogs
    Set FormSelectionDialogs = Nothing

End Function

'Create a new selection using the settings stored in a pdParamString-compatible string
Public Sub CreateNewSelection(ByVal paramString As String)
    
    'Use the passed parameter string to initialize the selection
    pdImages(g_CurrentImage).mainSelection.InitFromXML paramString
    pdImages(g_CurrentImage).mainSelection.LockIn
    pdImages(g_CurrentImage).selectionActive = True
    
    'For lasso selections, mark the lasso as closed if the selection is being created anew
    If (pdImages(g_CurrentImage).mainSelection.GetSelectionShape() = ss_Lasso) Then pdImages(g_CurrentImage).mainSelection.SetLassoClosedState True
    
    'Synchronize all user-facing controls to match
    Selection_Handler.SyncTextToCurrentSelection g_CurrentImage
    
    'Draw the new selection to the screen
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Remove the current selection
Public Sub RemoveCurrentSelection()
    
    'Release the selection object and mark it as inactive
    pdImages(g_CurrentImage).mainSelection.LockRelease
    pdImages(g_CurrentImage).selectionActive = False
    
    'Reset any internal selection state trackers
    pdImages(g_CurrentImage).mainSelection.EraseCustomTrackers
    
    'Synchronize all user-facing controls to match
    SyncTextToCurrentSelection g_CurrentImage
        
    'Redraw the image (with selection removed)
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Create a new selection using the settings stored in a pdParamString-compatible string
Public Sub SelectWholeImage()
    
    'Unselect any existing selection
    pdImages(g_CurrentImage).mainSelection.LockRelease
    pdImages(g_CurrentImage).selectionActive = False
    
    'Create a new selection at the size of the image
    pdImages(g_CurrentImage).mainSelection.SelectAll
    
    'Lock in this selection
    pdImages(g_CurrentImage).mainSelection.LockIn
    pdImages(g_CurrentImage).selectionActive = True
    
    'Synchronize all user-facing controls to match
    SyncTextToCurrentSelection g_CurrentImage
    
    'Draw the new selection to the screen
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Load a previously saved selection.  Note that this function also handles creation and display of the relevant common dialog.
Public Sub LoadSelectionFromFile(ByVal displayDialog As Boolean, Optional ByVal SelectionPath As String = "")

    If displayDialog Then
    
        'Disable user input until the dialog closes
        Interface.DisableUserInput
    
        'Simple open dialog
        Dim openDialog As pdOpenSaveDialog
        Set openDialog = New pdOpenSaveDialog
        
        Dim sFile As String
        
        Dim cdFilter As String
        cdFilter = g_Language.TranslateMessage("PhotoDemon Selection") & " (." & SELECTION_EXT & ")|*." & SELECTION_EXT & "|"
        cdFilter = cdFilter & g_Language.TranslateMessage("All files") & "|*.*"
        
        Dim cdTitle As String
        cdTitle = g_Language.TranslateMessage("Load a previously saved selection")
                
        If openDialog.GetOpenFileName(sFile, , True, False, cdFilter, 1, g_UserPreferences.GetSelectionPath, cdTitle, , GetModalOwner().hWnd) Then
            
            'Use a temporary selection object to validate the requested selection file
            Dim tmpSelection As pdSelection
            Set tmpSelection = New pdSelection
            tmpSelection.SetParentReference pdImages(g_CurrentImage)
            
            If tmpSelection.ReadSelectionFromFile(sFile, True) Then
                
                'Save the new directory as the default path for future usage
                g_UserPreferences.SetSelectionPath sFile
                
                'Call this function again, but with displayDialog set to FALSE and the path of the requested selection file
                Process "Load selection", False, sFile, UNDO_SELECTION
                    
            Else
                PDMsgBox "An error occurred while attempting to load %1.  Please verify that the file is a valid PhotoDemon selection file.", vbOKOnly + vbExclamation + vbApplicationModal, "Selection Error", sFile
            End If
            
            'Release the temporary selection object
            tmpSelection.SetParentReference Nothing
            Set tmpSelection = Nothing
            
        End If
        
        'Re-enable user input
        Interface.EnableUserInput
        
    Else
    
        Message "Loading selection..."
        pdImages(g_CurrentImage).mainSelection.ReadSelectionFromFile SelectionPath
        pdImages(g_CurrentImage).selectionActive = True
        
        'Synchronize all user-facing controls to match
        SyncTextToCurrentSelection g_CurrentImage
                
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
        Message "Selection loaded successfully"
    
    End If
        
End Sub

'Save the current selection to file.  Note that this function also handles creation and display of the relevant common dialog.
Public Sub SaveSelectionToFile()

    'Simple save dialog
    Dim saveDialog As pdOpenSaveDialog
    Set saveDialog = New pdOpenSaveDialog
    
    Dim sFile As String
    
    Dim cdFilter As String
    cdFilter = g_Language.TranslateMessage("PhotoDemon Selection") & " (." & SELECTION_EXT & ")|*." & SELECTION_EXT
    
    Dim cdTitle As String
    cdTitle = g_Language.TranslateMessage("Save the current selection")
        
    If saveDialog.GetSaveFileName(sFile, , True, cdFilter, 1, g_UserPreferences.GetSelectionPath, cdTitle, "." & SELECTION_EXT, GetModalOwner().hWnd) Then
        
        'Save the new directory as the default path for future usage
        g_UserPreferences.SetSelectionPath sFile
        
        'Write out the selection file
        If pdImages(g_CurrentImage).mainSelection.WriteSelectionToFile(sFile) Then
            Message "Selection saved."
        Else
            Message "Unknown error occurred.  Selection was not saved.  Please try again."
        End If
        
    End If
        
End Sub

'Export the currently selected area as an image.  This is provided as a convenience to the user, so that they do not have to crop
' or copy-paste the selected area in order to save it.  The selected area is also checked for bit-depth; 24bpp is recommended as
' JPEG, while 32bpp is recommended as PNG (but the user can select any supported PD save format from the common dialog).
Public Function ExportSelectedAreaAsImage() As Boolean
    
    'If a selection is not active, it should be impossible to select this menu item.  Just in case, check for that state and exit if necessary.
    If Not pdImages(g_CurrentImage).selectionActive Then
        Message "This action requires an active selection.  Please create a selection before continuing."
        ExportSelectedAreaAsImage = False
        Exit Function
    End If
    
    'Prepare a temporary pdImage object to house the current selection mask
    Dim tmpImage As pdImage
    Set tmpImage = New pdImage
    
    'Copy the current selection DIB into a temporary DIB.
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    pdImages(g_CurrentImage).RetrieveProcessedSelection tmpDIB, False, True
    
    'If the selected area has a blank alpha channel, convert it to 24bpp
    If Not DIB_Support.IsDIBAlphaBinary(tmpDIB, False) Then tmpDIB.ConvertTo24bpp
    
    'In the temporary pdImage object, create a blank layer; this will receive the processed DIB
    Dim newLayerID As Long
    newLayerID = tmpImage.CreateBlankLayer
    tmpImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, , tmpDIB
    tmpImage.UpdateSize
        
    'Give the selection a basic filename
    tmpImage.imgStorage.AddEntry "OriginalFileName", "PhotoDemon selection"
        
    'Get the last "save image" path from the preferences file
    Dim tempPathString As String
    tempPathString = g_UserPreferences.GetPref_String("Paths", "Save Image", "")
    
    'By default, recommend JPEG for 24bpp selections, and PNG for 32bpp selections
    Dim saveFormat As Long
    If tmpDIB.GetDIBColorDepth = 24 Then
        saveFormat = g_ImageFormats.GetIndexOfOutputPDIF(PDIF_JPEG) + 1
    Else
        saveFormat = g_ImageFormats.GetIndexOfOutputPDIF(PDIF_PNG) + 1
    End If
    
    'Now it's time to prepare a standard Save Image common dialog
    Dim saveDialog As pdOpenSaveDialog
    Set saveDialog = New pdOpenSaveDialog
    
    'Provide a string to the common dialog; it will fill this with the user's chosen path + filename
    Dim sFile As String
    sFile = tempPathString & IncrementFilename(tempPathString, tmpImage.imgStorage.GetEntry_String("OriginalFileName", vbNullString), g_ImageFormats.GetOutputFormatExtension(saveFormat - 1))
    
    'Present a common dialog to the user
    If saveDialog.GetSaveFileName(sFile, , True, g_ImageFormats.GetCommonDialogOutputFormats, saveFormat, tempPathString, g_Language.TranslateMessage("Export selection as image"), g_ImageFormats.GetCommonDialogDefaultExtensions, FormMain.hWnd) Then
                
        'Store the selected file format to the image object
        tmpImage.currentFileFormat = g_ImageFormats.GetOutputPDIF(saveFormat - 1)
                                
        'Transfer control to the core SaveImage routine, which will handle color depth analysis and actual saving
        ExportSelectedAreaAsImage = PhotoDemon_SaveImage(tmpImage, sFile, True)
        
    Else
        ExportSelectedAreaAsImage = False
    End If
        
    'Release our temporary image
    Set tmpDIB = Nothing
    Set tmpImage = Nothing
    
End Function

'Export the current selection mask as an image.  PNG is recommended by default, but the user can choose from any of PD's available formats.
Public Function ExportSelectionMaskAsImage() As Boolean
    
    'If a selection is not active, it should be impossible to select this menu item.  Just in case, check for that state and exit if necessary.
    If Not pdImages(g_CurrentImage).selectionActive Then
        Message "This action requires an active selection.  Please create a selection before continuing."
        ExportSelectionMaskAsImage = False
        Exit Function
    End If
    
    'Prepare a temporary pdImage object to house the current selection mask
    Dim tmpImage As pdImage
    Set tmpImage = New pdImage
    
    'Create a temporary DIB, then retrieve the current selection into it
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    tmpDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
    
    'Due to the way selections work, it's easier for us to forcibly up-sample the selection mask to 32bpp.  This prevents
    ' some issues with saving to exotic file formats.
    tmpDIB.ConvertTo32bpp
    
    'In the temporary pdImage object, create a blank layer; this will receive the processed DIB
    Dim newLayerID As Long
    newLayerID = tmpImage.CreateBlankLayer
    tmpImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, , tmpDIB
    tmpImage.UpdateSize
    
    'Give the selection a basic filename
    tmpImage.imgStorage.AddEntry "OriginalFileName", g_Language.TranslateMessage("PhotoDemon selection")
        
    'Get the last "save image" path from the preferences file
    Dim tempPathString As String
    tempPathString = g_UserPreferences.GetPref_String("Paths", "Save Image", "")
    
    'By default, recommend PNG as the save format
    Dim saveFormat As Long
    saveFormat = g_ImageFormats.GetIndexOfOutputPDIF(PDIF_PNG) + 1
    
    'Provide a string to the common dialog; it will fill this with the user's chosen path + filename
    Dim sFile As String
    sFile = tempPathString & IncrementFilename(tempPathString, tmpImage.imgStorage.GetEntry_String("OriginalFileName", vbNullString), "png")
    
    'Now it's time to prepare a standard Save Image common dialog
    Dim saveDialog As pdOpenSaveDialog
    Set saveDialog = New pdOpenSaveDialog
    
    'Present a common dialog to the user
    If saveDialog.GetSaveFileName(sFile, , True, g_ImageFormats.GetCommonDialogOutputFormats, saveFormat, tempPathString, g_Language.TranslateMessage("Export selection as image"), g_ImageFormats.GetCommonDialogDefaultExtensions, FormMain.hWnd) Then
                
        'Store the selected file format to the image object
        tmpImage.currentFileFormat = g_ImageFormats.GetOutputPDIF(saveFormat - 1)
                                
        'Transfer control to the core SaveImage routine, which will handle color depth analysis and actual saving
        ExportSelectionMaskAsImage = PhotoDemon_SaveImage(tmpImage, sFile, True)
        
    Else
        ExportSelectionMaskAsImage = False
    End If
    
    'Release our temporary image
    Set tmpImage = Nothing

End Function

'Use this to populate the text boxes on the main form with the current selection values.  Note that this does not cause a screen refresh, by design.
Public Sub SyncTextToCurrentSelection(ByVal formID As Long)

    Dim i As Long
    
    'Only synchronize the text boxes if a selection is active
    If Selection_Handler.SelectionsAllowed(False) Then
        
        pdImages(formID).mainSelection.SuspendAutoRefresh True
        
        'Selection coordinate toolboxes appear on three different selection subpanels: rect, ellipse, and line.
        ' To access their indicies properly, we must calculate an offset.
        Dim subpanelOffset As Long
        subpanelOffset = Selection_Handler.GetSelectionSubPanelFromSelectionShape(pdImages(formID)) * 4
        
        If Tool_Support.IsSelectionToolActive Then
        
            'Additional syncing is done if the selection is transformable; if it is not transformable, clear and lock the location text boxes
            If pdImages(formID).mainSelection.IsTransformable Then
                
                Dim tmpRectF As RECTF, tmpRectFRB As RECTF_RB
                
                'Different types of selections will display size and position differently
                Select Case pdImages(formID).mainSelection.GetSelectionShape
                    
                    'Rectangular and elliptical selections display left, top, width and height
                    Case ss_Rectangle, ss_Circle
                        tmpRectF = pdImages(formID).mainSelection.GetCornersLockedRect()
                        toolpanel_Selections.tudSel(subpanelOffset + 0).Value = tmpRectF.Left
                        toolpanel_Selections.tudSel(subpanelOffset + 1).Value = tmpRectF.Top
                        toolpanel_Selections.tudSel(subpanelOffset + 2).Value = tmpRectF.Width
                        toolpanel_Selections.tudSel(subpanelOffset + 3).Value = tmpRectF.Height
                        
                    'Line selections display x1, y1, x2, y2
                    Case ss_Line
                        tmpRectFRB = pdImages(formID).mainSelection.GetCornersUnlockedRect()
                        toolpanel_Selections.tudSel(subpanelOffset + 0).Value = tmpRectFRB.Left
                        toolpanel_Selections.tudSel(subpanelOffset + 1).Value = tmpRectFRB.Top
                        toolpanel_Selections.tudSel(subpanelOffset + 2).Value = tmpRectFRB.Right
                        toolpanel_Selections.tudSel(subpanelOffset + 3).Value = tmpRectFRB.Bottom
            
                End Select
                
            Else
            
                For i = 0 To toolpanel_Selections.tudSel.Count - 1
                    If (toolpanel_Selections.tudSel(i).Value <> 0) Then toolpanel_Selections.tudSel(i).Value = 0
                Next i
                
            End If
            
            'Next, sync all non-coordinate information
            If (pdImages(formID).mainSelection.GetSelectionShape <> ss_Raster) And (pdImages(formID).mainSelection.GetSelectionShape <> ss_Wand) Then
                toolpanel_Selections.cboSelArea(Selection_Handler.GetSelectionSubPanelFromSelectionShape(pdImages(formID))).ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_Area)
                toolpanel_Selections.sltSelectionBorder(Selection_Handler.GetSelectionSubPanelFromSelectionShape(pdImages(formID))).Value = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_BorderWidth)
            End If
            
            If toolpanel_Selections.cboSelSmoothing.ListIndex <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_Smoothing) Then toolpanel_Selections.cboSelSmoothing.ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_Smoothing)
            If toolpanel_Selections.sltSelectionFeathering.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_FeatheringRadius) Then toolpanel_Selections.sltSelectionFeathering.Value = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_FeatheringRadius)
            
            'Finally, sync any shape-specific information
            Select Case pdImages(formID).mainSelection.GetSelectionShape
            
                Case ss_Rectangle
                    If toolpanel_Selections.sltCornerRounding.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_RoundedCornerRadius) Then toolpanel_Selections.sltCornerRounding.Value = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_RoundedCornerRadius)
                
                Case ss_Circle
                
                Case ss_Line
                    If toolpanel_Selections.sltSelectionLineWidth.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_LineWidth) Then toolpanel_Selections.sltSelectionLineWidth.Value = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_LineWidth)
                    
                Case ss_Lasso
                    If toolpanel_Selections.sltSmoothStroke.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_SmoothStroke) Then toolpanel_Selections.sltSmoothStroke.Value = pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_SmoothStroke)
                    
                Case ss_Polygon
                    If toolpanel_Selections.sltPolygonCurvature.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_PolygonCurvature) Then toolpanel_Selections.sltPolygonCurvature.Value = pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_PolygonCurvature)
                    
                Case ss_Wand
                    If toolpanel_Selections.btsWandArea.ListIndex <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandSearchMode) Then toolpanel_Selections.btsWandArea.ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandSearchMode)
                    If toolpanel_Selections.btsWandMerge.ListIndex <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandSampleMerged) Then toolpanel_Selections.btsWandMerge.ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandSampleMerged)
                    If toolpanel_Selections.sltWandTolerance.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_WandTolerance) Then toolpanel_Selections.sltWandTolerance.Value = pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_WandTolerance)
                    If toolpanel_Selections.cboWandCompare.ListIndex <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandCompareMethod) Then toolpanel_Selections.cboWandCompare.ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandCompareMethod)
            
            End Select
            
        End If
        
        pdImages(formID).mainSelection.SuspendAutoRefresh False
        
    Else
        
        SetUIGroupState PDUI_Selections, False
        SetUIGroupState PDUI_SelectionTransforms, False
        
        If Tool_Support.IsSelectionToolActive Then
            For i = 0 To toolpanel_Selections.tudSel.Count - 1
                If (toolpanel_Selections.tudSel(i).Value <> 0) Then toolpanel_Selections.tudSel(i).Value = 0
            Next i
        End If
        
    End If
    
End Sub

'This sub will return a constant correlating to the nearest selection point. Its return values are:
' -1 - Cursor is not near a selection point
' 0 - NW corner
' 1 - NE corner
' 2 - SE corner
' 3 - SW corner
' 4 - N edge
' 5 - E edge
' 6 - S edge
' 7 - W edge
' 8 - interior of selection, not near a corner or edge (e.g. move the selection)
'
'Note that the x and y values this function is passed are assumed to already be in the IMAGE coordinate space, not the SCREEN or CANVAS
' coordinate space.
Public Function FindNearestSelectionCoordinates(ByVal imgX As Double, ByVal imgY As Double, ByRef srcImage As pdImage) As Long
    
    'If the current selection is of raster-type, return 0.
    If srcImage.mainSelection.GetSelectionShape = ss_Raster Then
        FindNearestSelectionCoordinates = -1
        Exit Function
    End If
    
    'If the current selection is NOT active, return 0.
    If Not srcImage.selectionActive Then
        FindNearestSelectionCoordinates = -1
        Exit Function
    End If
        
    'Calculate points of interest for the current selection.  Said points will be corners (for rectangle and circle selections),
    ' or line endpoints (for line selections).
    Dim tLeft As Long, tTop As Long, tRight As Long, tBottom As Long, tmpRectF As RECTF
    If (srcImage.mainSelection.GetSelectionShape = ss_Rectangle) Or (srcImage.mainSelection.GetSelectionShape = ss_Circle) Then
        tmpRectF = srcImage.mainSelection.GetCornersLockedRect()
        tLeft = tmpRectF.Left
        tTop = tmpRectF.Top
        tRight = tmpRectF.Left + tmpRectF.Width
        tBottom = tmpRectF.Top + tmpRectF.Height
    Else
        tmpRectF = srcImage.mainSelection.GetBoundaryRect()
        tLeft = tmpRectF.Left
        tTop = tmpRectF.Top
        tRight = tmpRectF.Left + tmpRectF.Width
        tBottom = tmpRectF.Top + tmpRectF.Height
    End If
    
    'Adjust the mouseAccuracy value based on the current zoom value
    Dim mouseAccuracy As Double
    mouseAccuracy = g_MouseAccuracy * (1 / g_Zoom.GetZoomValue(srcImage.currentZoomValue))
        
    'Find the smallest distance for this mouse position
    Dim minDistance As Double
    minDistance = mouseAccuracy
    
    Dim closestPoint As Long
    closestPoint = -1
    
    'Some selection types (lasso, polygon) must use a more complicated region for hit-testing.  GDI+ will be used for this.
    Dim gdipRegionHandle As Long, gdipHitCheck As Boolean
    
    Dim poiList() As POINTAPI
    Dim poiListFloat() As POINTFLOAT
    
    'If we made it here, this mouse location is worth evaluating.  How we evaluate it depends on the shape of the current selection.
    Select Case srcImage.mainSelection.GetSelectionShape
    
        'Rectangular and elliptical selections have identical POIs: the corners, edges, and interior of the selection
        Case ss_Rectangle, ss_Circle
    
            'Corners get preference, so check them first.
            ReDim poiList(0 To 3) As POINTAPI
            
            poiList(0).x = tLeft
            poiList(0).y = tTop
            poiList(1).x = tRight
            poiList(1).y = tTop
            poiList(2).x = tRight
            poiList(2).y = tBottom
            poiList(3).x = tLeft
            poiList(3).y = tBottom
            
            'Used the generalized point comparison function to see if one of the points matches
            closestPoint = FindClosestPointInArray(imgX, imgY, minDistance, poiList)
            
            'Was a close point found? If yes, then return that value
            If closestPoint <> -1 Then
                FindNearestSelectionCoordinates = closestPoint
                Exit Function
            End If
        
            'If we're at this line of code, a closest corner was not found.  Check edges next.
            ' (Unfortunately, we don't yet have a generalized function for edge checking, so this must be done manually.)
            Dim nDist As Double, eDist As Double, sDist As Double, wDist As Double
            
            nDist = DistanceOneDimension(imgY, tTop)
            eDist = DistanceOneDimension(imgX, tRight)
            sDist = DistanceOneDimension(imgY, tBottom)
            wDist = DistanceOneDimension(imgX, tLeft)
            
            If (nDist <= minDistance) And (imgX > (tLeft - minDistance)) And (imgX < (tRight + minDistance)) Then
                minDistance = nDist
                closestPoint = 4
            End If
            
            If (eDist <= minDistance) And (imgY > (tTop - minDistance)) And (imgY < (tBottom + minDistance)) Then
                minDistance = eDist
                closestPoint = 5
            End If
            
            If (sDist <= minDistance) And (imgX > (tLeft - minDistance)) And (imgX < (tRight + minDistance)) Then
                minDistance = sDist
                closestPoint = 6
            End If
            
            If (wDist <= minDistance) And (imgY > (tTop - minDistance)) And (imgY < (tBottom + minDistance)) Then
                minDistance = wDist
                closestPoint = 7
            End If
            
            'Was a close point found? If yes, then return that value.
            If closestPoint <> -1 Then
                FindNearestSelectionCoordinates = closestPoint
                Exit Function
            End If
        
            'If we're at this line of code, a closest edge was not found. Perform one final check to ensure that the mouse is within the
            ' image's boundaries, and if it is, return the "move selection" ID, then exit.
            If (imgX > tLeft) And (imgX < tRight) And (imgY > tTop) And (imgY < tBottom) Then
                FindNearestSelectionCoordinates = 8
            Else
                FindNearestSelectionCoordinates = -1
            End If
            
        Case ss_Line
    
            'Line selections are simple - we only care if the mouse is by (x1,y1) or (x2,y2)
            Dim xCoord As Double, yCoord As Double
            Dim firstDist As Double, secondDist As Double
            
            closestPoint = -1
            
            srcImage.mainSelection.GetSelectionCoordinates 1, xCoord, yCoord
            firstDist = DistanceTwoPoints(imgX, imgY, xCoord, yCoord)
            
            srcImage.mainSelection.GetSelectionCoordinates 2, xCoord, yCoord
            secondDist = DistanceTwoPoints(imgX, imgY, xCoord, yCoord)
                        
            If (firstDist <= minDistance) Then closestPoint = 0
            If (secondDist <= minDistance) Then closestPoint = 1
            
            'Was a close point found? If yes, then return that value.
            FindNearestSelectionCoordinates = closestPoint
            Exit Function
        
        Case ss_Polygon
        
            'First, we want to check all polygon points for a hit.
            pdImages(g_CurrentImage).mainSelection.GetPolygonPoints poiListFloat()
            
            'Used the generalized point comparison function to see if one of the points matches
            closestPoint = FindClosestPointInFloatArray(imgX, imgY, minDistance, poiListFloat)
            
            'Was a close point found? If yes, then return that value
            If closestPoint <> -1 Then
                FindNearestSelectionCoordinates = closestPoint
                Exit Function
            End If
            
            'If no polygon point was a hit, our final check is to see if the mouse lies within the polygon itself.  This will trigger
            ' a move transformation.
            
            'Create a GDI+ region from the current selection points
            gdipRegionHandle = pdImages(g_CurrentImage).mainSelection.GetGdipRegionForSelection()
            
            'Check the point for a hit
            gdipHitCheck = GDI_Plus.IsPointInGDIPlusRegion(imgX, imgY, gdipRegionHandle)
            
            'Release the GDI+ region
            GDI_Plus.ReleaseGDIPlusRegion gdipRegionHandle
            
            If gdipHitCheck Then FindNearestSelectionCoordinates = pdImages(g_CurrentImage).mainSelection.GetNumOfPolygonPoints Else FindNearestSelectionCoordinates = -1
        
        Case ss_Lasso
            'Create a GDI+ region from the current selection points
            gdipRegionHandle = pdImages(g_CurrentImage).mainSelection.GetGdipRegionForSelection()
            
            'Check the point for a hit
            gdipHitCheck = GDI_Plus.IsPointInGDIPlusRegion(imgX, imgY, gdipRegionHandle)
            
            'Release the GDI+ region
            GDI_Plus.ReleaseGDIPlusRegion gdipRegionHandle
            
            If gdipHitCheck Then FindNearestSelectionCoordinates = 0 Else FindNearestSelectionCoordinates = -1
        
        Case ss_Wand
            closestPoint = -1
            
            srcImage.mainSelection.GetSelectionCoordinates 1, xCoord, yCoord
            firstDist = DistanceTwoPoints(imgX, imgY, xCoord, yCoord)
                        
            If (firstDist <= minDistance) Then closestPoint = 0
            
            'Was a close point found? If yes, then return that value.
            FindNearestSelectionCoordinates = closestPoint
            Exit Function
        
        Case Else
            FindNearestSelectionCoordinates = -1
            Exit Function
            
    End Select

End Function

'Invert the current selection.  Note that this will make a transformable selection non-transformable - to maintain transformability, use
' the "exterior"/"interior" options on the main form.
' TODO: swap exterior/interior automatically, if a valid option
Public Sub InvertCurrentSelection()

    'Unselect any existing selection
    pdImages(g_CurrentImage).mainSelection.LockRelease
    pdImages(g_CurrentImage).selectionActive = False
        
    Message "Inverting selection..."
    
    'Point a standard 2D byte array at the selection mask
    Dim x As Long, y As Long
    Dim quickVal As Long
    
    Dim selMaskData() As Byte
    Dim selMaskSA As SAFEARRAY2D
    PrepSafeArray selMaskSA, pdImages(g_CurrentImage).mainSelection.GetMaskDIB
    CopyMemory ByVal VarPtrArray(selMaskData()), VarPtr(selMaskSA), 4
    
    Dim maskWidth As Long, maskHeight As Long
    maskWidth = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth - 1
    maskHeight = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBHeight - 1
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    SetProgBarMax maskWidth
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    Dim selMaskDepth As Long
    selMaskDepth = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBColorDepth \ 8
    
    'After all that work, the Invert code itself is very small and unexciting!
    For x = 0 To maskWidth
        quickVal = x * selMaskDepth
    For y = 0 To maskHeight
        selMaskData(quickVal, y) = 255 - selMaskData(quickVal, y)
        selMaskData(quickVal + 1, y) = 255 - selMaskData(quickVal + 1, y)
        selMaskData(quickVal + 2, y) = 255 - selMaskData(quickVal + 2, y)
    Next y
        If (x And progBarCheck) = 0 Then SetProgBarVal x
    Next x
    
    'Release our temporary byte array
    CopyMemory ByVal VarPtrArray(selMaskData), 0&, 4
    Erase selMaskData
    
    'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
    ' being non-transformable)
    pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
    
    SetProgBarVal 0
    ReleaseProgressBar
    Message "Selection inversion complete."
    
    'Lock in this selection
    pdImages(g_CurrentImage).mainSelection.LockIn
    pdImages(g_CurrentImage).selectionActive = True
        
    'Draw the new selection to the screen
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Feather the current selection.  Note that this will make a transformable selection non-transformable.
Public Sub FeatherCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal featherRadius As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retRadius As Double
        If DisplaySelectionDialog(SEL_FEATHER, retRadius) = vbOK Then
            Process "Feather selection", False, Str(retRadius), UNDO_SELECTION
        End If
        
    Else
    
        Message "Feathering selection..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).selectionActive = False
        
        'Use PD's built-in Gaussian blur function to apply the blur
        QuickBlurDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB, featherRadius, True
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
        
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).selectionActive = True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Feathering complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If

End Sub

'Sharpen (un-feather?) the current selection.  Note that this will make a transformable selection non-transformable.
Public Sub SharpenCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal sharpenRadius As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retRadius As Double
        If DisplaySelectionDialog(SEL_SHARPEN, retRadius) = vbOK Then
            Process "Sharpen selection", False, Str(retRadius), UNDO_SELECTION
        End If
        
    Else
    
        Message "Sharpening selection..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).selectionActive = False
        
       'Point an array at the current selection mask
        Dim selMaskData() As Byte
        Dim selMaskSA As SAFEARRAY2D
        
        'Create a second local array.  This will contain the a copy of the selection mask, and we will use it as our source reference
        ' (This is necessary to prevent blurred pixel values from spreading across the image as we go.)
        Dim srcDIB As pdDIB
        Set srcDIB = New pdDIB
        srcDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
                
        'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
        Dim x As Long, y As Long
        
        'Unsharp masking requires a gaussian blur DIB to operate.  Create one now.
        QuickBlurDIB srcDIB, sharpenRadius, True
        
        'Now that we have a gaussian DIB created in workingDIB, we can point arrays toward it and the source DIB
        PrepSafeArray selMaskSA, pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        CopyMemory ByVal VarPtrArray(selMaskData()), VarPtr(selMaskSA), 4
        
        Dim srcImageData() As Byte
        Dim srcSA As SAFEARRAY2D
        PrepSafeArray srcSA, srcDIB
        CopyMemory ByVal VarPtrArray(srcImageData()), VarPtr(srcSA), 4
        
        'These values will help us access locations in the array more quickly.
        ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
        Dim quickVal As Long, qvDepth As Long
        qvDepth = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBColorDepth \ 8
        
        'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
        ' based on the size of the area to be processed.
        Dim progBarCheck As Long
        SetProgBarMax pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth
        progBarCheck = FindBestProgBarValue()
        
        'ScaleFactor is used to apply the unsharp mask.  Maximum strength can be any value, but PhotoDemon locks it at 10.
        Dim scaleFactor As Double, invScaleFactor As Double
        scaleFactor = sharpenRadius
        invScaleFactor = 1 - scaleFactor
        
        Dim iWidth As Long, iHeight As Long
        iWidth = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth - 1
        iHeight = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBHeight - 1
        
        Dim blendVal As Double
        
        'More color variables - in this case, sums for each color component
        Dim r As Long, g As Long, b As Long
        Dim r2 As Long, g2 As Long, b2 As Long
        Dim newR As Long, newG As Long, newB As Long
        Dim tLumDelta As Long
        
        'The final step of the smart blur function is to find edges, and replace them with the blurred data as necessary
        For x = 0 To iWidth
            quickVal = x * qvDepth
        For y = 0 To iHeight
                
            'Retrieve the original image's pixels
            r = selMaskData(quickVal + 2, y)
            g = selMaskData(quickVal + 1, y)
            b = selMaskData(quickVal, y)
            
            'Now, retrieve the gaussian pixels
            r2 = srcImageData(quickVal + 2, y)
            g2 = srcImageData(quickVal + 1, y)
            b2 = srcImageData(quickVal, y)
            
            tLumDelta = Abs(GetLuminance(r, g, b) - GetLuminance(r2, g2, b2))
                
            newR = (scaleFactor * r) + (invScaleFactor * r2)
            If newR > 255 Then newR = 255
            If newR < 0 Then newR = 0
                
            newG = (scaleFactor * g) + (invScaleFactor * g2)
            If newG > 255 Then newG = 255
            If newG < 0 Then newG = 0
                
            newB = (scaleFactor * b) + (invScaleFactor * b2)
            If newB > 255 Then newB = 255
            If newB < 0 Then newB = 0
            
            blendVal = tLumDelta / 255
            
            newR = BlendColors(newR, r, blendVal)
            newG = BlendColors(newG, g, blendVal)
            newB = BlendColors(newB, b, blendVal)
            
            selMaskData(quickVal + 2, y) = newR
            selMaskData(quickVal + 1, y) = newG
            selMaskData(quickVal, y) = newB
                    
        Next y
            If (x And progBarCheck) = 0 Then SetProgBarVal x
        Next x
        
        CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
        Erase srcImageData
        
        CopyMemory ByVal VarPtrArray(selMaskData), 0&, 4
        Erase selMaskData
        
        Set srcDIB = Nothing
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
        
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).selectionActive = True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Feathering complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If

End Sub

'Grow the current selection.  Note that this will make a transformable selection non-transformable.
Public Sub GrowCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal growSize As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retSize As Double
        If DisplaySelectionDialog(SEL_GROW, retSize) = vbOK Then
            Process "Grow selection", False, Str(retSize), UNDO_SELECTION
        End If
        
    Else
    
        Message "Growing selection..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).selectionActive = False
        
        'Use PD's built-in Median function to dilate the selected area
        Dim tmpDIB As pdDIB
        Set tmpDIB = New pdDIB
        tmpDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        CreateMedianDIB growSize, 99, PDPRS_Circle, tmpDIB, pdImages(g_CurrentImage).mainSelection.GetMaskDIB, False
        
        Set tmpDIB = Nothing
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
        
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).selectionActive = True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Selection resize complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If
    
End Sub

'Shrink the current selection.  Note that this will make a transformable selection non-transformable.
Public Sub ShrinkCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal shrinkSize As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retSize As Double
        If DisplaySelectionDialog(SEL_SHRINK, retSize) = vbOK Then
            Process "Shrink selection", False, Str(retSize), UNDO_SELECTION
        End If
        
    Else
    
        Message "Shrinking selection..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).selectionActive = False
        
        'Use PD's built-in Median function to erode the selected area
        Dim tmpDIB As pdDIB
        Set tmpDIB = New pdDIB
        tmpDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        CreateMedianDIB shrinkSize, 1, PDPRS_Circle, tmpDIB, pdImages(g_CurrentImage).mainSelection.GetMaskDIB, False
        
        'Erase the temporary DIB
        Set tmpDIB = Nothing
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
        
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).selectionActive = True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Selection resize complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If
    
End Sub

'Convert the current selection to border-type.  Note that this will make a transformable selection non-transformable.
Public Sub BorderCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal borderRadius As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retSize As Double
        If DisplaySelectionDialog(SEL_BORDER, retSize) = vbOK Then
            Process "Border selection", False, Str(retSize), UNDO_SELECTION
        End If
        
    Else
    
        Message "Finding selection border..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).selectionActive = False
        
        'Bordering a selection requires two passes: a grow pass and a shrink pass.  The results of these two passes are then blended
        ' to create the final bordered selection.
        
        'Start by creating the grow and shrink DIBs using a median function.
        Dim growDIB As pdDIB
        Set growDIB = New pdDIB
        growDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        
        Dim shrinkDIB As pdDIB
        Set shrinkDIB = New pdDIB
        shrinkDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        
        'Use a median function to dilate and erode the existing mask
        CreateMedianDIB borderRadius, 1, PDPRS_Circle, pdImages(g_CurrentImage).mainSelection.GetMaskDIB, shrinkDIB, False, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth * 2
        CreateMedianDIB borderRadius, 99, PDPRS_Circle, pdImages(g_CurrentImage).mainSelection.GetMaskDIB, growDIB, False, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth * 2, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth
        
        'Blend those two DIBs together, and use the difference between the two to calculate the new border area
        pdImages(g_CurrentImage).mainSelection.GetMaskDIB.CreateFromExistingDIB growDIB
        BitBlt pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBDC, 0, 0, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBHeight, shrinkDIB.GetDIBDC, 0, 0, vbSrcInvert
        
        'Erase the temporary DIBs
        Set growDIB = Nothing
        Set shrinkDIB = Nothing
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
                
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).selectionActive = True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Selection resize complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If
    
End Sub

'Erase the currently selected area (LAYER ONLY!).  Note that this will not modify the current selection in any way.
Public Sub EraseSelectedArea(ByVal targetLayerIndex As Long)

    pdImages(g_CurrentImage).EraseProcessedSelection targetLayerIndex
    
    'Redraw the active viewport
    Viewport_Engine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'The selection engine integrates closely with tool selection (as it needs to know what kind of selection is being
' created/edited at any given time).  This function is called whenever the selection engine needs to correlate the
' current tool with a selection shape.  This allows us to easily switch between a rectangle and circle selection,
' for example, without forcing the user to recreate the selection from scratch.
Public Function GetSelectionShapeFromCurrentTool() As PD_SelectionShape

    Select Case g_CurrentTool
    
        Case SELECT_RECT
            GetSelectionShapeFromCurrentTool = ss_Rectangle
            
        Case SELECT_CIRC
            GetSelectionShapeFromCurrentTool = ss_Circle
        
        Case SELECT_LINE
            GetSelectionShapeFromCurrentTool = ss_Line
            
        Case SELECT_POLYGON
            GetSelectionShapeFromCurrentTool = ss_Polygon
            
        Case SELECT_LASSO
            GetSelectionShapeFromCurrentTool = ss_Lasso
            
        Case SELECT_WAND
            GetSelectionShapeFromCurrentTool = ss_Wand
            
        Case Else
            GetSelectionShapeFromCurrentTool = -1
    
    End Select
    
End Function

'The inverse of "getSelectionShapeFromCurrentTool", above
Public Function GetRelevantToolFromSelectShape() As PDTools

    If (g_OpenImageCount > 0) Then

        If (Not pdImages(g_CurrentImage).mainSelection Is Nothing) Then

            Select Case pdImages(g_CurrentImage).mainSelection.GetSelectionShape
            
                Case ss_Rectangle
                    GetRelevantToolFromSelectShape = SELECT_RECT
                    
                Case ss_Circle
                    GetRelevantToolFromSelectShape = SELECT_CIRC
                
                Case ss_Line
                    GetRelevantToolFromSelectShape = SELECT_LINE
                
                Case ss_Polygon
                    GetRelevantToolFromSelectShape = SELECT_POLYGON
                    
                Case ss_Lasso
                    GetRelevantToolFromSelectShape = SELECT_LASSO
                    
                Case ss_Wand
                    GetRelevantToolFromSelectShape = SELECT_WAND
                
                Case Else
                    GetRelevantToolFromSelectShape = -1
            
            End Select
            
        Else
            GetRelevantToolFromSelectShape = -1
        End If
            
    Else
        GetRelevantToolFromSelectShape = -1
    End If

End Function

'All selection tools share the same main panel on the options toolbox, but they have different subpanels that contain their
' specific parameters.  Use this function to correlate the two.
Public Function GetSelectionSubPanelFromCurrentTool() As Long

    Select Case g_CurrentTool
    
        Case SELECT_RECT
            GetSelectionSubPanelFromCurrentTool = 0
            
        Case SELECT_CIRC
            GetSelectionSubPanelFromCurrentTool = 1
        
        Case SELECT_LINE
            GetSelectionSubPanelFromCurrentTool = 2
            
        Case SELECT_POLYGON
            GetSelectionSubPanelFromCurrentTool = 3
            
        Case SELECT_LASSO
            GetSelectionSubPanelFromCurrentTool = 4
            
        Case SELECT_WAND
            GetSelectionSubPanelFromCurrentTool = 5
        
        Case Else
            GetSelectionSubPanelFromCurrentTool = -1
    
    End Select
    
End Function

Public Function GetSelectionSubPanelFromSelectionShape(ByRef srcImage As pdImage) As Long

    Select Case srcImage.mainSelection.GetSelectionShape
    
        Case ss_Rectangle
            GetSelectionSubPanelFromSelectionShape = 0
            
        Case ss_Circle
            GetSelectionSubPanelFromSelectionShape = 1
        
        Case ss_Line
            GetSelectionSubPanelFromSelectionShape = 2
            
        Case ss_Polygon
            GetSelectionSubPanelFromSelectionShape = 3
            
        Case ss_Lasso
            GetSelectionSubPanelFromSelectionShape = 4
            
        Case ss_Wand
            GetSelectionSubPanelFromSelectionShape = 5
        
        Case Else
            'Debug.Print "WARNING!  Selection_Handler.getSelectionSubPanelFromSelectionShape() was called, despite a selection not being active!"
            GetSelectionSubPanelFromSelectionShape = -1
    
    End Select
    
End Function

'Selections can be initiated several different ways.  To cut down on duplicated code, all new selection instances are referred
' to this function.  Initial X/Y values are required.
Public Sub InitSelectionByPoint(ByVal x As Double, ByVal y As Double)

    'Activate the attached image's primary selection
    pdImages(g_CurrentImage).selectionActive = True
    pdImages(g_CurrentImage).mainSelection.LockRelease
    
    'Reflect all current selection tool settings to the active selection object
    Dim curShape As PD_SelectionShape
    curShape = Selection_Handler.GetSelectionShapeFromCurrentTool()
    With pdImages(g_CurrentImage).mainSelection
        .SetSelectionShape curShape
        If (curShape <> ss_Wand) Then .SetSelectionProperty sp_Area, toolpanel_Selections.cboSelArea(Selection_Handler.GetSelectionSubPanelFromCurrentTool).ListIndex
        .SetSelectionProperty sp_Smoothing, toolpanel_Selections.cboSelSmoothing.ListIndex
        .SetSelectionProperty sp_FeatheringRadius, toolpanel_Selections.sltSelectionFeathering.Value
        If (curShape <> ss_Wand) Then .SetSelectionProperty sp_BorderWidth, toolpanel_Selections.sltSelectionBorder(Selection_Handler.GetSelectionSubPanelFromCurrentTool).Value
        .SetSelectionProperty sp_RoundedCornerRadius, toolpanel_Selections.sltCornerRounding.Value
        .SetSelectionProperty sp_LineWidth, toolpanel_Selections.sltSelectionLineWidth.Value
        If (curShape = ss_Polygon) Then .SetSelectionProperty sp_PolygonCurvature, toolpanel_Selections.sltPolygonCurvature.Value
        If (curShape = ss_Lasso) Then .SetSelectionProperty sp_SmoothStroke, toolpanel_Selections.sltSmoothStroke.Value
        If (curShape = ss_Wand) Then
            .SetSelectionProperty sp_WandTolerance, toolpanel_Selections.sltWandTolerance.Value
            .SetSelectionProperty sp_WandSampleMerged, toolpanel_Selections.btsWandMerge.ListIndex
            .SetSelectionProperty sp_WandSearchMode, toolpanel_Selections.btsWandArea.ListIndex
            .SetSelectionProperty sp_WandCompareMethod, toolpanel_Selections.cboWandCompare.ListIndex
        End If
    End With
    
    'Set the first two coordinates of this selection to this mouseclick's location
    pdImages(g_CurrentImage).mainSelection.SetInitialCoordinates x, y
    SyncTextToCurrentSelection g_CurrentImage
    pdImages(g_CurrentImage).mainSelection.RequestNewMask
    
    'Make the selection tools visible
    SetUIGroupState PDUI_Selections, True
    SetUIGroupState PDUI_SelectionTransforms, True
    
    'Redraw the screen
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
                        
End Sub

'Are selections currently allowed?  Program states like "no open images" prevent selections from ever being created, and individual
' functions can use this function to determine it.  Passing TRUE for the transformableMatters param will add a check for an existing,
' transformable-type selection (squares, etc) to the evaluation list.
Public Function SelectionsAllowed(ByVal transformableMatters As Boolean) As Boolean

    If (g_OpenImageCount > 0) Then
        If pdImages(g_CurrentImage).selectionActive And (Not pdImages(g_CurrentImage).mainSelection Is Nothing) Then
            If (Not pdImages(g_CurrentImage).mainSelection.GetAutoRefreshSuspend()) Then
                If transformableMatters Then
                    SelectionsAllowed = pdImages(g_CurrentImage).mainSelection.IsTransformable
                Else
                    SelectionsAllowed = True
                End If
            Else
                SelectionsAllowed = False
            End If
        Else
            SelectionsAllowed = False
        End If
    Else
        SelectionsAllowed = False
    End If
    
End Function

'Whenever a selection render setting changes (like switching between outline and highlight mode), you must call this function
' so that we can cache the new render settings.
Public Sub NotifySelectionRenderChange()
    m_CurSelectionMode = toolpanel_Selections.cboSelRender.ListIndex
    m_CurSelectionColor = toolpanel_Selections.csSelectionHighlight.Color
End Sub

Public Function GetCurrentPD_SelectionRenderMode() As PD_SelectionRender
    GetCurrentPD_SelectionRenderMode = m_CurSelectionMode
End Function

Public Function GetCurrentPD_SelectionRenderColor() As Long
    GetCurrentPD_SelectionRenderColor = m_CurSelectionColor
End Function
