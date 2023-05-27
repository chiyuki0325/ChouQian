package handlers

import (
	"Backend/chouqian"
	"github.com/gin-gonic/gin"
	"net/http"
)

func GetRandomStudent(context *gin.Context) {
	student := chouqian.GetRandomStudent()
	context.JSON(
		http.StatusOK,
		gin.H{
			"code":   200,
			"name":   student.Name,
			"number": student.Number,
		},
	)
}
