#!/usr/bin/bash

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