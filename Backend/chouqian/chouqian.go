package chouqian

import (
	"Backend/config"
	"Backend/types"
	cryptoRand "crypto/rand"
	"math/big"
	"math/rand"
	"time"
)

var StudentList []types.Student = initStudentList()
var NextStudent types.Student = types.Student{}
var BaoDi map[string]int = initBaoDi()
var reader = cryptoRand.Reader

func Reconfigure() {
	StudentList = initStudentList()
	BaoDi = initBaoDi()
}

func initStudentList() []types.Student {
	var studentList []types.Student
	for _, student := range config.Config.ChouQian.Students {
		studentList = append(studentList, types.Student{
			Name:   student[1],
			Number: student[0],
		})
	}
	rand.New(rand.NewSource(time.Now().UnixNano())).Shuffle(len(studentList), func(i, j int) {
		studentList[i], studentList[j] = studentList[j], studentList[i]
	})
	return studentList
}

func initBaoDi() map[string]int {
	baoDi := make(map[string]int)
	for _, baodi := range config.Config.ChouQian.SpecialConfig.BaoDi {
		baoDi[baodi.Number] = 0
	}
	return baoDi
}

func removeStudent(sourceArray []types.Student, index int) []types.Student {
	return append(sourceArray[:index], sourceArray[index+1:]...)
}

func GetRandomStudent() types.Student {
	// 抽取随机学生
	// 如果通过 API 设置了 NextStudent，那么就返回 NextStudent
	if NextStudent.Name != "" {
		student := NextStudent
		// 重置 NextStudent
		NextStudent = types.Student{}
		return student
	}
	// 检查保底机制
	baoDiConfig := config.Config.ChouQian.SpecialConfig.BaoDi
	for _, baodi := range baoDiConfig {
		value := BaoDi[baodi.Number]
		if value < baodi.BaoDiCount {
			BaoDi[baodi.Number] = value + 1
		} else {
			// 触发
			for _, studentAsArray := range config.Config.ChouQian.Students {
				if studentAsArray[0] == baodi.Number {
					BaoDi[baodi.Number] = 0
					return types.Student{
						Number: baodi.Number,
						Name:   studentAsArray[1],
					}
				}
			}
		}
	}
	// 否则就从 StudentList 中随机抽取一个学生
	var index int
	if config.Config.ChouQian.RandomMode == "math" {
		index = rand.New(rand.NewSource(time.Now().UnixNano())).Intn(len(StudentList))
	} else {
		index64, _ := cryptoRand.Int(reader, new(big.Int).SetInt64(int64(len(StudentList))))
		index = int(index64.Int64())
	}
	student := StudentList[index]
	StudentList = removeStudent(StudentList, index)
	if len(StudentList) == 0 {
		StudentList = initStudentList()
	}
	// 检查该学生是否在保底中，是则重置该保底
	for _, baodi := range baoDiConfig {
		if student.Number == baodi.Number {
			BaoDi[baodi.Number] = 0
		}
	}
	// 检查替换机制
	replacementConfig := config.Config.ChouQian.SpecialConfig.Replacements
	for _, replacement := range replacementConfig {
		if student.Number == replacement.Number {
			// 触发替代
			randRate, _ := cryptoRand.Int(reader, new(big.Int).SetInt64(100))
			if randRate.Int64() <= int64(replacement.Rate) {
				switch replacement.Key {
				case "number":
					student.Number = replacement.ValueTo
				case "name":
					student.Name = replacement.ValueTo
				}
			}
		}
	}
	return student
}
