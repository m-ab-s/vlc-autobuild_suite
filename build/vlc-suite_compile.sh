#!/usr/bin/bash
# shellcheck disable=SC2034,SC1090,SC1117,SC1091,SC2119
shopt -s extglob
if [[ -z $LOCALBUILDDIR ]]; then
    printf '%s\n' \
        "Something went wrong." \
        "MSYSTEM: $MSYSTEM" \
        "pwd: $(cygpath -w "$(pwd)")" \
        "fstab: " \
        "$(cat /etc/fstab)" \
        "Create a new issue and upload all logs you can find, especially compile.log"
    read -r -p "Enter to continue" ret
    exit 1
fi
FFMPEG_BASE_OPTS=("--pkg-config-flags=--static" "--cc=$CC" "--cxx=$CXX")
printf '\nBuild start: %(%F %T %z)T\n' -1 >> "$LOCALBUILDDIR/newchangelog"
printf '#!/bin/bash\nbash %s %s\n' "$LOCALBUILDDIR/vlc-suite_compile.sh" "$*" > "$LOCALBUILDDIR/last_run"

while true; do
    case $1 in
    --cpuCount=*)
        case ${1//[!0-9]/} in
        *[0-9]*) cpuCount=${1//[!0-9]/} ;;
        *) cpuCount=1 ;;
        esac
        shift
        ;;
    --build32=*)
        case ${1#*=} in
        true) build32=y ;;
        *) build32=n ;;
        esac
        shift
        ;;
    --build64=*)
        case ${1#*=} in
        true) build64=y ;;
        *) build64=n ;;
        esac
        shift
        ;;
    --stripping*)
        case ${1#*=} in
        true) stripping=y ;;
        *) stripping=n ;;
        esac
        shift
        ;;
    --packing*)
        case ${1#*=} in
        true) packing=y ;;
        *) packing=n ;;
        esac
        shift
        ;;
    --timeStamp=*)
        case ${1#*=} in
        true) timeStamp=y ;;
        *) timeStamp=n ;;
        esac
        shift
        ;;
    --) shift && break ;;
    -*) echo "Error, unknown option: '$1'." && exit 1 ;;
    *) break ;;
    esac
done

ccache=y logging=y

# shellcheck source=/code/media-autobuild_suite/build/media-suite_helper.sh
source "$LOCALBUILDDIR/media-suite_helper.sh"

# Overwrite certain functions that need extra stuff
set_title() {
    printf '\033]0;vlc-autobuild_suite  %s\a' "(${bits:=64bit})${1:+: $1}"
}
zip_logs() {
    local failed url
    failed=$(get_first_subdir)
    strip_ansi "$LOCALBUILDDIR"/*.log
    rm -f "$LOCALBUILDDIR/logs.zip"
    (
        cd "$LOCALBUILDDIR" > /dev/null || do_exit_prompt "Did you delete /build?"
        {
            echo /trunk/vlc-autobuild_suite.bat
            [[ $failed != . ]] && find "$failed" -name "*.log"
            find . -maxdepth 1 -name "*.stripped.log" -o -name "*_options.txt" -o -name "media-suite_*.sh" -o -name "vlc-suite_*.sh" \
                -o -name "last_run" -o -name "vlc-autobuild_suite.ini" -o -name "diagnostics.txt" -o -name "patchedFolders"
        } | sort -uo failedFiles
        7za -mx=9 a logs.zip -- @failedFiles > /dev/null && rm failedFiles
    )
    [[ ! -f $LOCALBUILDDIR/no_logs && -n $build32$build64 ]] &&
        url="$(cd "$LOCALBUILDDIR" && /usr/bin/curl -sF'file=@logs.zip' https://0x0.st)"
    echo
    if [[ $url ]]; then
        echo "${green}All relevant logs have been anonymously uploaded to $url"
        echo "${green}Copy and paste ${red}[logs.zip]($url)${green} in the GitHub issue.${reset}"
    elif [[ -f "$LOCALBUILDDIR/logs.zip" ]]; then
        echo "${green}Attach $(cygpath -w "$LOCALBUILDDIR/logs.zip") to the GitHub issue.${reset}"
    else
        echo "${red}Failed to generate logs.zip!${reset}"
    fi
}

cleanup() {
    [[ -z $build32$build64 ]] && return 1
    echo "${red}failed. Check the log files under $(pwd -W)"
    if ${_notrequired:-false}; then
        echo "This isn't required for anything so we can move on."
        return 1
    fi
    echo "${red}This is required for other packages, so this script will exit.${reset}"
    create_diagnostic
    zip_logs
    echo "Make sure the suite is up-to-date before reporting an issue. It might've been fixed already."
    do_prompt "Try running the build again at a later time."
    case "$-" in
    *i*) return 1 ;;
    *)
        trap - SIGINT EXIT
        exit 1
        ;;
    esac
}

trap cleanup SIGINT EXIT

do_makepkg() {
    [[ -d $LOCALBUILDDIR/$1 ]] || git -C /trunk checkout "@{u}" -- "${LOCALBUILDDIR#/}/$1"
    [[ -f $LOCALBUILDDIR/$1/PKGBUILD ]] || return 1
    cd_safe "$LOCALBUILDDIR/$1"
    case $bits in
    32bit)
        rm -rf ./*-i686-*.log
        export MINGW_INSTALLS=mingw32
        ;;
    *)
        rm -rf ./*-x86_64-*.log
        export MINGW_INSTALLS=mingw64
        ;;
    esac
    makepkg-mingw -siL --noconfirm --needed || exit 1
}

do_simple_print -p "${orange}Warning: We will not accept any issues lacking any form of logs or logs.zip!$reset"

buildGlobal() {
    set_title "compiling global tools"
    do_simple_print -p "${orange}Starting $bits compilation of global tools${reset}"

    if [[ $packing == y && \
        "$(/opt/bin/upx -V 2> /dev/null | head -1)" != "upx 3.96" ]] &&
            do_wget -h 014912ea363e2d491587534c1e7efd5bc516520d8f2cdb76bb0aaf915c5db961 \
                "https://github.com/upx/upx/releases/download/v3.96/upx-3.96-win32.zip"; then
        do_install upx.exe /opt/bin/upx.exe
    fi
    do_makepkg zlib
    do_makepkg libxml2
}

buildAudio() {
    true
}

buildProcess() {
    set_title
    cd_safe "$LOCALBUILDDIR"
    # in case the root was moved, this fixes windows abspaths
    mkdir -p "$LOCALDESTDIR/lib/pkgconfig"
    # pkgconfig keys to find the wrong abspaths from
    local _keys="(prefix|exec_prefix|libdir|includedir)"
    # current abspath root
    local _root
    _root=$(cygpath -m "$LOCALDESTDIR")
    # find .pc files with Windows abspaths
    grep -ElZR "${_keys}=[^/$].*" "$LOCALDESTDIR"/lib/pkgconfig |
        # find those with a different abspath than the current
        xargs -0r grep -LZ "$_root" |
        # replace with current abspath
        xargs -0r sed -ri "s;${_keys}=.*$LOCALDESTDIR;\1=$_root;g"
    unset _keys _root
    hide_conflicting_libs -R
    do_hide_all_sharedlibs
    create_ab_pkgconfig
    create_cmake_toolchain
    create_ab_ccache

    buildGlobal
}

run_builds() {
    new_updates=false
    new_updates_packages=""
    if [[ $build32 == y ]]; then
        source /vlc32/etc/profile2.local
        buildProcess
    fi

    if [[ $build64 == y ]]; then
        source /vlc64/etc/profile2.local
        buildProcess
    fi
}

cd_safe "$LOCALBUILDDIR"
run_builds

while [[ $new_updates != false ]]; do
    ret=no
    printf '%s\n' \
        "-------------------------------------------------------------------------------" \
        "There were new updates while compiling." \
        "Updated:$new_updates_packages" \
        "Would you like to run compilation again to get those updates? Default: no"
    do_prompt "y/[n] "
    echo "-------------------------------------------------------------------------------"
    case $ret in
    [Yy]*) run_builds ;;
    *) break ;;
    esac
done

clean_suite
trap - SIGINT EXIT
do_simple_print -p "${green}Compilation successful.${reset}"
do_simple_print -p "${green}This window will close automatically in 5 seconds.${reset}"
sleep 5
