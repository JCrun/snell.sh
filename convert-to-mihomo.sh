#!/bin/bash

# 读取 sing-box 客户端配置文件
CONFIG_FILE="/etc/sing-box/client-config.json"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 使用 jq 解析 JSON 配置
if ! command -v jq &> /dev/null; then
    echo "错误: 需要安装 jq 工具来解析 JSON"
    exit 1
fi

# 提取 Shadowsocks 配置
SHADOWSOCKS_CONFIG=$(jq '.outbounds[] | select(.type == "shadowsocks")' "$CONFIG_FILE")
SHADOWSOCKS_METHOD=$(echo "$SHADOWSOCKS_CONFIG" | jq -r '.method')
SHADOWSOCKS_PASSWORD=$(echo "$SHADOWSOCKS_CONFIG" | jq -r '.password')

# 提取 ShadowTLS 配置
SHADOWTLS_CONFIG=$(jq '.outbounds[] | select(.type == "shadowtls")' "$CONFIG_FILE")
SHADOWTLS_SERVER=$(echo "$SHADOWTLS_CONFIG" | jq -r '.server')
SHADOWTLS_PORT=$(echo "$SHADOWTLS_CONFIG" | jq -r '.server_port')
SHADOWTLS_PASSWORD=$(echo "$SHADOWTLS_CONFIG" | jq -r '.password')
SHADOWTLS_SNI=$(echo "$SHADOWTLS_CONFIG" | jq -r '.tls.server_name')

# 提取 AnyTLS (Reality) 配置
ANYTLS_CONFIG=$(jq '.outbounds[] | select(.type == "anytls")' "$CONFIG_FILE")
ANYTLS_SERVER=$(echo "$ANYTLS_CONFIG" | jq -r '.server')
ANYTLS_PORT=$(echo "$ANYTLS_CONFIG" | jq -r '.server_port')
ANYTLS_PASSWORD=$(echo "$ANYTLS_CONFIG" | jq -r '.password')
ANYTLS_SNI=$(echo "$ANYTLS_CONFIG" | jq -r '.tls.server_name')
ANYTLS_FINGERPRINT=$(echo "$ANYTLS_CONFIG" | jq -r '.tls.utls.fingerprint')
ANYTLS_PUBLIC_KEY=$(echo "$ANYTLS_CONFIG" | jq -r '.tls.reality.public_key')
ANYTLS_SHORT_ID=$(echo "$ANYTLS_CONFIG" | jq -r '.tls.reality.short_id')
ANYTLS_IDLE_CHECK=$(echo "$ANYTLS_CONFIG" | jq -r '.idle_session_check_interval' | sed 's/s//')
ANYTLS_IDLE_TIMEOUT=$(echo "$ANYTLS_CONFIG" | jq -r '.idle_session_timeout' | sed 's/s//')
ANYTLS_MIN_IDLE=$(echo "$ANYTLS_CONFIG" | jq -r '.min_idle_session')

# 设置默认值（如果某些字段为空）
if [ -z "$SHADOWTLS_SNI" ] || [ "$SHADOWTLS_SNI" = "null" ]; then
    SHADOWTLS_SNI="www.microsoft.com"
fi

if [ -z "$ANYTLS_SNI" ] || [ "$ANYTLS_SNI" = "null" ]; then
    ANYTLS_SNI="www.microsoft.com"
fi

if [ -z "$ANYTLS_FINGERPRINT" ] || [ "$ANYTLS_FINGERPRINT" = "null" ]; then
    ANYTLS_FINGERPRINT="chrome"
fi

if [ $? -eq 0 ] && [ ! -z "$SHADOWTLS_SERVER" ]; then
    IP_COUNTRY_IPV4=$(curl -s http://ipinfo.io/${SHADOWTLS_SERVER}/country)
    echo "IPv4 地址: ${SHADOWTLS_SERVER} 所在国家: ${IP_COUNTRY_IPV4}"
fi

# 生成代理名称
SS_NAME="${IP_COUNTRY_IPV4}-SS-${SHADOWTLS_SERVER}"
REALITY_NAME="${IP_COUNTRY_IPV4}-Reality-${ANYTLS_SERVER}"

# 输出 Mihomo 格式配置
echo "proxies:"
echo "  - name: \"${SS_NAME}\""
echo "    type: ss"
echo "    server: \"${SHADOWTLS_SERVER}\""
echo "    port: ${SHADOWTLS_PORT}"
echo "    cipher: \"${SHADOWSOCKS_METHOD}\""
echo "    password: \"${SHADOWSOCKS_PASSWORD}\""
echo "    plugin: shadow-tls"
echo "    plugin-opts:"
echo "      host: \"${SHADOWTLS_SNI}\""
echo "      password: \"${SHADOWTLS_PASSWORD}\""
echo "      version: 3"
echo ""
echo "  - name: \"${REALITY_NAME}\""
echo "    type: anytls"
echo "    server: \"${ANYTLS_SERVER}\""
echo "    port: ${ANYTLS_PORT}"
echo "    password: \"${ANYTLS_PASSWORD}\""
echo "    idle-session-check-interval: 30"
echo "    idle-session-timeout: 30"
echo "    min-idle-session: 5"
echo "    sni: \"${ANYTLS_SNI}\""
echo "    reality-opts:"
echo "      public-key: \"${ANYTLS_PUBLIC_KEY}\""
echo "      short-id: \"${ANYTLS_SHORT_ID}\""
echo "    client-fingerprint: \"${ANYTLS_FINGERPRINT}\""
echo "    udp: true"
echo "    servername: \"${ANYTLS_SNI}\""
echo "    # 以下参数可能需要根据客户端支持情况调整"
echo "    # idle-timeout: ${ANYTLS_IDLE_TIMEOUT}"
echo "    # skip-cert-verify: true"