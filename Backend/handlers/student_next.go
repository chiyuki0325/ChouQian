package handlers

import (
	"Backend/chouqian"
	"Backend/config"
	"Backend/persistent"
	"Backend/types"
	"github.com/gin-gonic/gin"
	"strconv"
	"time"
)

func SetNextStudent(context *gin.Context) {
	lastRequestTime := persistent.Get("last_request_time")
	if lastRequestTime != "" {
		lastRequestTimeStamp, _ := strconv.ParseInt(lastRequestTime, 10, 64)
		if (time.Now().Unix() - lastRequestTimeStamp) < (int64(config.Config.ChouQian.ApiCooldown * 60)) {
			context.JSON(403, gin.H{
				"code":           403,
				"message":        "请求过于频繁",
				"time_remaining": int64(config.Config.ChouQian.ApiCooldown*60) - (time.Now().Unix() - lastRequestTimeStamp),
			})
			return
		}
	}
	persistent.Set("last_request_time", strconv.FormatInt(time.Now().Unix(), 10))
	var req types.SetNextStudentRequest
	_ = context.BindJSON(&req)
	chouqian.NextStudent = types.Student{
		Name:   req.Name,
		Number: req.Number,
	}
	context.JSON(200, gin.H{
		"code":    200,
		"message": "设置成功",
	})
}
