#Requires AutoHotkey v2.0
#SingleInstance Force

; Ctrl+Space → simulate context menu key (AppsKey)
^space:: Send("{AppsKey}")

; Right Win → simulate language switch 
RWin::
{
    Send "{LAlt down}{Shift down}{Shift up}{LAlt up}"
}
