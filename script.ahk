#Requires AutoHotkey v2.0
#SingleInstance Force

; =========================================================
; Primary Selection + Attach-as-file helper (AutoHotkey v2)
; ---------------------------------------------------------
; Features:
;   • Linux-like “primary selection”: select text → auto-captured
;   • Middle mouse click (MButton): paste captured text (without touching real clipboard)
;   • Ctrl + MButton: paste captured text as an attachment/file (CF_HDROP)
;   • Ctrl + Alt + X: take current clipboard text → save → paste as attachment
;   • Ctrl + Space: open context menu (AppsKey)
;   • XButton1: double-click (handy for some mice)
;
; Notes:
;   • The real clipboard is restored after synthetic pastes.
;   • By default, we only middle-paste when a text caret exists — so browser
;     autoscroll on MButton isn’t broken. Toggle in settings.
; =========================================================

; -------------------------- SETTINGS --------------------------
global gOnlyWhenCaret := true    ; paste on MButton only when a caret is present
global gDragThreshold := 3       ; pixels to treat as a selection drag
global gDropEffect   := 1        ; 1=COPY, 2=MOVE for CF_HDROP paste
global gTempPrefix   := "Sel2File_"
global gPrimaryText  := ""       ; in-memory “primary selection”
global gPrimaryPath  := ""       ; temp file path for primary selection

; -------------------------- HOTKEYS ---------------------------
; Ctrl+Space → simulate context menu key (AppsKey)
^space:: Send("{AppsKey}")

; Mouse XButton1 → double click
XButton1:: Click(2)

; Ctrl+Alt+X — current clipboard → temp file → paste as attachment
^!x:: {
    text := A_Clipboard
    if (text = "") {
        Tip("Clipboard is empty or not text")
        return
    }
    ClipSaved := ClipboardAll()
    path := SaveToTemp(text)
    PasteFilesAsAttachment([path], ClipSaved)
}

; Middle button — paste primary text (if caret exists)
MButton:: {
    global gPrimaryText, gOnlyWhenCaret
    if (gOnlyWhenCaret && !CaretGetPos(&cx, &cy)) {
        SendEvent("{MButton}")  ; pass through to keep autoscroll intact
        return
    }
    if (gPrimaryText = "") {
        SendEvent("{MButton}")
        return
    }
    ClipSaved := ClipboardAll()
    A_Clipboard := gPrimaryText
    Sleep(30)
    Send("^v")
    SetTimer(() => (A_Clipboard := ClipSaved), -200)
}

; Ctrl + Middle button — paste primary as an attachment (CF_HDROP)
^MButton:: {
    global gPrimaryPath, gDropEffect
    if (gPrimaryPath = "" || !FileExist(gPrimaryPath)) {
        SendEvent("{MButton}")
        return
    }
    ClipSaved := ClipboardAll()
    if SetClipboardFiles([gPrimaryPath], gDropEffect) {
        Sleep(60)
        Send("^v")
        SetTimer(() => (A_Clipboard := ClipSaved), -500)
    } else {
        SendEvent("{MButton}")
    }
}

; ------------------- PRIMARY SELECTION CAPTURE -------------------
; Track mouse drag to detect a selection and capture it on LButton release.
global gSelStartX := 0, gSelStartY := 0

~LButton:: {
    global gSelStartX, gSelStartY
    MouseGetPos &x, &y
    gSelStartX := x, gSelStartY := y
}

~LButton Up:: {
    global gSelStartX, gSelStartY, gDragThreshold
    MouseGetPos &x2, &y2
    if (Abs(x2 - gSelStartX) < gDragThreshold && Abs(y2 - gSelStartY) < gDragThreshold)
        return  ; simple click — not a selection
    CapturePrimary()
}

CapturePrimary() {
    ; Grab current selection via Ctrl+C without altering user clipboard.
    global gPrimaryText, gPrimaryPath
    ClipSaved := ClipboardAll()
    A_Clipboard := ""
    Send("^c")
    if ClipWait(0.25) && (A_Clipboard != "") {
        gPrimaryText := A_Clipboard
        gPrimaryPath := A_Temp "\PrimarySelection.txt"
        f := FileOpen(gPrimaryPath, "w", "UTF-8-RAW")
        f.Write(gPrimaryText), f.Close()
        ; Tip("Primary updated: " . SubStr(gPrimaryText, 1, 60))
    }
    A_Clipboard := ClipSaved
}

; ------------------------- ATTACHMENT PASTE -------------------------
PasteFilesAsAttachment(paths, ClipSaved) {
    global gDropEffect
    if !SetClipboardFiles(paths, gDropEffect) {
        Tip("Failed to prepare CF_HDROP clipboard")
        return
    }
    Sleep(100)
    Send("^v")                              ; paste as file/attachment
    SetTimer(() => (A_Clipboard := ClipSaved), -400)
}

; Put file list into clipboard as CF_HDROP (+ Preferred DropEffect)
; paths — array of absolute paths, e.g. ["C:\file1.txt", "C:\file2.txt"]
; dropEffect — 1=COPY, 2=MOVE
SetClipboardFiles(paths, dropEffect := 1) {
    ; Build double-null-terminated UTF-16 list (MULTI_SZ)
    multi := ""
    for _, p in paths
        multi .= StrReplace(p, "/", "\") . Chr(0)
    multi .= Chr(0)

    ; Prepare DROPFILES header (20 bytes) + strings
    chars := StrPut(multi, "UTF-16")
    buf := Buffer(20 + chars*2, 0)
    NumPut("UInt", 20, buf, 0)      ; pFiles offset
    NumPut("Int",  0,  buf, 4)      ; pt.x
    NumPut("Int",  0,  buf, 8)      ; pt.y
    NumPut("Int",  0,  buf,12)      ; fNC
    NumPut("Int",  1,  buf,16)      ; fWide = TRUE (Unicode)
    StrPut(multi, buf.Ptr + 20, "UTF-16")

    if !DllCall("OpenClipboard", "Ptr", 0, "Int")
        return false
    DllCall("EmptyClipboard")

    GMEM_MOVEABLE := 0x0002, GMEM_ZEROINIT := 0x0040
    flags := GMEM_MOVEABLE | GMEM_ZEROINIT
    size  := buf.Size
    hMem  := DllCall("GlobalAlloc", "UInt", flags, "UPtr", size, "UPtr")
    if !hMem {
        DllCall("CloseClipboard")
        return false
    }
    pMem := DllCall("GlobalLock", "UPtr", hMem, "UPtr")
    DllCall("RtlMoveMemory", "Ptr", pMem, "Ptr", buf.Ptr, "UPtr", size)
    DllCall("GlobalUnlock", "UPtr", hMem)
    DllCall("SetClipboardData", "UInt", 15, "UPtr", hMem)   ; CF_HDROP = 15

    ; Optional “Preferred DropEffect” hints (COPY/MOVE)
    fmt := DllCall("RegisterClipboardFormatW", "Str", "Preferred DropEffect", "UInt")
    hEff := DllCall("GlobalAlloc", "UInt", flags, "UPtr", 4, "UPtr")
    pEff := DllCall("GlobalLock", "UPtr", hEff, "UPtr")
    NumPut("UInt", dropEffect, pEff, 0)  ; 1=COPY, 2=MOVE
    DllCall("GlobalUnlock", "UPtr", hEff)
    DllCall("SetClipboardData", "UInt", fmt, "UPtr", hEff)

    DllCall("CloseClipboard")
    return true
}

; ------------------------- FILE UTILITIES -------------------------
SaveToTemp(text) {
    global gTempPrefix
    ts   := FormatTime(, "yyyyMMdd_HHmmss")
    path := A_Temp "\" gTempPrefix ts ".txt"
    FileAppend(text, path, "UTF-8-RAW")
    return path
}

; ------------------------- UI UTILITIES -------------------------
Tip(msg, ms := 1200) {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -ms)
}
