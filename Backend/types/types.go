package types

// 配置文件最上层

type Config struct {
	ChouQian ChouQianConfig `json:"chouqian"`
	Api      ApiConfig      `json:"api"`
	Qr       QrConfig       `json:"qr"`
}

// .chouqian

type ChouQianConfig struct {
	Students      [][]string    `json:"students"`
	SpecialConfig SpecialConfig `json:"special_config"`
	ApiCooldown   int           `json:"api_cooldown"`
	RandomMode    string        `json:"random_mode"`
}

// .api

type ApiConfig struct {
	Host string `json:"host"`
	Mode string `json:"mode"`
}

// .qr

type QrConfig struct {
	PreferredPrefix string   `json:"preferred_prefix"`
	BlockedPrefixes []string `json:"blocked_prefixes"`
}

//.chouqian.special_config

type SpecialConfig struct {
	BaoDi        []BaoDi       `json:"baodi"`
	Replacements []Replacement `json:"replacements"`
}

//.chouqian.special_config.baodi

type BaoDi struct {
	Number     string `json:"number"`
	BaoDiCount int    `json:"baodi_count"`
}

//.chouqian.special_config.replacements

type Replacement struct {
	Number  string `json:"number"`
	Key     string `json:"key"`
	ValueTo string `json:"value_to"`
	Rate    int    `json:"rate"`
}

// Student 结构体

type Student struct {
	Name   string
	Number string
}

// API 请求结构体

type SetNextStudentRequest struct {
	Name   string `json:"name"`
	Number string `json:"number"`
}
