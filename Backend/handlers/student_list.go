package handlers

import (
	"Backend/config"
	"github.com/gin-gonic/gin"
	"net/http"
)

func GetStudentList(context *gin.Context) {
	studentList := config.Config.ChouQian.Students
	context.JSON(
		http.StatusOK,
		gin.H{
			"code":         200,
			"student_list": studentList,
		},
	)
}
