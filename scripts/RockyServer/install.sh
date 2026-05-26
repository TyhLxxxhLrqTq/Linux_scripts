#!/bin/bash

# ==============================================================================
# 颜色与样式定义 (ANSI)
# ==============================================================================
export NC='\033[0m'
export BOLD='\033[1m'
export DIM='\033[2m'
export ITALIC='\033[3m'
export UNDER='\033[4m'
export H_MAGENTA='\033[1;35m'
export H_RED='\033[1;31m'
export H_GREEN='\033[1;32m'
export H_YELLOW='\033[1;33m'
export H_BLUE='\033[1;34m'
export H_PURPLE='\033[1;35m'
export H_CYAN='\033[1;36m'
export H_WHITE='\033[1;37m'
export H_GRAY='\033[1;90m'
export BG_BLUE='\033[44m'
export BG_PURPLE='\033[45m'
export TICK="${H_GREEN}✔${NC}"
export CROSS="${H_RED}✘${NC}"
export INFO="${H_BLUE}ℹ${NC}"
export WARN="${H_YELLOW}⚠${NC}"
export ARROW="${H_CYAN}➜${NC}"

# ==============================================================================
# 基础环境设置
# ==============================================================================
export SHELL=$(command -v bash)
export DEBUG=${DEBUG:-0}
export CN_MIRROR=${CN_MIRROR:-0}

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$BASE_DIR/scripts"
STATE_FILE="$BASE_DIR/.install_progress"

# --- 清理函数 ---
cleanup() {
    rm -f "/tmp/shorin_install_user"
}
trap cleanup EXIT

cleanup_on_exit() {
    command -v tput &>/dev/null && tput cnorm
}
trap cleanup_on_exit EXIT

# ==============================================================================
# 辅助函数
# ==============================================================================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${H_RED}   $CROSS CRITICAL ERROR: Script must be run as root.${NC}"
        exit 1
    fi
}

# --- 加载可视化引擎 (如果存在) ---
if [ -f "$SCRIPTS_DIR/00-utils.sh" ]; then
    source "$SCRIPTS_DIR/00-utils.sh"
else
    echo -e "${H_YELLOW}${WARN} Warning: 00-utils.sh not found, using built-in functions.${NC}"
fi

# --- ASCII Banners ---
banner1() {
cat << "EOF"
.----------------------------------------------.
|████████╗██╗        ██╗  ██╗ ██████╗  ██████╗ |
|╚══██╔══╝██║        ██║  ██║██╔═══██╗██╔═══██╗|
|   ██║   ██║        ███████║██║   ██║██║   ██║|
|   ██║   ██║        ██╔══██║██║▄▄ ██║██║▄▄ ██║|
|   ██║   ███████╗██╗██║  ██║╚██████╔╝╚██████╔╝|
|   ╚═╝   ╚══════╝╚═╝╚═╝  ╚═╝ ╚══▀▀═╝  ╚══▀▀═╝ |
'----------------------------------------------'
EOF
}

export SHORIN_BANNER_IDX=0
show_banner() {
    clear
    echo -e "${H_CYAN}"
    case $SHORIN_BANNER_IDX in
        0) banner1 ;;
    esac
    echo -e "${NC}"
    echo -e "${DIM}   :: Arch Linux Automation ::${NC}"
    echo -e ""
}

# ==============================================================================
# dnf 安装前置准备 (适用于 Fedora/RHEL 系)
# ==============================================================================
detect_distro() {
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    else
        echo -e "${H_RED}错误：未找到 dnf 或 yum，不支持此系统${NC}"
        exit 1
    fi
    export PKG_MANAGER   
    echo -e "${H_GREEN}检测到包管理器: $PKG_MANAGER${NC}"
}

check_network() {
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        echo -e "${H_RED}错误：网络连接失败${NC}"
        exit 1
    fi
}

update_cache() {
    echo -e "${H_CYAN}正在更新软件包缓存...${NC}"
    sudo $PKG_MANAGER check-update &> /dev/null || true
}

install_packages() {
    local packages=("$@")
    echo -e "${H_CYAN}正在安装: ${packages[*]}${NC}"
    sudo $PKG_MANAGER install -y "${packages[@]}"
}

check_fzf() {
    if ! command -v fzf &> /dev/null; then
        sudo $PKG_MANAGER install -y fzf   # 修复硬编码
    fi
}

conf_mirror() {
    # 仅当 Rocky Linux 时执行
    if grep -qi "rocky" /etc/os-release; then
        sed -e 's|^mirrorlist=|#mirrorlist=|g' \
            -e 's|^#baseurl=http://dl.rockylinux.org/$contentdir|baseurl=https://mirrors.aliyun.com/rockylinux|g' \
            -i.bak /etc/yum.repos.d/Rocky-*.repo
        sudo $PKG_MANAGER makecache   # 使用变量
    else
        echo -e "${H_YELLOW}跳过镜像配置（非 Rocky Linux）${NC}"
    fi
}

select_software() {

    local choices=(
        "开发工具|git vim gcc"
        "网络工具|curl wget nmap"
        "多媒体|ffmpeg vlc"
    )
    
    # ... fzf 菜单逻辑 ...
    export SELECTED_PACKAGES="git vim gcc"  # 输出结果
}
# ------------------------------------------------------------------------------
# install docker
# ------------------------------------------------------------------------------
install_docker() {
    # 使用 PKG_MANAGER，并修复拼写
    sudo $PKG_MANAGER remove -y docker \
        docker-client docker-client-latest docker-common \
        docker-latest docker-latest-logrotate docker-logrotate \
        docker-engine podman runc

    sudo $PKG_MANAGER install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
    sudo $PKG_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker   # 已包含启动，无需单独 start
}
# ==============================================================================
# 主流程
# ==============================================================================
main() {
    check_root
    show_banner
    
    # 检测发行版并执行 dnf 准备（若为 Fedora/RHEL）
    detect_distro
    check_network
    update_cache
    check_fzf
    
    # 调用软件选择菜单
    # select_software
    
    conf_mirror

    install_docker
    # ==========================================================================
    # === 用户在此处添加安装软件并配置的逻辑 ===
    # ==========================================================================
    # 您可以调用上面的 install_packages 函数，例如：
    # install_packages "git" "vim" "htop"
    # 也可以直接编写自己的安装和配置命令。
    # ==========================================================================
    bash -c "$(curl -sSL https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh)"
    
    echo -e "${H_GREEN}${TICK} 脚本执行完毕。${NC}"
}

# 执行主函数
main "$@"