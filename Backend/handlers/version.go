package handlers

import "github.com/gin-gonic/gin"

func Version(context *gin.Context) {
	context.JSON(
		200,
		gin.H{
			"code":    200,
			"version": "3.3.0",
		},
	)
}
