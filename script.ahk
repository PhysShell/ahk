#Requires AutoHotkey v2.0
#SingleInstance Force
#Include Lib\UIA.ahk

EnsureStartupShortcut()
InitExplorerAutoSelectTop()

global g_ExplorerNameHook := 0
global g_ExplorerWinEventCb := 0
global g_ExplorerLastPathByHwnd := Map()
global g_ExplorerShellMsg := 0

InitExplorerAutoSelectTop() {
    global g_ExplorerWinEventCb, g_ExplorerNameHook, g_ExplorerShellMsg

    ; Ловим создание/активацию окон Explorer
    g_ExplorerShellMsg := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK", "UInt")
    DllCall("RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
    OnMessage(g_ExplorerShellMsg, Explorer_ShellHookProc)

    ; Ловим изменение имени окна (title), что часто происходит при смене папки/вкладки
    ; EVENT_OBJECT_NAMECHANGE = 0x800C
    g_ExplorerWinEventCb := CallbackCreate(Explorer_WinEventProc, "Fast")
    g_ExplorerNameHook := DllCall(
        "SetWinEventHook",
        "UInt", 0x800C,
        "UInt", 0x800C,
        "Ptr", 0,
        "Ptr", g_ExplorerWinEventCb,
        "UInt", 0,
        "UInt", 0,
        "UInt", 0,   ; WINEVENT_OUTOFCONTEXT
        "Ptr"
    )
}

Explorer_ShellHookProc(wParam, lParam, msg, hwnd) {
    ; HSHELL_WINDOWCREATED = 1
    ; HSHELL_WINDOWACTIVATED = 4
    if (wParam = 1 || wParam = 4) {
        wh := lParam
        if !wh
            return
        if !Explorer_IsRealWindow(wh)
            return

        SetTimer ((*) => Explorer_HandlePossibleNav(wh)), -120
    }
}

Explorer_WinEventProc(hWinEventHook, event, hwnd, idObject, idChild, idEventThread, dwmsEventTime) {
    ; Нас интересует только top-level окно
    if (idObject != 0 || idChild != 0)
        return
    if !hwnd
        return
    if !Explorer_IsRealWindow(hwnd)
        return

    SetTimer ((*) => Explorer_HandlePossibleNav(hwnd)), -120
}

Explorer_IsRealWindow(hwnd) {
    try {
        if (WinGetClass("ahk_id " hwnd) != "CabinetWClass")
            return false
        if (WinGetProcessName("ahk_id " hwnd) != "explorer.exe")
            return false
    } catch {
        return false
    }
    return true
}

Explorer_HandlePossibleNav(hwnd) {
    global g_ExplorerLastPathByHwnd

    if !WinExist("ahk_id " hwnd)
        return

    ex := Explorer_GetWindowByHwnd(hwnd)
    if !ex
        return

    path := ""
    try path := ex.Document.Folder.Self.Path
    catch
        return

    if !path || !DirExist(path)
        return

    key := String(hwnd)
    oldPath := g_ExplorerLastPathByHwnd.Has(key) ? g_ExplorerLastPathByHwnd[key] : ""

    ; Если путь не менялся, не дёргаемся
    if (oldPath = path)
        return

    g_ExplorerLastPathByHwnd[key] := path

    ; Дадим Explorer дорисовать содержимое
    SetTimer ((*) => Explorer_SelectTopVisibleishItem(hwnd)), -160
}

Explorer_SelectTopVisibleishItem(hwnd) {
    if !WinExist("ahk_id " hwnd)
        return
    if !WinActive("ahk_id " hwnd)
        return
    if !Explorer_IsRealWindow(hwnd)
        return

    ex := Explorer_GetWindowByHwnd(hwnd)
    if !ex
        return

    item := Explorer_GetFirstFolderItem(ex)
    if !item
        return

    flags := 1 | 4 | 8 ; SELECT + FOCUSED + ENSUREVISIBLE

    ; Пытаемся несколько раз, потому что Explorer любит перетаптывать selection
    Loop 3 {
        try ex.Document.SelectItem(item, flags)
        Sleep 60
    }
}

Explorer_GetFirstFolderItem(ex) {
    try {
        items := ex.Document.Folder.Items
        if !items
            return 0

        count := items.Count
        if (count < 1)
            return 0

        return items.Item(0)
    } catch {
        return 0
    }
}

Explorer_GetWindowByHwnd(hwnd) {
    for w in ComObject("Shell.Application").Windows {
        try {
            if (w.HWND = hwnd)
                return w
        }
    }
    return 0
}


; Remap CapsLock to LControl
SetCapsLockState "AlwaysOff"
CapsLock::LControl

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
    ext := ".txt"
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

; Ctrl+Shift+T -> open current Explorer path in Windows Terminal,
; or default terminal if Explorer is not active
^+t::
{
    Send "{Ctrl up}{Shift up}"

    path := Explorer_GetCurrentPath()
    if (path)
        OpenTerminalHere(path)
    else
        OpenDefaultTerminal()
}

; Ctrl+Shift+Alt+T -> open current Explorer path in WSL inside Windows Terminal,
; or default WSL terminal if Explorer is not active
^+!t::
{
    Send "{Ctrl up}{Shift up}{Alt up}"

    path := Explorer_GetCurrentPath()
    if (path)
        OpenWslTerminalHere(path)
    else
        OpenDefaultWslTerminal()
}

OpenDefaultTerminal() {
    wt := FindWindowsTerminal()
    if !wt {
        MsgBox "Не найден wt.exe (Windows Terminal)."
        return
    }

    Run '"' wt '"'
}

OpenDefaultWslTerminal() {
    wt := FindWindowsTerminal()
    if !wt {
        MsgBox "Не найден wt.exe (Windows Terminal)."
        return
    }

    Run '"' wt '" wsl.exe'
}

Explorer_GetCurrentPath() {
    ex := Explorer_GetWindow()
    if !ex
        return ""

    try path := ex.Document.Folder.Self.Path
    catch
        path := ""

    if !path || !DirExist(path)
        return ""

    return path
}

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
    flags := 1 | 4 | 8  ; SELECT + FOCUSED + ENSUREVISIBLE

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

OpenTerminalHere(path) {
    wt := FindWindowsTerminal()
    if !wt {
        MsgBox "Не найден wt.exe (Windows Terminal)."
        return
    }

    Run '"' wt '" -d "' path '"'
}

OpenWslTerminalHere(winPath) {
    wt := FindWindowsTerminal()
    if !wt {
        MsgBox "Не найден wt.exe (Windows Terminal)."
        return
    }

    wslPath := WindowsPathToWslPath(winPath)
    if !wslPath {
        MsgBox "Не удалось преобразовать путь в WSL:`n" winPath
        return
    }

    ; Запускаем WSL и заходим в нужную папку
    ; exec bash оставляет вас в интерактивной shell
    cmd := '"' wt '" wsl.exe bash -lc "cd ' . QuoteForBash(wslPath) . ' && exec bash"'
    Run cmd
}

FindWindowsTerminal() {
    localAppData := EnvGet("LOCALAPPDATA")
    programFiles := EnvGet("ProgramFiles")

    candidates := [
        localAppData "\Microsoft\WindowsApps\wt.exe",
        programFiles "\WindowsApps\wt.exe",
        "wt.exe"
    ]

    for c in candidates {
        if (c = "wt.exe")
            return c
        if FileExist(c)
            return c
    }
    return ""
}

WindowsPathToWslPath(winPath) {
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec(A_ComSpec ' /c wsl.exe wslpath -a "' winPath '"')
        stdout := exec.StdOut.ReadAll()
        stderr := exec.StdErr.ReadAll()

        result := Trim(stdout, "`r`n`t ")
        if (result != "")
            return result
    } catch as e {
    }

    ; Фоллбэк для обычных дисков C:\... -> /mnt/c/...
    if RegExMatch(winPath, "^([A-Za-z]):\\(.*)$", &m) {
        drive := StrLower(m[1])
        rest := StrReplace(m[2], "\", "/")
        return "/mnt/" drive "/" rest
    }

    return ""
}

QuoteForBash(s) {
    ; Безопасное экранирование для одинарных кавычек в bash:
    ; abc'def -> 'abc'\''def'
    return "'" StrReplace(s, "'", "'\''") "'"
}

EnsureStartupShortcut() {
    startupDir := A_Startup
    linkPath := startupDir "\autostart.ahk.lnk"

    ; Путь к текущему скрипту
    scriptPath := A_ScriptFullPath

    ; Если скрипт запущен не как файл, а как-то экзотически, не лезем
    if !FileExist(scriptPath)
        return

    ; Если ярлык уже есть, ничего не делаем
    if FileExist(linkPath)
        return

    try {
        FileCreateShortcut scriptPath, linkPath, A_WorkingDir, "", "My AHK hotkeys"
    } catch as e {
        MsgBox "Не удалось добавить скрипт в автозагрузку:`n`n" e.Message
    }
}
