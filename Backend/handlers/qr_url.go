package handlers

import (
	"github.com/gin-gonic/gin"
)

func QrUrl(context *gin.Context) {
	context.JSON(
		200,
		gin.H{
			"code": 200,
			"url":  getFrontendUrl(),
		})
}
