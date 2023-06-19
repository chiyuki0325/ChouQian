package main

import (
	"Backend/config"
	"Backend/handlers"
	"Backend/utils"
	"github.com/gin-gonic/gin"
	"os"
)

func initRouter() *gin.Engine {
	frontendPath := os.Args[1]
	router := gin.Default()
	apiRouter := router.Group("/api")
	studentRouter := apiRouter.Group("/student")
	studentRouter.GET("/random", handlers.GetRandomStudent)
	studentRouter.POST("/next", handlers.SetNextStudent)
	studentRouter.GET("/list", handlers.GetStudentList)
	qrRouter := apiRouter.Group("/qr")
	qrRouter.GET("/image", handlers.QrImage)
	qrRouter.GET("/url", handlers.QrUrl)
	apiRouter.GET("/reconfigure", handlers.Reconfigure)
	apiRouter.GET("/version", handlers.Version)
	router.Static("/ui", frontendPath)
	router.Static("/favicon.ico", frontendPath+"/favicon.ico")
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
