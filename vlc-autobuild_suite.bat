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

set iniOptions=arch CC cores strip pack timeStamp

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

:selectSystem
if %archINI%==0 (
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    echo.
    echo. Select the target binaries:
    echo. 1 = both [32 bit and 64 bit]
    echo. 2 = 32 bit
    echo. 3 = 64 bit
    echo.
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    set /P buildEnv="Build System: "
) else set buildEnv=%archINI%

if "%buildEnv%"=="" GOTO selectSystem
if %buildEnv% GTR 3 GOTO selectSystem
if %buildEnv%==1 set build32=true && set build64=true
if %buildEnv%==2 set build32=true && set build64=false
if not defined build64 set build32=false && set build64=true
if %deleteINI%==1 echo.arch=^%buildEnv%>>%ini%

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

:packEXE
if %packINI%==0 (
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    echo.
    echo. Pack compiled files?
    echo. 1 = Yes
    echo. 2 = No [recommended]
    echo.
    echo. Attention: Some security applications may detect packed binaries as malware.
    echo. Increases delay on runtime during which files need to be unpacked.
    echo. Makes binaries smaller at a big time cost after compiling and on runtime.
    echo.
    echo. If distributing the files, consider packing them with 7-zip instead.
    echo.
    echo -------------------------------------------------------------------------------
    echo -------------------------------------------------------------------------------
    set /P packF="Pack files: "
) else set packF=%packINI%

if "%packF%"=="" GOTO packEXE
if %packF% GTR 2 GOTO packEXE
if %packF%==1 set packFile=true
if not defined packFile set packFile=false
if %deleteINI%==1 echo.pack=^%packF%>>%ini%

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

    sed -i "s/#Color/Color/" %instdir%\msys64\etc\pacman.conf

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
if %build32%==true (
    mkdir %instdir%\vlc32 2>NUL
    mkdir %instdir%\vlc32\etc 2>NUL
)
if %build64%==true (
    mkdir %instdir%\vlc64 2>NUL
    mkdir %instdir%\vlc64\etc 2>NUL
)

rem checkFstab
set fstab=%instdir%\msys64\etc\fstab
for /f "tokens=1 delims= " %%a in ('findstr trunk %fstab%') do if not [%%a]==[%instdir%\] (
    findstr /V trunk %fstab% > %build%\fstab.
    move %build%\fstab. %fstab%
)
findstr /C:"/trunk" %fstab% >nul 2>&1 || echo.%instdir%\ /trunk ntfs binary,posix=0,noacl,user 0 0 >> %fstab%
findstr /C:"/build" %fstab% >nul 2>&1 || echo.%instdir%\build\ /build ntfs binary,posix=0,noacl,user 0 0 >> %fstab%
if %build32%==false (
    findstr vlc32 %fstab% >nul 2>&1 && (
        findstr /V vlc32 %fstab% > %build%\fstab.
        move %build%\fstab. %fstab%
    )
) else findstr vlc32 %fstab% >nul 2>&1 || echo.%instdir%\vlc32\ /vlc32 ntfs binary,posix=0,noacl,user 0 0 >> %fstab%
if %build64%==false (
    findstr vlc64 %fstab% >nul 2>&1 && (
        findstr /V vlc64 %fstab% > %build%\fstab.
        move %build%\fstab. %fstab%
    )
) else findstr vlc64 %fstab% >nul 2>&1 || echo.%instdir%\vlc64\ /vlc64 ntfs binary,posix=0,noacl,user 0 0 >> %fstab%

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

rem makepkg conf
(
    echo.#!/usr/bin/sed -f
    echo.s^|#PACKAGER="John Doe <john@doe.com>"^|PACKAGER="%USERNAME% <%USERNAME%@%COMPUTERNAME%>"^|
    echo.s^|GIT_COMMITTER_NAME="makepkg"^|GIT_COMMITTER_NAME="%USERNAME%"^|
    echo.s^|GIT_COMMITTER_EMAIL="makepkg@msys2.org"^|GIT_COMMITTER_EMAIL="%USERNAME%@%COMPUTERNAME%"^|
    echo.s^|^^BUILDENV=(fakeroot ^!distcc color ^!ccache check ^!sign^)^|BUILDENV=(!distcc color ccache check !sign^)^|
) > makepkg.sed
sed -f makepkg.sed -i %instdir%\msys64\etc\makepkg.conf %instdir%\msys64\etc\makepkg_mingw64.conf %instdir%\msys64\etc\makepkg_mingw32.conf
del makepkg.sed

if "%stripFile%"=="true" (
    sed -i 's/!strip/strip/' %instdir%\msys64\etc\makepkg.conf %instdir%\msys64\etc\makepkg_mingw64.conf %instdir%\msys64\etc\makepkg_mingw32.conf
) else (
    sed -i 's/strip/!strip/' %instdir%\msys64\etc\makepkg.conf %instdir%\msys64\etc\makepkg_mingw64.conf %instdir%\msys64\etc\makepkg_mingw32.conf
)

rem installbase
if not exist %instdir%\msys64\usr\bin\make.exe (
    echo.-------------------------------------------------------------------------------
    echo.install msys2 base system
    echo.-------------------------------------------------------------------------------
    title install base system
    call :runBash pacman.log pacman -S --noconfirm --needed %msyspackages%
)

for %%i in (%instdir%\msys64\usr\ssl\cert.pem) do if %%~zi==0 call :runBash cert.log update-ca-trust

setlocal EnableDelayedExpansion
rem installmingw
set mingw64packages=
set mingw32packages=
for %%i in (%mingwpackages%) do (
    set "mingw32packages=!mingw32packages! mingw-w64-i686-%%i"
    set "mingw64packages=!mingw64packages! mingw-w64-x86_64-%%i"
)

if %build32%==true call :getmingw 32
if %build64%==true call :getmingw 64
endlocal & (
    set "mingw32packages=%mingw32packages%"
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
if not exist "%build%\vlc-suite_compile.sh" git checkout ${u} -- "%build%\vlc-suite_compile.sh"
git remote get-url mabs > nul 2>&1 || git remote add -f mabs "https://github.com/m-ab-s/media-autobuild_suite.git"
git fetch --all
git remote set-head -a mabs
git checkout mabs/HEAD -- "%build%\bash.sh" "%build%\media-suite_helper.sh"

echo.-------------------------------------------------------------------------------
echo.Updating pacman database...
echo.-------------------------------------------------------------------------------

pacman -Syy
set "packagestoinstall=%msyspackages%"

if %build32%==true set "packagestoinstall=%mingw32packages%"
if %build64%==true set "packagestoinstall=%mingw64packages%"
pacman -Qi %packagestoinstall% > nul 2>&1 || (
    echo.-------------------------------------------------------------------------------
    echo.You're missing some packages!
    echo.Do you want to install them?
    echo.-------------------------------------------------------------------------------
    echo.
    pacman -Qi %packagestoinstall% 2>&1 > nul | sed "s/error: package '//;s/' was not found//"
    set /P yn="install packs [y/N]? "
    if "%yn%"=="y" pacman -S --needed --noconfirm %packagestoinstall%
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

if %build32%==true call :writeProfile 32
if %build64%==true call :writeProfile 64

mkdir "%instdir%\msys64\home\%USERNAME%\.gnupg" > nul 2>&1
mkdir "%instdir%\msys64\home\%USERNAME%\.gnupg\" > nul 2>&1
findstr "hkps://keys.openpgp.org" "%instdir%\msys64\home\%USERNAME%\.gnupg\gpg.conf" >nul 2>&1 || echo.keyserver hkps://keys.openpgp.org >> "%instdir%\msys64\home\%USERNAME%\.gnupg\gpg.conf"

rem loginProfile
if exist %instdir%\msys64\etc\profile.pacnew ^
    move /y %instdir%\msys64\etc\profile.pacnew %instdir%\msys64\etc\profile
findstr /C:"profile2.local" %instdir%\msys64\etc\profile.d\Zab-suite.sh >nul 2>&1 || (
    echo.if [[ $MSYSTEM = MINGW32 ]]; then
    echo.   source /vlc32/etc/profile2.local
    echo.else
    echo.   source /vlc64/etc/profile2.local
    echo.fi
)>%instdir%\msys64\etc\profile.d\Zab-suite.sh

findstr /C:"LANG" %instdir%\msys64\etc\profile.d\Zab-suite.sh >nul 2>&1 || (
    echo.case $- in
    echo.*i*^) ;;
    echo.*^) export LANG=en_US.UTF-8 ;;
    echo.esac
)>>%instdir%\msys64\etc\profile.d\Zab-suite.sh

rem compileLocals
cd %instdir%
title VABSbat
if exist %build%\compilation_failed del %build%\compilation_failed
if exist %build%\fail_comp del %build%\compilation_failed

REM Test mklink availability
set "MSYS="
mkdir testmklink 2>nul
mklink /d linkedtestmklink testmklink >nul 2>&1 && (
    set MSYS="winsymlinks:nativestrict"
    rmdir /q linkedtestmklink
)
rmdir /q testmklink

endlocal & (
set compileArgs=--cpuCount=%cpuCount% --build32=%build32% --build64=%build64% ^
--stripping=%stripFile% --packing=%packFile% --timeStamp=%timeStamp%
    if %build64%==yes ( set "MSYSTEM=MINGW64" ) else set "MSYSTEM=MINGW32"
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

:getmingw
setlocal
if exist %instdir%\msys64\mingw%1\bin\gcc.exe GOTO :EOF
echo.-------------------------------------------------------------------------------
echo.install %1 bit toolchain
echo.-------------------------------------------------------------------------------
title install %1 bit compiler
if "%1"=="32" (
    call :runBash mingw32.log pacman -S --noconfirm --needed mingw-w64-i686-toolchain %mingw32packages%
) else (
    call :runBash mingw64.log pacman -S --noconfirm --needed mingw-w64-x86_64-toolchain %mingw64packages%
)

if not exist %instdir%\msys64\mingw%1\bin\gcc.exe (
    echo -------------------------------------------------------------------------------
    echo.
    echo.MinGW%1 GCC compiler isn't installed; maybe the download didn't work
    echo.Do you want to try it again?
    echo.
    echo -------------------------------------------------------------------------------
    set /P try="try again [y/n]: "

    if [%try%]==[y] GOTO getmingw %1
    exit
)
endlocal
goto :EOF

:writeProfile
(
    echo.MSYSTEM=MINGW%1
    echo.source /etc/msystem
    echo.
    echo.# package installation prefix and package build directory
    echo.export LOCALDESTDIR=/vlc%1 LOCALBUILDDIR=/build
    echo.
    echo.bits='%1bit'
    echo.
    echo.alias dir='ls -la --color=auto'
    echo.alias ls='ls --color=auto'
    if %CC%==clang (
        echo.export CC="ccache clang"
        echo.export CXX="ccache clang++"
    ) else (
        echo.export CC="ccache gcc"
        echo.export CXX="ccache g++"
    )
    echo.
    echo.CARCH="${MINGW_CHOST%%%%-*}"
    echo.CPATH="$(cygpath -m $LOCALDESTDIR/include $MINGW_PREFIX/include | tr '\n' ';')"
    echo.LIBRARY_PATH="$(cygpath -m $LOCALDESTDIR/lib $MINGW_PREFIX/lib | tr '\n' ';')"
    echo.
    echo.CPPFLAGS="-D_FORTIFY_SOURCE=2"
    echo.CFLAGS="-mtune=generic -O3 -pipe -fstack-protector-strong"
    echo.[[ $CC = *gcc ]] ^&^& CFLAGS+=" -mthreads"
    echo.CXXFLAGS="${CFLAGS}"
    echo.LDFLAGS="-pipe -static-libgcc -static-libstdc++"
    echo.RUSTFLAGS="-C target-feature=+crt-static"
    echo.RUST_TRIPLE="x86_64-pc-windows-gnu"
    echo.
    echo.MANPATH="${LOCALDESTDIR}/share/man:${MINGW_PREFIX}/share/man:/usr/share/man"
    echo.INFOPATH="${LOCALDESTDIR}/share/info:${MINGW_PREFIX}/share/info:/usr/share/info"
    echo.export DXSDK_DIR="${MINGW_PREFIX}/${MINGW_CHOST}"
    echo.export ACLOCAL_PATH="${LOCALDESTDIR}/share/aclocal:${MINGW_PREFIX}/share/aclocal:/usr/share/aclocal"
    echo.export PKG_CONFIG="${MINGW_PREFIX}/bin/pkg-config --static"
    echo.export PKG_CONFIG_PATH="${LOCALDESTDIR}/lib/pkgconfig:${MINGW_PREFIX}/lib/pkgconfig"
    echo.
    echo.export CPATH LIBRARY_PATH CPPFLAGS CFLAGS CXXFLAGS LDFLAGS MSYSTEM
    echo.
    echo.export CARGO_HOME="/opt/cargo" RUSTUP_HOME="/opt/cargo"
    echo.export CCACHE_DIR="$HOME/.ccache"
    echo.
    echo.export LANG=en_US.UTF-8
    echo.PATH="${MINGW_PREFIX}/bin:${INFOPATH}:${MSYS2_PATH}:${ORIGINAL_PATH}"
    echo.PATH="${LOCALDESTDIR}/bin-audio:${LOCALDESTDIR}/bin-global:${LOCALDESTDIR}/bin-video:${LOCALDESTDIR}/bin:${PATH}"
    echo.PATH="/opt/cargo/bin:/opt/bin:${PATH}"
    echo.source '/etc/profile.d/perlbin.sh'
    echo.export PS1='\[\033[32m\]\u@\h \[\e[33m\]\w\[\e[0m\]\n\$ '
    echo.export HOME="/home/${USERNAME}"
    echo.GIT_GUI_LIB_DIR="$(cygpath -w /usr/share/git-gui/lib)"
    echo.export PATH GIT_GUI_LIB_DIR
    echo.stty susp undef
    echo.export MAKEFLAGS="$cpuCount"
    echo.test -f "$LOCALDESTDIR/etc/custom_profile" ^&^& source "$LOCALDESTDIR/etc/custom_profile"
    echo.cd /trunk
)>%instdir%\vlc%1\etc\profile2.local
dos2unix -q %instdir%\vlc%1\etc\profile2.local
goto :EOF
