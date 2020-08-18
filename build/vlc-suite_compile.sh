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

# shellcheck source=build/vlc-suite_helper.sh
source "$LOCALBUILDDIR/vlc-suite_helper.sh"

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
    do_vcs "https://git.savannah.gnu.org/git/gnulib.git"
    export GNULIB_SRCDIR=$LOCALBUILDDIR/gnulib-git
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
