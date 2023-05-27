package handlers

import "github.com/gin-gonic/gin"

func HelloWorld(context *gin.Context) {
	context.JSON(
		200,
		gin.H{
			"code":    200,
			"message": "Hello, World!",
			"version": "3.1.0",
		},
	)
}
