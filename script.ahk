#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Lib\UIA.ahk

; Ctrl+Space → simulate context menu key (AppsKey)
^space:: Send("{AppsKey}")

; Right Win → simulate language switch 
RWin:: Send "{LAlt down}{Shift down}{Shift up}{LAlt up}"

; Ctrl+Alt+Space → simulate opening DropDown in VS' text editor as it has no way to set hotkey in VS itself
; TODO: disable hotkey if text editor is not open in VS; test how it handles multiple VS code windows from one devenv process
^!Space::
{
    hwnd := WinExist("ahk_exe devenv.exe")
    if !hwnd {
        MsgBox "Visual Studio (devenv.exe) не найдено."
        return
    }
    WinActivate hwnd
    WinWaitActive hwnd, , 0.8

    root := UIA.ElementFromHandle(hwnd)
    combo := 0

    ; 1) По AutomationId
    try {
        combo := root.FindFirst({AutomationId:"FunctionsList"})
    } catch as e {
        ; игнорируем
    }

    ; 2) По UIA-Name (Members)
    if !combo {
        try {
            combo := root.FindFirst({Type:"ComboBox", Name:"Members"})
        } catch as e {
            ; игнорируем
        }
    }

    ; 3) Фоллбэк: перебор всех ComboBox + лог
    if !combo {
        dbg := ""
        try {
            all := root.FindAll({Type:"ComboBox"})
            for el in all {
                nm := "", id := ""
                try nm := el.Name
                try id := el.AutomationId
                dbg .= "Name:`t" (nm?nm:"<empty>") " | Id:`t" (id?id:"<empty>") "`n"
                if (id = "FunctionsList") {
                    combo := el
                    break
                }
                if (!combo && el.HasPattern("ExpandCollapse") && el.HasPattern("Selection"))
                    combo := el
            }
        } catch as e {
            ; игнор
        }
        if (!combo && dbg != "")
            MsgBox "Найденные ComboBox'ы:`n`n" dbg
    }

    if !combo {
        MsgBox "Не удалось найти EditorNavigationComboBox."
        return
    }

    combo.SetFocus()
    Sleep 80
    try {
        combo.Expand()
    } catch as e {
        try combo.Click()
    }
}

; Spotify
; Ctrl+Alt+1 — следующая песня
^!1::Send ("{Media_Next}")

; Ctrl+Alt+2 — предыдущая песня
^!2::Send ("{Media_Prev}")

; Ctrl+Alt+3 — play/pause
^!3::Send ("{Media_Play_Pause}")
