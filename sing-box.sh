#!/bin/bash
# sing-box 一键安装管理脚本
# 支持: Debian / Ubuntu / CentOS
# 功能: 安装 / 配置 / 管理 sing-box (ShadowTLS + Shadowsocks)
# 作者: ChatGPT 改写版

set -e

SINGBOX_BIN="/usr/local/bin/sing-box"
CONFIG_PATH="/etc/sing-box/config.json"
SERVICE_FILE="/etc/systemd/system/sing-box.service"

# 定义配置目录
SNELL_CONF_DIR="/etc/snell"
SNELL_CONF_FILE="${SNELL_CONF_DIR}/users/snell-main.conf"

# 获取最新版本号
get_latest_version() {
    curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | grep "tag_name" | cut -d '"' -f 4 | sed 's/v//'
}

install_singbox() {
    if [ -f "$SINGBOX_BIN" ]; then
        echo "sing-box 已安装: $($SINGBOX_BIN version)"
        return
    fi

    echo "正在安装 sing-box ..."
    VERSION=$(get_latest_version)
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) echo "不支持的架构: $ARCH" && exit 1 ;;
    esac

    wget -qO /tmp/sing-box.tar.gz https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-linux-${ARCH}.tar.gz
    tar -xzf /tmp/sing-box.tar.gz -C /tmp
    install -m 755 /tmp/sing-box-${VERSION}-linux-${ARCH}/sing-box $SINGBOX_BIN

    rm -rf /tmp/sing-box*
    echo "安装完成: $($SINGBOX_BIN version)"
}

generate_config() {
    mkdir -p /etc/sing-box
    if [ -f "$CONFIG_PATH" ]; then
        echo "配置文件已存在: $CONFIG_PATH"
        return
    fi

    # 获取 IPv4 地址
    IPV4_ADDR=$(curl -s4 https://api.ipify.org)
    if [ $? -eq 0 ] && [ ! -z "$IPV4_ADDR" ]; then
        IP_COUNTRY_IPV4=$(curl -s http://ipinfo.io/${IPV4_ADDR}/country)
        echo "IPv4 地址: ${IPV4_ADDR} 所在国家: ${IP_COUNTRY_IPV4}"
    fi

    read -p "请输入 AnyTLS 监听端口 (默认随机): " ANYTLS_PORT
    ANYTLS_PORT=$(shuf -i 10000-65535 -n 1)

    read -p "请输入 AnyTLS 密码 (默认随机): " ANYTLS_PASS
    # $(sing-box generate uuid)
    ANYTLS_PASS=$($SINGBOX_BIN generate uuid)

    read -p "请输入 Reality Private Key (默认随机): " REALITY_PRIVATE_KEY
    key_pair=$(sing-box generate reality-keypair)
    # private_key=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    # public_key=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')
    REALITY_PRIVATE_KEY=$(echo "$key_pair" | awk '/PrivateKey/ {print $2}' | tr -d '"')
    REALITY_PUBLIC_KEY=$(echo "$key_pair" | awk '/PublicKey/ {print $2}' | tr -d '"')

    read -p "请输入 Reality Short ID (多个用逗号分隔, 默认随机): " REALITY_SHORT_ID
    # $(sing-box generate rand --hex 4)
    REALITY_SHORT_ID=$(sing-box generate rand --hex 4)

    read -p "请输入 ShadowTLS 监听端口 (默认随机): " SHADOWTLS_DETOUR_PORT
    SHADOWTLS_DETOUR_PORT=$(shuf -i 10000-65535 -n 1)

    read -p "请输入 Shadowsocks 密码 (默认随机): " SHADOWSOCKS_PASS
    SHADOWSOCKS_PASS=$($SINGBOX_BIN generate rand 32 --base64)

    read -p "请输入 ShadowTLS 密码 (默认随机): " SHADOWTLS_DETOUR_PASS
    SHADOWTLS_DETOUR_PASS=$($SINGBOX_BIN generate rand 16 --base64)

    read -p "请输入 ShadowTLS 伪装域名 (例如 www.microsoft.com): " SNI
    SNI=${SNI:-www.microsoft.com}

    read -p "请输入 Snell ShadowTLS 监听端口 (默认随机): " SHADOWTLS_PORT
    SHADOWTLS_PORT=$(shuf -i 10000-65535 -n 1)

    read -p "请输入 Snell 密码 (默认随机): " SHADOWTLS_PASS
    SHADOWTLS_PASS=$($SINGBOX_BIN generate rand 16 --base64)

    SNELL_PORT=$(grep -E '^listen' "${SNELL_CONF_FILE}" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
    SNELL_PSK=$(grep -E '^psk' "${SNELL_CONF_FILE}" | awk -F'=' '{print $2}' | tr -d ' ')
    if [ ! -z "$SNELL_PORT" ] && [ ! -z "$SNELL_PSK" ]; then
        echo "${SNELL_PORT}|${SNELL_PSK}"
    fi
    cat > $CONFIG_PATH <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      {
        "type": "https",
        "server": "8.8.8.8"
      }
    ],
    "strategy": "prefer_ipv4"
  },
  "inbounds": [
    {
      "type": "anytls",
      "listen": "::",
      "listen_port": ${ANYTLS_PORT},
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SNI}",
            "server_port": 443
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": "${REALITY_SHORT_ID}"
        }
      },
      "users": [
        {
          "password": "${ANYTLS_PASS}"
        }
      ],
      "padding_scheme": [
        "stop=8",
        "0=30-30",
        "1=100-400",
        "2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000",
        "3=9-9,500-1000",
        "4=500-1000",
        "5=500-1000",
        "6=500-1000",
        "7=500-1000"
      ]
    },
    {
      "type": "shadowtls",
      "tag": "shadowtls-in-for-snell",
      "listen": "::",
      "listen_port": ${SHADOWTLS_PORT},
      "version": 3,
      "users": [
        {
          "password": "${SHADOWTLS_PASS}"
        }
      ],
      "handshake": {
        "server": "${SNI}",
        "server_port": 443
      },
      "strict_mode": true
    },
    {
      "type": "shadowtls",
      "tag": "st-in",
      "listen": "::",
      "listen_port": ${SHADOWTLS_DETOUR_PORT},
      "detour": "ss-in",
      "version": 3,
      "users": [
        {
          "password": "${SHADOWTLS_DETOUR_PASS}"
        }
      ],
      "handshake": {
        "server": "${SNI}",
        "server_port": 443
      },
      "strict_mode": true
    },
    {
      "type": "shadowsocks",
      "tag": "ss-in",
      "listen": "127.0.0.1",
      "method": "2022-blake3-aes-256-gcm",
      "password": "${SHADOWSOCKS_PASS}",
      "multiplex": {
        "enabled": true,
        "padding": true,
        "brutal": {
          "enabled": true,
          "up_mbps": 30,
          "down_mbps": 300
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block-out"
    }
  ],
  "route": {
    "rules": [
      {
        "action": "sniff"
      },
      {
        "action": "resolve",
        "strategy": "prefer_ipv4"
      },
      {
        "ip_cidr": [
          "::/0",
          "0.0.0.0/0"
        ],
        "outbound": "direct"
      },
      {
        "inbound": "shadowtls-in-for-snell",
        "action": "route-options",
        "override_address": "127.0.0.1",
        "override_port": ${SNELL_PORT}
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      }
    ],
    "final": "direct"
  }
}

EOF

    # 生成sing-box client端配置
    cat > /etc/sing-box/client-config.json <<EOF
{
  "outbounds": [
    {
      "tag": "",
      "type": "shadowsocks",
      "method": "2022-blake3-aes-256-gcm",
      "password": "${SHADOWSOCKS_PASS}",
      "detour": "shadowtls-out"
    },
    {
      "tag": "shadowtls-out",
      "type": "shadowtls",
      "server": "${IPV4_ADDR}",
      "server_port": ${SHADOWTLS_DETOUR_PORT},
      "version": 3,
      "password": "${SHADOWTLS_DETOUR_PASS}",
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "utls": {
          "enabled": true
        }
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-out",
      "server": "${IPV4_ADDR}",
      "server_port": ${ANYTLS_PORT},
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "${REALITY_PUBLIC_KEY}",
          "short_id": "${REALITY_SHORT_ID}"
        }
      },
      "password": "${ANYTLS_PASS}",
      "idle_session_check_interval": "30s",
      "idle_session_timeout": "30s",
      "min_idle_session": 5
    }
  ]
}
EOF
    # 输出 Surge 配置格式
    # snell, 124.156.157.132, 37662, psk = k0wvk2XOYVi1pXMu3uxf, version = 4, reuse = true, tfo = true, shadow-tls-password = FfnCJfW3aZOioOOO, shadow-tls-sni = www.microsoft.com, shadow-tls-version = 3
    echo "Surge 配置格式："
    echo "${IP_COUNTRY_IPV4} = snell, ${IPV4_ADDR}, ${SHADOWTLS_PORT}, psk = ${SNELL_PSK}, version = 5, reuse = true, tfo = true, shadow-tls-password = ${SHADOWTLS_PASS}, shadow-tls-sni = ${SNI}, shadow-tls-version = 3"

    echo "server配置已生成: $CONFIG_PATH"
    echo "client配置已生成: /etc/sing-box/client-config.json"
    echo "AnyTLS 监听端口: $ANYTLS_PORT"
    echo "AnyTLS 密码: $ANYTLS_PASS"
    echo "Reality Private Key: $REALITY_PRIVATE_KEY"
    echo "Reality Public Key: $REALITY_PUBLIC_KEY"
    echo "Reality Short ID: $REALITY_SHORT_ID"
    echo "ShadowTLS 监听端口: $SHADOWTLS_DETOUR_PORT"
    echo "Shadowsocks 密码: $SHADOWSOCKS_PASS"
    echo "ShadowTLS 密码: $SHADOWTLS_DETOUR_PASS"
    echo "Snell ShadowTLS 监听端口: $SHADOWTLS_PORT"
    echo "Snell ShadowTLS 密码: $SHADOWTLS_PASS"
    echo "SNI 域名: $SNI"
}

create_service() {
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=sing-box service
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${SINGBOX_BIN} run -c ${CONFIG_PATH}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable sing-box
    echo "systemd 服务已创建: sing-box"
}

start_service() {
    systemctl start sing-box
    systemctl status sing-box --no-pager -l
}

stop_service() {
    systemctl stop sing-box
    echo "sing-box 已停止"
}

uninstall_singbox() {
    systemctl stop sing-box || true
    systemctl disable sing-box || true
    rm -f $SERVICE_FILE
    rm -f $SINGBOX_BIN
    rm -rf /etc/sing-box
    systemctl daemon-reload
    echo "sing-box 已卸载"
}

menu() {
    echo "\n=== sing-box 管理脚本 ==="
    echo "1. 安装 sing-box"
    echo "2. 生成配置文件"
    echo "3. 创建 systemd 服务"
    echo "4. 启动服务"
    echo "5. 停止服务"
    echo "6. 卸载 sing-box"
    echo "0. 退出"
    echo "========================"
    read -p "请选择操作: " choice
    case $choice in
        1) install_singbox ;;
        2) generate_config ;;
        3) create_service ;;
        4) start_service ;;
        5) stop_service ;;
        6) uninstall_singbox ;;
        0) exit 0 ;;
        *) echo "无效选择" ;;
    esac
}

while true; do
    menu
done
