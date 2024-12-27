#!/usr/bin/env bash

#=libs
#@shared variables and functions
#@usage:
#@source shared.sh

CONFIG_DIR="${HOME}"/.config/keyring
CONFIG_FILE="${CONFIG_DIR}"/config

KEY_KEYRING_DIR="directory"

declare -A ITEM_ARRAY
declare -a ITEM_ARRAY_ORDER

error_msg() {
    printf "ERROR:\nSCRIPT:%s\nFUNC:%s\nLINE:%d\n" "$(basename "${0}")" "${FUNCNAME[1]}" "$1"
    exit 1
}

get_gpg_symmetric_password_from_keychain() {
    local password
    password=$(security find-generic-password -s "gpg-symmetric" -a "${MAIL_GMAIL_MAIN}" -w) || error_msg "$LINENO"

    echo "${password}"
    return 0
}

#对称加密
do_symmetric_encrypt() {
    local plain_text="${1}"
    local encrypted_text
    local password
    password=$(get_gpg_symmetric_password_from_keychain)

    encrypted_text=$(echo -n "$plain_text" | gpg --batch --yes --passphrase "$password" --symmetric --armor)

    if [[ $? -eq 0 ]]; then
        echo "${encrypted_text}"
        return 0
    else
        error_msg "$LINENO"
    fi
}

#对称解密
do_symmetric_decrypt() {
    local encrypted_text="${1}"
    local plain_text
    local password
    password=$(get_gpg_symmetric_password_from_keychain)

    plain_text=$(echo "$encrypted_text" | gpg --quiet --batch --yes --passphrase "$password" --decrypt)

    if [[ $? -eq 0 ]]; then
        echo "${plain_text}"
        return 0
    else
        error_msg "$LINENO"
    fi
}

#非对称加密
do_asymmetric_encrypt() {
    :
}

get_config_value() {
    if (("$#" == 1)); then
        local key="${1}"
        local value
        value=$(awk -F= -v k="$key" '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); if ($1 == k) print $2}' "${CONFIG_FILE}")

        echo "${value}"
        return 0
    else
        error_msg "$LINENO"
    fi
}

get_keyring_dir() {
    local keyring_dir
    keyring_dir=$(get_config_value "${KEY_KEYRING_DIR}") || error_msg "$LINENO"

    echo "${keyring_dir}"
    return 0
}

get_vault_path() {
    local vault_name="${1}"
    local vault_path
    vault_path=$(get_keyring_dir)/"${vault_name}" || error_msg "$LINENO"

    echo "${vault_path}"
    return 0
}

get_item_path() {
    local vault_name="${1}"
    local item_name="${2}"
    local item_path
    item_path=$(get_vault_path "${vault_name}")/"${item_name}" || error_msg "$LINENO"

    echo "${item_path}"
    return 0
}

read_item() {
    local item="${1}"

    current_key=""

    #设置IFS=的作用是告诉read命令不将空格,制表符或换行符视为分隔符,这意味着读取的每一行会被完整保留,包括前导和尾随空格
    #-r:禁用反斜杠转义,如果没有-r,反斜杠(\)会被解析为转义符
    #如果文件的最后一行没有换行符,read会读取这行内容,但返回非0,导致该行可能被忽略
    #为了防止这种情况,通过||[[-n $line]]确保即使read返回非0,只要变量line非空,这行数据仍会被处理
    while IFS= read -r line || [[ -n $line ]]; do
        # 如果是空行,则清除当前键
        if [[ -z $line ]]; then
            current_key=""
        elif [[ $current_key == "" ]]; then
            # 如果没有当前键,将这一行作为键
            current_key=$line
            ITEM_ARRAY["$current_key"]=""
            ITEM_ARRAY_ORDER+=("$current_key")
        else
            # 否则将这一行追加到当前键的值中
            ITEM_ARRAY["$current_key"]+="${line}"$'\n'
        fi
    done <"${item}"

    # 去除每个值末尾多余的换行符
    for key in "${!ITEM_ARRAY[@]}"; do
        # 使用printf去掉末尾的换行符,同时保留中间的换行符
        ITEM_ARRAY["$key"]=$(printf "%s" "${ITEM_ARRAY[$key]}")
    done
}

read_symmetric_encrypted_item() {
    local item="${1}"
    local current_key=""
    local is_pgp_block=0

    while IFS= read -r line || [[ -n $line ]]; do
        # 检查是否是PGP块的开始
        if [[ $line == "-----BEGIN PGP MESSAGE-----" ]]; then
            is_pgp_block=1
            if [[ -n $current_key ]]; then
                ITEM_ARRAY["$current_key"]+="$line"$'\n'
            fi
            continue
        fi

        # 检查是否是PGP块的结束
        if [[ $is_pgp_block -eq 1 ]]; then
            ITEM_ARRAY["$current_key"]+="$line"$'\n'
            if [[ $line == "-----END PGP MESSAGE-----" ]]; then
                is_pgp_block=0
            fi
            continue
        fi

        # 处理空行
        if [[ -z $line ]]; then
            current_key=""
            continue
        fi

        # 处理新键
        if [[ -z $current_key ]]; then
            current_key=$line
            ITEM_ARRAY["$current_key"]=""
            ITEM_ARRAY_ORDER+=("$current_key")
        else
            # 追加到当前键的值
            ITEM_ARRAY["$current_key"]+="$line"$'\n'
        fi
    done <"$item"

    # 去除每个值末尾多余的换行符
    for key in "${!ITEM_ARRAY[@]}"; do
        ITEM_ARRAY["$key"]=$(printf "%s" "${ITEM_ARRAY[$key]}")
    done
}

write_item() {
    local item="${1}"

    : >"${item}"

    for key in "${ITEM_ARRAY_ORDER[@]}"; do
        echo "${key}" >>"${item}"
        printf "%s\n" "${ITEM_ARRAY[$key]}" >>"${item}"
        echo >>"${item}"
    done

    #删除掉文件末尾的空行
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${item}"
}
