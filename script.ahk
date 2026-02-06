#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Lib\UIA.ahk

; Ctrl+Space → simulate context menu key (AppsKey)
^space:: Send("{AppsKey}")

; Right Win → simulate language switch
RWin:: Send "{LAlt down}{Shift down}{Shift up}{LAlt up}"

^e:: Send "{Enter}"

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
        combo := root.FindFirst({ AutomationId: "FunctionsList" })
    } catch as e {
        ; игнорируем
    }

    ; 2) По UIA-Name (Members)
    if !combo {
        try {
            combo := root.FindFirst({ Type: "ComboBox", Name: "Members" })
        } catch as e {
            ; игнорируем
        }
    }

    ; 3) Фоллбэк: перебор всех ComboBox + лог
    if !combo {
        dbg := ""
        try {
            all := root.FindAll({ Type: "ComboBox" })
            for el in all {
                nm := "", id := ""
                try nm := el.Name
                try id := el.AutomationId
                dbg .= "Name:`t" (nm ? nm : "<empty>") " | Id:`t" (id ? id : "<empty>") "`n"
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
^!1:: Send ("{Media_Next}")

; Ctrl+Alt+2 — предыдущая песня
^!2:: Send ("{Media_Prev}")

; Ctrl+Alt+3 — play/pause
^!3:: Send ("{Media_Play_Pause}")

; Explorer
#HotIf WinActive("ahk_class CabinetWClass")
^!e::
{
    ; 0) отпускаем модификаторы сразу, чтобы дальнейшие Send не превращались в ^!F2
    Send "{Ctrl up}{Alt up}"

    ex := Explorer_GetWindow()
    if !ex {
        SoundBeep 1500, 100
        return
    }

    path := ex.Document.Folder.Self.Path
    if !path || !DirExist(path) {
        MsgBox "Не удалось получить реальный путь текущей папки."
        return
    }

    base := "New Text Document"
    ext  := ".txt"
    full := path "\" base ext

    i := 2
    while FileExist(full) {
        full := path "\" base " (" i ")" ext
        i++
    }

    try FileAppend "", full
    catch as e {
        MsgBox "Не удалось создать файл:`n" full "`n`n" e.Message
        return
    }

    ; 1) Дожидаемся, пока Explorer начнёт видеть файл (ParseName != "")
    item := Explorer_WaitForItem(ex, full, 1200)
    if !item {
        ; как фоллбек: refresh и ещё чуть подождать
        try ex.Document.Refresh()
        item := Explorer_WaitForItem(ex, full, 1200)
    }

    if !item {
        MsgBox "Файл создан, но Explorer не смог его увидеть для выделения:`n" full
        return
    }

    ; 2) Выделяем/фокусируем и убеждаемся, что выделение применилось
    if !Explorer_SelectItem(ex, item, 1200) {
        MsgBox "Не удалось надёжно выделить созданный файл."
        return
    }

    ; 3) Теперь можно F2 (уже без Ctrl/Alt)
    WinActivate ex.HWND
    Sleep 60
    Send "{F2}"
}
#HotIf

Explorer_GetWindow() {
    hwnd := WinActive("A")
    for w in ComObject("Shell.Application").Windows {
        try {
            if (w.HWND = hwnd)
                return w
        }
    }
    return 0
}

Explorer_WaitForItem(ex, fullPath, timeoutMs := 1000) {
    SplitPath fullPath, &name, &dir
    start := A_TickCount

    while (A_TickCount - start) < timeoutMs {
        try {
            ; важно: Explorer должен быть именно в этой папке
            if (ex.Document.Folder.Self.Path != dir)
                return 0

            item := ex.Document.Folder.ParseName(name)
            if item
                return item
        }
        Sleep 50
    }
    return 0
}

Explorer_SelectItem(ex, item, timeoutMs := 1000) {
    start := A_TickCount
    flags := 1|4|8  ; SELECT + FOCUSED + ENSUREVISIBLE

    while (A_TickCount - start) < timeoutMs {
        try {
            ex.Document.SelectItem(item, flags)
            Sleep 50

            ; проверяем, что он реально в SelectedItems
            sel := ex.Document.SelectedItems
            if sel && sel.Count >= 1 {
                try {
                    if (sel.Item(0).Path = item.Path)
                        return true
                }
            }
        }
        Sleep 50
    }
    return false
}
