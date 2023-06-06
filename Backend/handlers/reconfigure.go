package handlers

import (
	"Backend/chouqian"
	"Backend/config"
	"github.com/gin-gonic/gin"
	"net/http"
)

func Reconfigure(context *gin.Context) {
	config.Reconfigure()
	chouqian.Reconfigure()
	context.JSON(
		http.StatusOK,
		gin.H{
			"code": 200,
		},
	)
}
