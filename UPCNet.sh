#!/bin/sh

# ==================== 配置项 ====================
username=" "                     # 学号
password=" "                      # 密码
service=" "                            # 运营商: default/unicom/cmcc/ctcc/local
wan_interface="apcli0"                    # WAN 侧接口名
portal_address="http://121.251.251.217"   # portal 地址
portal_backup="http://121.251.251.207"    # portal 备用地址
portal_path="/&userlocation=ethtrunk/62:3501.0"  # portal 路径
login_api="/eportal/InterFace.do?method=login"   # 登录接口
portal_domain="http://lan.upc.edu.cn"     # portal 域名
wan_wait_timeout=120                      # 等待 WAN 接口超时（秒）
portal_retry=10                           # portal 可达重试次数
max_login_retry=5                         # 最大登录重试次数
log_file="/root/my_watchdog.log"          # 日志文件路径
# ================================================

DATE=$(date +%Y-%m-%d-%H:%M:%S)
log() {
    echo "$DATE $1"
    echo "$DATE $1" >> "$log_file"
}

do_login() {
    # 获取认证参数
    trueText=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 "${portal_address}${portal_path}")
    trueUrl=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 -o /dev/null -w '%{url_effective}' "${portal_address}${portal_path}")
    login_url="${portal_domain}${login_api}"

    if echo "$trueText" | grep -q "Error report"; then
        trueUrl=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 -o /dev/null -w '%{url_effective}' "${portal_backup}${portal_path}")
        login_url="${portal_address}${login_api}"
    fi

    query_string="${trueUrl#*\?}"
    log "query_string: $query_string"

    if ! echo "$query_string" | grep -q "wlanuserip"; then
        log "portal 未返回 wlanuserip 参数"
        return 1
    fi

    encoded_query=$(printf '%s' "$query_string" | xxd -p | tr -d '\n' | sed 's/\(..\)/%\1/g' | tr 'a-f' 'A-F')
    parameter="userId=${username}&password=${password}&service=${service}&queryString=${encoded_query}&operatorPwd=&operatorUserId=&validcode=&passwordEncrypt=false"

    postMessage=$(curl -s -X POST -d "$parameter" "$login_url")
    log "portal 响应: $postMessage"

    if echo "$postMessage" | grep -q "success"; then
        log "portal 返回 success, 验证登录状态..."
        sleep 3
        verify_url=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 -o /dev/null -w '%{url_effective}' "$portal_address")
        if echo "$verify_url" | grep -q "success"; then
            return 0
        else
            log "portal 仍显示未登录"
            return 1
        fi
    else
        log "portal 返回失败"
        return 1
    fi
}

# 等待 WAN 侧接口获取到 IP
log "等待 ${wan_interface} 就绪..."
wait=0
while [ $wait -lt $wan_wait_timeout ]; do
    if ip addr show "$wan_interface" 2>/dev/null | grep -q 'inet '; then
        wan_ip=$(ip addr show "$wan_interface" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
        log "${wan_interface} 已就绪, IP: $wan_ip"
        break
    fi
    sleep 5
    wait=$((wait+5))
done

if [ $wait -ge $wan_wait_timeout ]; then
    log "${wan_interface} 超时未就绪, 退出"
    exit 1
fi

log "开始检测登录状态..."

# 等待 portal 可达
log "等待 portal 可达..."
portal_ready=0
j=0
while [ $j -lt $portal_retry ]; do
    check_url=$(curl -s -L -A "Mozilla/5.0" --connect-timeout 5 -o /dev/null -w '%{url_effective}' "$portal_address")
    log "第 $((j+1)) 次检测, portal 重定向到: $check_url"
    if echo "$check_url" | grep -q "eportal"; then
        portal_ready=1
        log "portal 已就绪"
        break
    fi
    sleep 3
    j=$((j+1))
done

if [ $portal_ready -eq 0 ]; then
    log "portal 未就绪, 退出"
    exit 1
fi

# 检查是否已登录（portal 走 apcli0，通过 mwan3 路由）
if echo "$check_url" | grep -q "success"; then
    log "已登录, 退出"
    exit 0
fi

# 循环重试登录
attempt=0
while [ $attempt -lt $max_login_retry ]; do
    attempt=$((attempt+1))
    log "第 ${attempt}/${max_login_retry} 次登录尝试..."
    if do_login; then
        log "登录成功"
        exit 0
    fi
    log "第 ${attempt} 次登录失败, 等待重试..."
    sleep 5
done

log "登录失败: 已重试 ${max_login_retry} 次"
exit 1
