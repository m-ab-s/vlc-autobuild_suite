@echo off
rem -----------------------------------------------------------------------------
rem LICENSE --------------------------------------------------------------------
rem -----------------------------------------------------------------------------
rem  This Windows Batchscript is for setup a compiler environment for building
rem  VLC under Windows.
rem
rem    Copyright (C) 2020 m-ab-s
rem
rem    This program is free software: you can redistribute it and/or modify
rem    it under the terms of the GNU General Public License as published by
rem    the Free Software Foundation, either version 3 of the License, or
rem    (at your option) any later version.
rem
rem    This program is distributed in the hope that it will be useful,
rem    but WITHOUT ANY WARRANTY; without even the implied warranty of
rem    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
rem    GNU General Public License for more details.
rem
rem    You should have received a copy of the GNU General Public License
rem    along with this program.  If not, see <https://www.gnu.org/licenses/>.
rem -----------------------------------------------------------------------------

title vlc-autobuild_suite

setlocal
chcp 65001 >nul 2>&1
cd /d "%~dp0"
set "TERM=xterm-256color"
setlocal

if %PROCESSOR_ARCHITECTURE%==x86 if not DEFINED PROCESSOR_ARCHITEW6432 (
    echo ----------------------------------------------------------------------
    echo. 32-bit host and OS are not supported for building.
    echo. Please consider either moving to a 64-bit machine and OS or use
    echo. a 64-bit machine to compile the binaries you need.
    pause
    exit
)

rem MSVC Detection
(
    where lib.exe || ^
    where cl.exe || ^
    if DEFINED VSINSTALLDIR cd .
) >nul 2>&1 && (
    echo ----------------------------------------------------------------------
    echo. You are running in a MSVC environment (cl.exe or lib.exe detected^)
    echo. This is not supported.
    echo. Please run the script through a normal cmd.exe some other way.
    echo.
    echo. Detected Paths:
    where lib.exe 2>nul
    where cl.exe 2>nul
    echo %VSINSTALLDIR%
    pause
    exit
)

if not exist %CD% (
    echo ----------------------------------------------------------------------
    echo. You have probably run the script in a path with spaces.
    echo. This is not supported.
    echo. Please move the script to use a path without spaces. Example:
    echo. Incorrect: C:\build suite\
    echo. Correct:   C:\build_suite\
    pause
    exit
)

if not ["%CD:~32,1%"]==[""] (
    echo -------------------------------------------------------------------------------
    echo. The total filepath to the suite seems too large (larger than 32 characters^):
    echo. %CD%
    echo. Some packages might fail building because of it.
    echo. Please move the suite directory closer to the root of your drive and maybe
    echo. rename the suite directory to a smaller name. Examples:
    echo. Avoid:  C:\Users\Administrator\Desktop\testing\media-autobuild_suite-master
    echo. Prefer: C:\media-autobuild_suite
    echo. Prefer: C:\ab-suite
    pause
)

where pwsh.exe >nul 2>&1 && set ps=pwsh || set ps=powershell
for /f "tokens=4-5 delims=. " %%i in ('ver') do ^
for /f "delims=" %%x in  ('%ps% -Command 10 * %%i.%%j') do set WINVER=%%x

if %WINVER% LEQ 61 (
    echo ----------------------------------------------------------------------
    echo. Windows 7 or older was detected, this is not supported by the suite.
    echo. Building will not be stopped, but any issues with Windows 7 may be
    echo. marked as low priority or closed.
    pause
)

set instdir=%CD%
set build=%instdir%\build
if not exist %build% mkdir %build%

set msyspackages=base-devel git p7zip autoconf-archive

set mingwpackages=cmake meson dlfcn gcc clang nasm yasm pcre tools-git ninja pkg-config ccache jq

set iniOptions=CC cores strip timeStamp

set deleteIni=0
set ini=%build%\vlc-autobuild_suite.ini

rem Set all INI options to 0
for %%a in (%iniOptions%) do set %%aINI=0

rem Set INI options to what's found in the inifile
if exist %ini% (
    for %%a in (%iniOptions%) do for /F "tokens=2 delims==" %%b in ('findstr %%a %ini%') do set %%aINI=%%b
) else set deleteIni=1

setlocal EnableDelayedExpansion
rem Check if any of the *INI options are still unset (0)
for %%a in (%iniOptions%) do if [!%%aINI!]==[0] set deleteIni=1 && goto :endINIcheck
:endINIcheck
endlocal & set deleteIni=%deleteIni%
if %deleteINI%==1 echo.[compiler list] >"%ini%"

:CC
if %CCINI%==0 (
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    echo.
    echo. Which C Compiler to use?
    echo. Use of a compiler other than gcc is experimental and possibly broken due
    echo. to presumptions of a mingw-w64 compiler on Windows
    echo. 1 = GCC [Recommended]
    echo. 2 = Clang
    echo.
    echo.
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    set /P buildCC="CC to use with compiling: "
) else set buildCC=%CCINI%

if "%buildCC%"=="" GOTO CC
if %buildCC% GTR 2 GOTO CC
if %buildCC%==2 set CC=clang && set CXX=clang++
if not defined CC set CC=gcc && set CXX=g++
if %deleteINI%==1 echo.CC=^%buildCC%>>%ini%

:numCores
if %NUMBER_OF_PROCESSORS% EQU 1 ( set coreHalf=1 ) else set /a coreHalf=%NUMBER_OF_PROCESSORS%/2
if %coresINI%==0 (
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    echo.
    echo. Number of CPU Cores/Threads for compiling:
    echo. [it is non-recommended to use all cores/threads!]
    echo.
    echo. Recommended: %coreHalf%
    echo.
    echo. If you have Windows Defender Real-time protection on, most of your processing
    echo. power will go to it. It is recommended to whitelist this directory from
    echo. scanning due to the amount of new files and copying/moving done by the suite.
    echo. If you do not know how to do this, google it. If you don't care, ignore this.
    echo.
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    set /P cpuCores="Core/Thread Count: "
) else set cpuCores=%coresINI%
for /l %%a in (1,1,%cpuCores%) do set cpuCount=%%a

if "%cpuCount%"=="" GOTO numCores
if not defined cpuCount set cpuCount=1
if %deleteINI%==1 echo.cores=^%cpuCount%>>%ini%

:stripEXE
if %stripINI%==0 (
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    echo.
    echo. Strip compiled files binaries?
    echo. 1 = Yes [recommended]
    echo. 2 = No
    echo.
    echo. Makes binaries smaller at only a small time cost after compiling.
    echo.
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    set /P stripF="Strip files: "
) else set stripF=%stripINI%

if "%stripF%"=="" GOTO stripEXE
if %stripF% GTR 2 GOTO stripEXE
if %stripF%==2 set stripFile=false
if not defined stripFile set stripFile=true
if %deleteINI%==1 echo.strip=^%stripF%>>%ini%

:timeStamp
if %timeStampINI%==0 (
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    echo.
    echo. Show timestamps of commands during compilation?
    echo. 1 = Yes
    echo. 2 = No
    echo.
    echo This will show the start times of commands during compilation.
    echo Don't turn this on unless you really want to see the timestamps.
    echo.
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    set /P timeStampF="Show Timestamps: "
) else set timeStampF=%timeStampINI%

if "%timeStampF%"=="" GOTO timestamp
if %timeStampF% GTR 2 GOTO timeStamp
if %timeStampF%==2 set timeStamp=false
if not defined timeStamp set timeStamp=true
if %deleteINI%==1 echo.timeStamp=^%timeStampF%>>%ini%

rem ------------------------------------------------------------------
rem download and install basic msys2 system:
rem ------------------------------------------------------------------
cd %build%
rem we only need bash.sh at this time, the rest can be gotten later
if not exist "%build%\bash.sh" (
    %ps% -Command (New-Object System.Net.WebClient^).DownloadFile('"https://github.com/m-ab-s/media-autobuild_suite/raw/master/build/bash.sh"', '"bash.sh"' ^)
)

rem checkmsys2
if not exist "%instdir%\msys64\msys2_shell.cmd" (
    echo -------------------------------------------------------------------------------
    echo.
    echo.- Download and install msys2 basic system
    echo.
    echo -------------------------------------------------------------------------------
    %ps% -NoProfile -Noninteractive -Command (New-Object System.Net.WebClient^).DownloadFile(^
        'https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe', ^
        'msys2-base.sfx.exe'^) || goto :errorMsys
    if exist .\msys2-base.sfx.exe .\msys2-base.sfx.exe x -y -o".."
    del msys2-base.sfx.exe

    if not exist %instdir%\msys64\usr\bin\msys-2.0.dll (
        :errorMsys
        echo -------------------------------------------------------------------------------
        echo.
        echo.- Download msys2 basic system failed,
        echo.- please download it manually from:
        echo.- https://github.com/msys2/msys2-installer/releases
        echo.- extract and put the msys2 folder into
        echo.- the root suite folder
        echo.- and start the batch script again!
        echo.
        echo -------------------------------------------------------------------------------
        pause
        exit
    )
)

rem getMintty
set "PATH=%instdir%\msys64\opt\bin;%instdir%\msys64\usr\bin;%PATH%"
if not exist %instdir%\mintty.lnk (
    echo.-------------------------------------------------------------------------------
    echo.- make a first run
    echo.-------------------------------------------------------------------------------
    call :runBash firstrun.log exit

    sed -i "s/#Color/Color/;/.*mingw32.*/d" %instdir%\msys64\etc\pacman.conf

    echo.-------------------------------------------------------------------------------
    echo.first update
    echo.-------------------------------------------------------------------------------
    title first msys2 update
    call :runBash firstUpdate.log pacman -Syu --noconfirm

    echo.-------------------------------------------------------------------------------
    echo.second update
    echo.-------------------------------------------------------------------------------
    title second msys2 update
    call :runBash secondUpdate.log pacman -Syu --noconfirm

    (
        echo.Set Shell = CreateObject("WScript.Shell"^)
        echo.Set link = Shell.CreateShortcut("%instdir%\mintty.lnk"^)
        echo.link.Arguments = "-full-path -mingw64"
        echo.link.Description = "msys2 shell console"
        echo.link.TargetPath = "%instdir%\msys64\msys2_shell.cmd"
        echo.link.WindowStyle = 1
        echo.link.IconLocation = "%instdir%\msys64\msys2.ico"
        echo.link.WorkingDirectory = "%instdir%\msys64"
        echo.link.Save
    )>%build%\setlink.vbs
    cscript /B /Nologo %build%\setlink.vbs
    del %build%\setlink.vbs
)

rem createFolders
mkdir %instdir%\vlc64\etc 2>NUL

rem checkFstab
set fstab=%instdir%\msys64\etc\fstab
for /f "tokens=1 delims= " %%a in ('findstr trunk %fstab%') do if not [%%a]==[%instdir%\] (
    findstr /V trunk %fstab% > %build%\fstab.
    move %build%\fstab. %fstab%
)
findstr /C:"/trunk" %fstab% >nul 2>&1 || echo.%instdir%\ /trunk ntfs binary,posix=0,noacl,user 0 0 >> %fstab%
findstr /C:"/build" %fstab% >nul 2>&1 || echo.%instdir%\build\ /build ntfs binary,posix=0,noacl,user 0 0 >> %fstab%
findstr vlc64 %fstab% >nul 2>&1 || echo.%instdir%\vlc64\ /vlc64 ntfs binary,posix=0,noacl,user 0 0 >> %fstab%

if not exist "%instdir%\msys64\home\%USERNAME%" mkdir "%instdir%\msys64\home\%USERNAME%"
if not exist "%instdir%\home\%USERNAME%\.minttyrc" (
    printf %%s\n Locale=en_US Charset=UTF-8 Font=Consolas Columns=120 Rows=30 TERM=xterm-256color ^
    > "%instdir%\msys64\home\%USERNAME%\.minttyrc"
)

rem gitsettings
if not exist "%instdir%\msys64\home\%USERNAME%\.gitconfig" (
    echo.[user]
    echo.name = %USERNAME%
    echo.email = "%USERNAME%@%COMPUTERNAME%"
    echo.
    echo.[core]
    echo.autocrlf = false
    echo.
    echo.[am]
    echo.threeWay = true
    echo.
    echo.[apply]
    echo.ignorewhitespace = change
    echo.
    echo.[color]
    echo.ui = true
    echo.
    echo.[fetch]
    echo.recurseSubmodules = true
    echo.prune = true
    echo.pruneTags = true
    echo.parallel = 0
    echo.
    echo.[submodule]
    echo.recurse = true
    echo.fetchJobs = 0
    echo.
    echo.[feature]
    echo.manyFiles = true
)>"%instdir%\msys64\home\%USERNAME%\.gitconfig"

rem installbase
echo.-------------------------------------------------------------------------------
echo.Checking base install packages
echo.-------------------------------------------------------------------------------
title install base system
call :runBash pacman.log pacman -S --noconfirm --needed %msyspackages%

for %%i in (%instdir%\msys64\usr\ssl\cert.pem) do if %%~zi==0 call :runBash cert.log update-ca-trust

setlocal EnableDelayedExpansion
rem installmingw
set mingw64packages=
for %%i in (%mingwpackages%) do (
    set "mingw64packages=!mingw64packages! mingw-w64-x86_64-%%i"
)

if not exist %instdir%\msys64\mingw64\bin\gcc.exe (
    :getmingw
    echo.-------------------------------------------------------------------------------
    echo.install 64 bit toolchain
    echo.-------------------------------------------------------------------------------
    title install 64 bit compiler
    call :runBash mingw64.log pacman -S --noconfirm --needed mingw-w64-x86_64-toolchain %mingw64packages%

    if not exist %instdir%\msys64\mingw64\bin\gcc.exe (
        echo -------------------------------------------------------------------------------
        echo.
        echo.MinGW64 GCC compiler isn't installed; maybe the download didn't work
        echo.Do you want to try it again?
        echo.
        echo -------------------------------------------------------------------------------
        set /P try="try again [y/n]: "

        if [%try%]==[y] GOTO getmingw
        exit
    )
)
endlocal & (
    set "mingw64packages=%mingw64packages%"
)

rem Setup git
echo.-------------------------------------------------------------------------------
echo.Checking if the suite has been updated...
echo.-------------------------------------------------------------------------------
cd %instdir%
if not exist %instdir%\.git (
    git clone -n "https://github.com/m-ab-s/vlc-autobuild_suite.git" vabs
    move vabs/.git .
    rmdir /S /Q vabs
)
git remote get-url origin > nul 2>&1 || git remote add -f origin "https://github.com/m-ab-s/vlc-autobuild_suite.git"
git fetch --all

set oldHead=000000
set newHead=000000

for /f "usebackq tokens=*" %%f in (`git merge-base HEAD "@{upstream}"`) do set oldHead=%%f
for /f "usebackq tokens=*" %%f in (`git rev-parse "@{upstream}"`) do set newHead=%%f

setlocal EnableDelayedExpansion
if not "%oldHead%"=="%newHead%" (
    echo.Updates detected, attempting an update
    git diff --exit-code --quiet "@{upstream}" || (
        set stashFile=user-changes-!random!.diff
        echo.Changes to the suite detected
        git diff "@{upstream}" 2> nul > !stashFile!
        echo.your latest changes were put into !stashFile!
    )
    git reset --hard "@{upstream}"
    echo.Update finished.
    echo.You might want to consider restarting the suite from here to make sure you
    echo.are running with the latest suite in case an issue was resolved.
    sleep 3
)
endlocal

rem Get suite files
git remote get-url mabs > nul 2>&1 || git remote add -f mabs "https://github.com/m-ab-s/media-autobuild_suite.git"
git fetch --all
git remote set-head -a mabs
git checkout mabs/HEAD -- "%build%\bash.sh" "%build%\media-suite_helper.sh"
git checkout -- "%build%\vlc-suite_compile.sh" "%build%\vlc-suite_helper.sh"
git rm --cached "%build%\bash.sh" "%build%\media-suite_helper.sh"

echo.-------------------------------------------------------------------------------
echo.Updating pacman database...
echo.-------------------------------------------------------------------------------

pacman -Syy
pacman -Qi %msyspackages% %mingw64packages% > nul 2>&1 || (
    echo.-------------------------------------------------------------------------------
    echo.You're missing some packages!
    echo.Do you want to install them?
    echo.-------------------------------------------------------------------------------
    echo.
    pacman -Qi %msyspackages% %mingw64packages% 2>&1 > nul | sed "s/error: package '//;s/' was not found//"
    set /P yn="install packs [y/N]? "
    if "%yn%"=="y" pacman -S --needed --noconfirm %msyspackages% %mingw64packages%
)

bash -lc 'type rustup' > nul 2>&1 && (
    echo.Updating rust...
    bash -lc 'rustup update'
)

echo.-------------------------------------------------------------------------------
echo.Updating msys2 system and installed packages...
echo.-------------------------------------------------------------------------------

rem Update twice to make sure to catch core updates then generic packages
pacman -Suu --noconfirm --overwrite "/mingw64/*" --overwrite "/mingw32/*" --overwrite "/usr/*"
pacman -Suu --noconfirm --overwrite "/mingw64/*" --overwrite "/mingw32/*" --overwrite "/usr/*"

echo.-------------------------------------------------------------------------------
echo.Updates finished.
echo.-------------------------------------------------------------------------------

rem ------------------------------------------------------------------
rem write config profiles:
rem ------------------------------------------------------------------

(
    echo.export MSYSTEM=MINGW64
    echo.source /etc/msystem
    echo.bits=64bit
    echo.# package installation prefix and package build directory
    echo.export LOCALDESTDIR=/vlc64 LOCALBUILDDIR=/build
    echo.
    echo.alias dir='ls -la --color=auto' ls='ls --color=auto'
    echo.export CC="ccache %CC%" CXX="ccache %CXX%"
    echo.
    echo.export CARCH=${MINGW_CHOST%%%%-*}
    echo.CPATH=$(cygpath -pm $LOCALDESTDIR/include:$MINGW_PREFIX/include^)
    echo.LIBRARY_PATH=$(cygpath -pm $LOCALDESTDIR/lib:$MINGW_PREFIX/lib^)
    echo.export LIBRARY_PATH CPATH
    echo.
    echo.CFLAGS="-D_FORTIFY_SOURCE=2 -D__USE_MINGW_ANSI_STDIO=1 -D_FILE_OFFSET_BITS=64 -D_LARGEFILE64_SOURCE=1 -mtune=generic -O3 -pipe -fstack-protector-strong"
    echo.[[ $CC = *gcc ]] ^&^& CFLAGS+=" -mthreads"
    echo.export CFLAGS CXXFLAGS=$CFLAGS
    echo.export LDFLAGS="-pipe -Wl,--dynamicbase,--high-entropy-va,--nxcompat -static-libgcc -static-libstdc++"
    echo.export RUSTFLAGS="-C target-feature=+crt-static"
    echo.export RUST_TRIPLE=x86_64-pc-windows-gnu
    echo.
    echo.export MANPATH=$LOCALDESTDIR/share/man:$MINGW_PREFIX/share/man:/usr/share/man
    echo.export INFOPATH=$LOCALDESTDIR/share/info:$MINGW_PREFIX/share/info:/usr/share/info
    echo.export DXSDK_DIR=$MINGW_PREFIX/$MINGW_CHOST
    echo.export ACLOCAL_PATH=$LOCALDESTDIR/share/aclocal:$MINGW_PREFIX/share/aclocal:/usr/share/aclocal
    echo.export PKG_CONFIG="$MINGW_PREFIX/bin/pkg-config --static"
    echo.export PKG_CONFIG_PATH=$LOCALDESTDIR/lib/pkgconfig:$MINGW_PREFIX/lib/pkgconfig:$MINGW_PREFIX/share/pkgconfig
    echo.
    echo.export CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/cargo
    echo.export CCACHE_DIR=$HOME/.ccache
    echo.
    echo.export LANG=en_US.UTF-8
    echo.PATH=$MINGW_PREFIX/bin:$INFOPATH:$MSYS2_PATH:$ORIGINAL_PATH
    echo.PATH=$LOCALDESTDIR/bin-audio:$LOCALDESTDIR/bin-global:$LOCALDESTDIR/bin-video:$LOCALDESTDIR/bin:$PATH
    echo.PATH=/opt/cargo/bin:/opt/bin:$PATH
    echo.source /etc/profile.d/perlbin.sh
    echo.export PS1='\[\033[32m\]\u@\h \[\e[33m\]\w\[\e[0m\]\n\$ '
    echo.export HOME=/home/$USERNAME
    echo.GIT_GUI_LIB_DIR=$(cygpath -w /usr/share/git-gui/lib^)
    echo.export PATH GIT_GUI_LIB_DIR
    echo.stty susp undef
    echo.export MAKEFLAGS="-j${cpuCount:-$((($(nproc) + 2) / 2))}"
    echo.export GNULIB_SRCDIR=$LOCALBUILDDIR/gnulib-git
    echo.test -f "$LOCALDESTDIR/etc/custom_profile" ^&^& source "$LOCALDESTDIR/etc/custom_profile"
    echo.cd /trunk
)>"%instdir%\vlc64\etc\profile2.local"
dos2unix -q %instdir%\vlc64\etc\profile2.local

(
    echo.DLAGENTS=('http::/usr/bin/curl -qb "" -fLC - --retry 3 --retry-delay 3 -o %%o %%u'
    echo.          'https::/usr/bin/curl -qb "" -fLC - --retry 3 --retry-delay 3 -o %%o %%u'^)
    echo.VCSCLIENTS=(bzr::bzr git::git hg::mercurial svn::subversion^)
    echo.GIT_COMMITTER_NAME="%USERNAME%"
    echo.GIT_COMMITTER_EMAIL="%USERNAME%@%COMPUTERNAME%"
    echo.gitam_mkpkg(^) { git am --committer-date-is-author-date "$@"; }
    echo.CHOST=$MINGW_CHOST
    echo.BUILDENV=(!distcc color ccache check !sign^)
    echo.OPTIONS=(
    if "%stripFile%"=="true" (
        echo.strip
    ) else (
        echo.!strip
    )
    echo.docs !libtool staticlibs emptydirs zipman purge !debug^)
    echo.INTEGRITY_CHECK=(md5^)
    echo.STRIP_BINARIES="--strip-all"
    echo.STRIP_SHARED="--strip-unneeded"
    echo.STRIP_STATIC="--strip-debug"
    echo.MAN_DIRS=({mingw,vlc}64{{,/local}{,/share},/opt/*}/{man,info}^)
    echo.DOC_DIRS=({mingw,vlc}64/{,local/}{,share/}{doc,gtk-doc}^)
    echo.PURGE_TARGETS=({mingw,vlc}64/{,share}/info/dir .packlist *.pod^)
    echo.PACKAGER="%USERNAME% <%USERNAME%@%COMPUTERNAME%>"
    echo.COMPRESSGZ=(gzip -cfn9^)
    echo.COMPRESSZST=(zstd -c -T0 --ultra -20 -^)
    echo.PKGEXT='.pkg.tar.zst'
    echo.SRCEXT='.src.tar.gz'
)>%instdir%\vlc64\etc\makepkg.conf
dos2unix -q %instdir%\vlc64\etc\makepkg.conf

mkdir "%instdir%\msys64\home\%USERNAME%\.gnupg" > nul 2>&1
findstr "hkps://keys.openpgp.org" "%instdir%\msys64\home\%USERNAME%\.gnupg\gpg.conf" >nul 2>&1 || echo.keyserver hkps://keys.openpgp.org >> "%instdir%\msys64\home\%USERNAME%\.gnupg\gpg.conf"

rem loginProfile
if exist %instdir%\msys64\etc\profile.pacnew ^
    move /y %instdir%\msys64\etc\profile.pacnew %instdir%\msys64\etc\profile
(
    echo.case $- in
    echo.*i*^) ;;
    echo.*^) export LANG=en_US.UTF-8 ;;
    echo.esac
    echo.source /vlc64/etc/profile2.local
)>%instdir%\msys64\etc\profile.d\Zab-suite.sh

rem compileLocals
cd %instdir%
title VABSbat
del %build%\compilation_failed %build%\compilation_failed > nul 2>&1

REM Test mklink availability
set "MSYS="
mkdir testmklink 2>nul
mklink /d linkedtestmklink testmklink >nul 2>&1 && (
    set MSYS="winsymlinks:nativestrict"
    rmdir /q linkedtestmklink
)
rmdir /q testmklink

endlocal & (
set compileArgs=--cpuCount=%cpuCount% --stripping=%stripFile% --timeStamp=%timeStamp%
    set "MSYSTEM=MINGW64"
    set "MSYS2_PATH_TYPE=inherit"
    set "MSYS=%MSYS%"
    set "PATH=%PATH%"
    set "build=%build%"
    set "instdir=%instdir%"
)
echo.-------------------------------------------------------------------------------
echo.Running compilation
echo.-------------------------------------------------------------------------------
call :runBash compile.log /build/vlc-suite_compile.sh %compileArgs%
exit /B %ERRORLEVEL%
endlocal
goto :EOF

:runBash
setlocal enabledelayedexpansion
set "log=%1"
shift
set args=%*
set arg=!args:%log% =!
if "%log%"=="""" (
    start "bash" /B /LOW /WAIT bash "%build%\bash.sh" "/dev/null" "%arg%"
) else (
    start "bash" /B /LOW /WAIT bash "%build%\bash.sh" "%build%\%log%" "%arg%"
)
endlocal
goto :EOF
