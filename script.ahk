#Requires AutoHotkey v2.0
#SingleInstance Force

; Ctrl+Space → simulate context menu key (AppsKey)
^space:: Send("{AppsKey}")

; Right Alt → simulate language switch 
~RAlt Up::{
    if (A_PriorKey = "RAlt")
        Send "{LAlt down}{Shift down}{Shift up}{LAlt up}"
}
