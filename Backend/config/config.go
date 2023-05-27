package config

import (
	"Backend/types"
	"Backend/utils"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
)

var Config = loadConfig()

func loadConfig() types.Config {
	executablePath, _ := exec.LookPath(os.Args[0])
	baseDir := filepath.Dir(executablePath)
	jsonData, err := os.ReadFile(baseDir + "/chouqian_backend.json")
	utils.ErrorThenPanic(err)
	var config types.Config
	_ = json.Unmarshal(jsonData, &config)
	return config
}
