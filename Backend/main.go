package main

import (
	"Backend/config"
	"Backend/handlers"
	"Backend/utils"
	"github.com/gin-gonic/contrib/static"
	"github.com/gin-gonic/gin"
	"os"
)

func initRouter() *gin.Engine {
	frontendPath := os.Args[1]
	router := gin.Default()
	router.Use(static.Serve("/", static.LocalFile(frontendPath, false)))
	studentRouter := router.Group("/api/student")
	studentRouter.GET("/random", handlers.GetRandomStudent)
	studentRouter.POST("/next", handlers.SetNextStudent)
	studentRouter.GET("/list", handlers.GetStudentList)
	qrRouter := router.Group("/api/qr")
	qrRouter.GET("/image", handlers.QrImage)
	qrRouter.GET("/url", handlers.QrUrl)
	router.GET("/api/reconfigure", handlers.Reconfigure)
	router.GET("/api/version", handlers.Version)
	return router
}

func main() {
	if config.Config.Api.Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}
	router := initRouter()
	err := router.Run(config.Config.Api.Host)
	utils.ErrorThenPanic(err)
}
