#!/bin/bash

# =============================================
# 颜色定义与输出函数 (FIX: 重定向到 stderr 以防被变量捕获)
# =============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

showErr() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

showWarn() {
    echo -e "${YELLOW}[WARN] $1${NC}" >&2
}

showSucc() {
    echo -e "${GREEN}[SUCCESS] $1${NC}" >&2
}

showInfo() {
    echo -e "${BLUE}[INFO] $1${NC}" >&2
}

# =============================================
# 版本管理函数
# =============================================

read_version() {
    if [[ -f ".ver" ]]; then
        cat ".ver"
    else
        echo "v1.0.0"
    fi
}

save_version() {
    echo "$1" > ".ver"
}

parse_version() {
    local version="$1"
    version="${version#v}"
    IFS='.' read -r major minor patch <<< "$version"
    echo "$major $minor $patch"
}

increment_version() {
    local current_version="$1"
    local increment_type="$2"

    IFS=' ' read -r major minor patch <<< "$(parse_version "$current_version")"

    case "$increment_type" in
        1) patch=$((patch + 1)) ;;
        2) minor=$((minor + 1)); patch=0 ;;
        3) major=$((major + 1)); minor=0; patch=0 ;;
        *) return 1 ;;
    esac

    echo "v${major}.${minor}.${patch}"
}

# =============================================
# Git操作函数
# =============================================

check_git_status() {
    if ! git status &> /dev/null; then
        showErr "当前目录不是Git仓库"
        return 1
    fi

    if [[ -z $(git status -s) ]]; then
        showWarn "没有需要提交的更改"
        return 1
    fi
    return 0
}

git_add_commit() {
    local commit_message="$1"
    showInfo "添加文件到暂存区..."
    git add . || return 1
    showInfo "提交更改..."
    git commit -m "$commit_message" || return 1
    showSucc "本地提交完成"
    return 0
}

# =============================================
# 核心修复：版本处理函数
# =============================================

handle_version_tag() {
    local current_version="$1"
    local new_version=""
    local strategy_text=""

    showInfo "当前版本: $current_version"
    echo "" >&2
    showInfo "选择版本策略："
    showInfo "1). 编译号（Patch）"
    showInfo "2). 次要版本号（Minor）"
    showInfo "3). 主版本号（Major）"
    showInfo "4). 不发布版本号"

    # FIX BUG 2 & 3: 使用 -n 1 并立即换行，防止混行
    echo -ne "${BLUE}[INFO] 请选择 (1-4): ${NC}" >&2
    read -r -n 1 version_choice
    echo "" >&2 # 强制换行

    # 默认值处理
    version_choice="${version_choice:-4}"

    # FIX BUG 4: 映射文案
    case "$version_choice" in
        1) strategy_text="编译号 (Patch)" ;;
        2) strategy_text="次要版本号 (Minor)" ;;
        3) strategy_text="主版本号 (Major)" ;;
        4) strategy_text="不发布版本号" ;;
        *) strategy_text="无效选择，跳过"; version_choice=4 ;;
    esac

    showInfo "当前选择了：$strategy_text"

    if [[ "$version_choice" == "4" ]]; then
        return 0
    fi

    # 处理版本递增
    new_version=$(increment_version "$current_version" "$version_choice")
    showInfo "生成新版本号: $new_version"

    # 获取标签说明
    local tag_message="Release $new_version"
    echo -ne "${BLUE}[INFO] 请输入标签说明 (直接回车使用默认): ${NC}" >&2
    read -r custom_message
    [[ -n "$custom_message" ]] && tag_message="$custom_message"

    showInfo "正在创建本地标签 $new_version..."
    if git tag -a "$new_version" -m "$tag_message"; then
        save_version "$new_version"
        showSucc "本地标签创建成功"
        # FIX BUG 1 & 5: 只有这个 echo 会被 main 函数的变量捕获
        echo "$new_version"
        return 0
    else
        showErr "标签创建失败"
        return 1
    fi
}

git_push() {
    local new_version="$1"

    showInfo "正在推送到远程 main 分支..."
    if git push origin main; then
        showSucc "代码推送成功"

        # FIX BUG 6: 显式推送新创建的标签
        if [[ -n "$new_version" ]]; then
            showInfo "正在推送标签 $new_version 到远程..."
            if git push origin "$new_version"; then
                showSucc "远程标签同步完成"
            else
                showErr "标签推送失败，请检查网络或权限"
                return 1
            fi
        fi
    else
        showErr "代码推送失败"
        return 1
    fi
    return 0
}

# =============================================
# 主函数
# =============================================

main() {
    clear
    showInfo ">>> 开始 Git 推送流程 <<<"

    # 1. 检查状态
    check_git_status || return 1

    # 2. 获取提交信息
    echo "" >&2
    echo -ne "${BLUE}[INFO] 请输入 Commit 提交说明: ${NC}" >&2
    read -r commit_message
    if [[ -z "$commit_message" ]]; then
        showErr "提交说明不能为空"
        return 1
    fi

    # 3. 提交
    git_add_commit "$commit_message" || return 1

    # 4. 版本处理 (捕获函数返回的版本号字符串)
    echo "" >&2
    showInfo "=== 版本标签设置 ==="
    local current_version=$(read_version)
    local new_version=$(handle_version_tag "$current_version")

    # 5. 推送
    git_push "$new_version" || return 1

    echo "" >&2
    showSucc "所有任务已完成！"
    [[ -n "$new_version" ]] && showInfo "最终版本状态: $new_version"
}

# 执行
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    showErr "错误: 当前目录不是Git仓库"
    exit 1
fi

main "$@"
exit $?
