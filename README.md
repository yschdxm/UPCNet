# 中国石油大学（华东）校园网络认证脚本

OpenWrt 路由器自动登录 UPC 校园网 portal 认证。

## 配置

编辑 `UPCNet.sh` 顶部配置项：

```sh
username="1234567890"                    # 学号
password="password"                      # 密码
service="cmcc"                           # 运营商，见下表
wan_interface="apcli0"                   # WAN 侧接口名
portal_address="http://121.251.251.217"  # portal 地址
portal_backup="http://121.251.251.207"   # portal 备用地址
portal_path="/&userlocation=ethtrunk/62:3501.0"  # portal 路径
login_api="/eportal/InterFace.do?method=login"   # 登录接口
portal_domain="http://lan.upc.edu.cn"    # portal 域名
wan_wait_timeout=120                     # 等待 WAN 接口超时（秒）
portal_retry=10                          # portal 可达重试次数
log_file="/root/my_watchdog.log"         # 日志文件路径
```

运营商编号：

| 编号 | 运营商 |
|------|--------|
| default | 校园网 |
| unicom | 联通 |
| cmcc | 移动 |
| ctcc | 电信 |
| local | 校园内网 |

## OpenWrt 安装

将以下指令中的 `<路由器IP>` 和 `<SSH密码>` 替换为实际值。

### 1. 上传脚本

```sh
sshpass -p '<SSH密码>' scp UPCNet.sh root@<路由器IP>:/root/UPCNet.sh
sshpass -p '<SSH密码>' ssh root@<路由器IP> "chmod +x /root/UPCNet.sh"
```

### 2. 设置 cron 定时检测（每小时）

```sh
sshpass -p '<SSH密码>' ssh root@<路由器IP> "(crontab -l 2>/dev/null; echo '0 * * * * /root/UPCNet.sh') | crontab -"
```

### 3. 设置开机自启

```sh
sshpass -p '<SSH密码>' ssh root@<路由器IP> "cat > /etc/init.d/upcnet << 'EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

start() {
    /bin/sh /root/UPCNet.sh > /root/upcnet_boot.log 2>&1 &
}
EOF
chmod +x /etc/init.d/upcnet
/etc/init.d/upcnet enable"
```

## 脚本逻辑

1. 等待 WAN 侧接口获取 IP（校园网 WiFi 连接就绪）
2. 等待 portal 服务器可达
3. 通过 portal 重定向 URL 中的 `wlanuserip` 参数判断是否需要登录
4. 需要登录则提交认证，否则跳过

## 依赖

- curl
- ip（iproute2）

## 支持的网络类型

有线网络（认证 IP：121.251.251.217 / 121.251.251.207）

## 版权信息

Author: EndangeredFish
Email: im.EndangeredFish@gmail.com
LICENSE: AGPLv3
