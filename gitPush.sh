#!/bin/bash

# =============================================
# 颜色定义函数
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
        echo "v0.0.0"
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
        *) showErr "无效的版本递增类型"; return 1 ;;
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
    if ! git add .; then
        showErr "git add 操作失败"
        return 1
    fi

    showInfo "提交更改..."
    if ! git commit -m "$commit_message"; then
        showErr "git commit 操作失败"
        return 1
    fi

    showSucc "提交完成: $commit_message"
    return 0
}

# 修复关键问题：版本选择函数只在需要时执行一次
handle_version_tag() {
    local current_version="$1"
    local new_version=""

    showInfo "当前版本: $current_version"

    echo ""
    showInfo "选择版本策略："
    showInfo "1). 编译号（Patch）"
    showInfo "2). 次要版本号（Minor）"
    showInfo "3). 主版本号（Major）"
    showInfo "4). 不发布版本号"

    while true; do
        echo -n "请选择 (1-4, 直接回车选择4): "
        read -r version_choice

        # 处理空输入（默认选择4）
        if [[ -z "$version_choice" ]]; then
            showInfo "跳过版本标签创建"
            echo ""  # 返回空字符串
            return 0
        fi

        # 验证输入有效性
        if [[ "$version_choice" =~ ^[1-4]$ ]]; then
            break
        else
            showErr "无效的选择: '$version_choice'，请选择1-4"
        fi
    done

    case "$version_choice" in
        4)
            showInfo "跳过版本标签创建"
            echo ""  # 返回空字符串
            return 0
            ;;
        *)
            # 处理版本递增
            if ! new_version=$(increment_version "$current_version" "$version_choice"); then
                echo ""  # 返回空字符串表示失败
                return 1
            fi

            showInfo "新版本号: $new_version"

            # 获取标签说明
            local tag_message="Release $new_version"
            echo -n "请输入标签说明 (直接回车使用默认说明): "
            read -r custom_message

            if [[ -n "$custom_message" ]]; then
                tag_message="$custom_message"
            fi

            showInfo "创建标签 $new_version..."
            if git tag -a "$new_version" -m "$tag_message"; then
                save_version "$new_version"
                showSucc "标签创建成功: $new_version"
                echo "$new_version"  # 返回新版本号
                return 0
            else
                showErr "标签创建失败"
                echo ""  # 返回空字符串表示失败
                return 1
            fi
            ;;
    esac
}

git_push() {
    local new_version="$1"

    showInfo "推送到远程仓库..."
    if git push -u origin main; then
        showSucc "代码推送成功"

        # 只有在有有效版本号时才推送标签
        if [[ -n "$new_version" ]] && [[ "$new_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            showInfo "推送版本标签: $new_version"
            if git push origin "$new_version"; then
                showSucc "标签推送成功: $new_version"
            else
                showErr "标签推送失败"
                return 1
            fi
        else
            showInfo "未创建标签，跳过标签推送"
        fi
    else
        showErr "代码推送失败"
        return 1
    fi
    return 0
}

# =============================================
# 主函数 - 修复执行顺序问题
# =============================================

main() {
    clear
    showInfo "开始Git推送流程..."

    # 1. 检查Git状态
    if ! check_git_status; then
        return 1
    fi

    # 2. 获取提交信息
    echo ""
    showInfo "请输入提交说明:"
    read -r commit_message

    if [[ -z "$commit_message" ]]; then
        showErr "提交说明不能为空"
        return 1
    fi

    # 3. 添加并提交
    if ! git_add_commit "$commit_message"; then
        return 1
    fi

    # 4. 询问版本标签（必须在推送之前！）
    echo ""
    showInfo "=== 版本标签设置 ==="
    local current_version=$(read_version)
    local new_version=""

    if new_version=$(handle_version_tag "$current_version"); then
        # 5. 推送代码和标签
        if git_push "$new_version"; then
            echo ""
            showSucc "Git推送流程完成！"
            if [[ -n "$new_version" ]]; then
                showInfo "最终版本: $new_version"
            fi
        else
            return 1
        fi
    else
        # 版本选择失败
        return 1
    fi
}

# =============================================
# 脚本执行入口
# =============================================

# 检查是否在Git仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    showErr "错误: 当前目录不是Git仓库"
    exit 1
fi

# 执行主函数
main "$@"

# 脚本结束，不会有任何额外的交互提示
exit $?
