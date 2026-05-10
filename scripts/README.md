# Scripts

日常只需要这两个入口：

```sh
scripts/build.sh
scripts/install.sh
```

`scripts/build.sh` 构建 Android 5 兼容的接收端 APK，成功时只打印 APK 路径和日志路径。

`scripts/install.sh` 构建并安装到当前连接且已授权的 Android 手机，失败时只打印最关键的原因、下一步命令和日志路径。

如果手机上已经有不同签名的旧包，并且确认要替换它：

```sh
scripts/install.sh --replace
```
