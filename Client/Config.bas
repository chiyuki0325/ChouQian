Attribute VB_Name = "Config"
Option Explicit

Public Config As ConfigModel

Type ConfigModel
    Host As String
End Type

Function LoadConfig() As ConfigModel
    Open App.Path & "\config.json" For Input As #8
        Dim ConfigFileContent$
        Input #8, ConfigFileContent
        Dim ConfigFileDict As Dictionary
        Set ConfigFileDict = JSON.parse(ConfigFileContent)
        Dim ReturnConfig As ConfigModel
        ReturnConfig.Host = ConfigFileDict.item("host")
        LoadConfig = ReturnConfig
    Close #8
End Function
