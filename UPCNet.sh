#!/bin/sh

# ==================== 配置项 ====================
username=""                     # 学号
password=""                      # 密码
service=""                            # 运营商: default/unicom/cmcc/ctcc/local
wan_interface="apcli0"                    # WAN 侧接口名
portal_address="http://121.251.251.217"   # portal 地址
portal_backup="http://121.251.251.207"    # portal 备用地址
portal_path="/&userlocation=ethtrunk/62:3501.0"  # portal 路径
login_api="/eportal/InterFace.do?method=login"   # 登录接口
portal_domain="http://lan.upc.edu.cn"     # portal 域名
wan_wait_timeout=120                      # 等待 WAN 接口超时（秒）
portal_retry=10                           # portal 可达重试次数
log_file="/root/my_watchdog.log"          # 日志文件路径
# ================================================

DATE=$(date +%Y-%m-%d-%H:%M:%S)

# 等待 WAN 侧接口获取到 IP
echo "等待 ${wan_interface} 就绪..."
wait=0
while [ $wait -lt $wan_wait_timeout ]; do
    if ip addr show "$wan_interface" 2>/dev/null | grep -q 'inet '; then
        echo "${wan_interface} 已就绪"
        break
    fi
    sleep 5
    wait=$((wait+5))
done

if [ $wait -ge $wan_wait_timeout ]; then
    echo "${wan_interface} 超时未就绪"
    exit 1
fi

echo --- my_watchdog start ---

# 检测是否已登录：直接访问 portal 根地址
# 已登录 → 重定向到 success.jsp
# 未登录 → 重定向到登录页（含 wlanuserip）
check_url=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 -o /dev/null -w '%{url_effective}' "$portal_address")

if echo "$check_url" | grep -q "success"; then
    echo "你已经登录！"
    exit 0
fi

# 未登录，等待 portal 可达
portal_ok=0
i=0
while [ $i -lt $portal_retry ]; do
    trueText=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 "${portal_address}${portal_path}")
    if [ -n "$trueText" ]; then
        portal_ok=1
        break
    fi
    sleep 3
    i=$((i+1))
done

if [ $portal_ok -eq 0 ]; then
    echo "portal 不可达"
    exit 1
fi

trueUrl=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 -o /dev/null -w '%{url_effective}' "${portal_address}${portal_path}")
login_url="${portal_domain}${login_api}"

if echo "$trueText" | grep -q "Error report"; then
    trueUrl=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 -o /dev/null -w '%{url_effective}' "${portal_backup}${portal_path}")
    login_url="${portal_address}${login_api}"
fi

query_string="${trueUrl#*?}"
encoded_query=$(echo "$query_string" | sed 's/=/%3D/g; s/&/%26/g; s/:/%3A/g; s/\//%2F/g')

if echo "$encoded_query" | grep -q "wlanuserip"; then
    parameter="userId=${username}&password=${password}&service=${service}&queryString=${encoded_query}&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false"
    echo "$DATE 执行登录" >> "$log_file"

    postMessage=$(curl -s -X POST -d "$parameter" "$login_url")
    if echo "$postMessage" | grep -q "success"; then
        echo "登录成功"
    else
        echo "登录失败: $postMessage"
        exit 1
    fi
else
    # portal 没有返回 wlanuserip，可能是 portal 异常
    echo "portal 未返回预期参数，尝试直接登录"
    parameter="userId=${username}&password=${password}&service=${service}&queryString=&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false"
    echo "$DATE 尝试直接登录" >> "$log_file"

    postMessage=$(curl -s -X POST -d "$parameter" "${portal_domain}${login_api}")
    echo "响应: $postMessage"
fi
