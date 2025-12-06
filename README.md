# findnr-feeds

## 安装说明

- 依赖：`oath-toolkit-oathtool`、`qrencode`、`coreutils-base32`
- 目标：安装 LuCI 插件 `luci-app-simple2fa`，为登录增加 TOTP 二次验证

### 方式一：通过 OpenWrt feeds 集成构建

- 在 OpenWrt 源码目录中添加本地 feed（推荐）：

```
echo "src-link findnrfeeds https://github.com/findnr/findnr-feeds.git" >> feeds.conf
./scripts/feeds update findnrfeeds
./scripts/feeds install luci-app-simple2fa
```

- 选择并编译：

```
make menuconfig
# LuCI -> Applications -> luci-app-simple2fa 选为 <*> 或 <M>
make -j$(nproc)
```

### 方式二：单包本地编译并安装

- 在 OpenWrt 源码目录中执行：

```
make package/luci-app-simple2fa/compile V=s
```

- 将生成的 `.ipk` 拷贝到路由器并安装：

```
scp bin/packages/*/all/luci-app-simple2fa_*.ipk root@<router>:/tmp/
ssh root@<router> opkg update
ssh root@<router> opkg install /tmp/luci-app-simple2fa_*.ipk
```

## 启用与使用

- Web 界面：系统 → Two-Factor Auth，打开开关并扫描二维码
- UCI 命令：

```
uci set simple2fa.global.enabled=1
uci commit simple2fa
```

- 登录页会新增“验证码”输入框；需使用 TOTP 应用（Google Authenticator 等）输入动态码

## 故障排查

- 二维码不显示：确认已安装 `qrencode`，并在设置页存在密钥
- 登录被拦截：确认路由器与客户端时间同步，动态码 30 秒有效
