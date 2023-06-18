# 🔄 抽签

此为我为班级白板编写的一款抽签程序，后端使用 Golang，客户端使用 Visual Basic。

## 😋 功能

其功能看似很简单，点击浮窗即可抽取一名随机学生。

长按（或右键）悬浮窗即可退出。

![](https://imgsrc.baidu.com/forum/pic/item/f31fbe096b63f624121f85cec244ebf81b4ca3b9.jpg)

但是，其拥有一些「有趣的功能」，详见 [配置文件](#🖊️%20配置文件) 这节。

比如，给某名学生设置别名，或者是给某名幸运儿设置保底次数。

![](https://imgsrc.baidu.com/forum/pic/item/9358d109b3de9c8208d945422981800a18d843bb.jpg)

除了这些功能之外，把窗口的底边向下拉，长按学号就可以看见一个隐藏「黑幕」按钮，点击按钮，就可以用手机扫码设置幸运观众。

![](https://imgsrc.baidu.com/forum/pic/item/ac345982b2b7d0a2ae73b8508eef76094a369a41.jpg)


## 🗄️ 后端

后端位于 `Backend` 文件夹，基于 Golang 的 Gin 框架，可以使用 `math/rand` 生成伪随机数，也可以使用 `crypto/rand` 生成真随机数，保证绝对公平。

使用如下命令编译：

```bash
cd Backend
GOOS=windows go build -o ChouQianBackend.exe
```

### 🖊️ 配置文件

可以在 `Backend/chouqian_backend_example.json` 获取到示例配置文件。

`.chouqian.students` 字段为学生列表，采用 `["学号", "姓名"]` 的方式填写。

`.chouqian.special_config`  字段为有趣小功能的配置。`baodi` 中可以给某名学生设置保底，`replacements` 字段可以给学生设置别名或别号。

`.chouqian.api_cooldown` 为扫码遥控功能冷却的分钟数。

`.chouqian.random_mode` 为随机数模式（`math` / `crypto`）。

`.qr` 字段是二维码 IP 相关的设置，因为校园网环境复杂，因此一台电子白板可能有不止一个 IP。此字段用于确保获取到正确的 IP，而不是每次整活时，都去网络适配器选项里禁用网卡。

## 📝 前端

前端位于 `Frontend` 文件夹中。

## 💻 客户端

客户端位于 `Client` 文件夹中，使用 Visual Basic 编写。

依赖 [VBJSON](https://github.com/YidaozhanYa/VBJSON) 和 [stdPicEx2](https://www.vbforums.com/showthread.php?860333-vb6-Enhancing-VB-s-StdPicture-Object-to-Support-GDI&p=5272035#post5272035) 库。

编译时可以使用 [Make-My-Manifest](https://github.com/froque/Make-My-Manifest) 附加 manifest 以启用现代控件和高 DPI 支持。

在 `config.json` 中更改 `BackgroundPath` 项可以更改抽签签筒的图片。需要是白色背景。

### 🔧 配置工具

配置工具位于 `Configure` 文件夹中，可以图形化更改后端的配置。

依赖 [VBJSON](https://github.com/YidaozhanYa/VBJSON) 库和 .NET Framework 4.0.30319（仅用于 UTF-8 编码解码）。
