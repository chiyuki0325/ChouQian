Attribute VB_Name = "Config"
Option Explicit

Public Config As Dictionary

Sub LoadConfig()
    Dim FSO As New FileSystemObject, Stream As TextStream
    Set Stream = FSO.OpenTextFile(FileName:=App.Path & "\config.json", IOMode:=IOMode.ForReading)
    Set Config = JSON.parse(Stream.ReadAll)
End Sub
