package persistent

import (
	"Backend/utils"
	"encoding/json"
	"os"
	"runtime"
)

func getAppDataPath() string {
	switch runtime.GOOS {
	case "windows":
		return os.Getenv("APPDATA")
	case "darwin":
		return os.Getenv("HOME") + "/Library/Application Support"
	case "linux":
		return os.Getenv("HOME") + "/.config"
	default:
		return "."
	}
}

var appDataPath = getAppDataPath()
var filePath = appDataPath + "/ChouQian.json"

func getPersistentMap() map[string]string {
	if _, err := os.Stat(filePath); os.IsNotExist(err) {
		err := os.WriteFile(filePath, []byte("{}"), 0644)
		utils.ErrorThenPanic(err)
		return make(map[string]string)
	}
	fileContent, _ := os.ReadFile(filePath)
	var data map[string]string
	err := json.Unmarshal(fileContent, &data)
	utils.ErrorThenPanic(err)
	return data
}

func savePersistentMap(data map[string]string) {
	jsonData, _ := json.Marshal(data)
	err := os.WriteFile(filePath, jsonData, 0644)
	utils.ErrorThenPanic(err)
}

func Get(key string) string {
	data := getPersistentMap()
	return data[key]
}

func Set(key string, value string) {
	data := getPersistentMap()
	data[key] = value
	savePersistentMap(data)
}
