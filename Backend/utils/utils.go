package utils

func ErrorThenPanic(err error) {
	if err != nil {
		panic(err)
	}
}
