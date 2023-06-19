package handlers

import (
	"Backend/config"
	"github.com/gin-gonic/gin"
	"github.com/skip2/go-qrcode"
	"net"
	"strings"
)

func QrImage(context *gin.Context) {
	pngImage, _ := qrcode.Encode(
		getFrontendUrl(),
		qrcode.Medium,
		256,
	)
	context.Data(
		200,
		"image/png",
		pngImage,
	)
}

func getFrontendUrl() string {
	return "http://" + getCurrentIpAddress() + ":" + strings.Split(config.Config.Api.Host, ":")[1] + "/ui"
}

func getCurrentIpAddress() string {
	var addresses []net.Addr
	var selectedAddresses []string
	addresses, _ = net.InterfaceAddrs()
	for _, addr := range addresses {
		var isBlocked bool
		for _, blockedIpPrefix := range config.Config.Qr.BlockedPrefixes {
			if strings.HasPrefix(addr.String(), blockedIpPrefix) {
				isBlocked = true
				break
			}
		}
		if !isBlocked {
			selectedAddresses = append(selectedAddresses, strings.Split(addr.String(), "/")[0])
		}
	}
	for _, addr := range selectedAddresses {
		if strings.HasPrefix(addr, config.Config.Qr.PreferredPrefix) {
			return addr
		}
	}
	return selectedAddresses[0]
}
