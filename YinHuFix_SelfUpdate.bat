@echo off
chcp 936 >nul 2>&1
setlocal enabledelayedexpansion
title YinHuFix - [8] 检查更新 @NovaPupil_
if not "%~1"=="MAIN" (
    echo.
    echo   [提示] 请直接运行主程序「YinHuFix_综合修复.bat」
    echo          本文件是功能模块，由主程序自动调用，无需单独运行。
    echo.
    pause
    exit /b 0
)
color 0B

set "K1=del"
set "K2=taskkill"
set "KF=%SystemRoot%\System32\find.exe"
set "CURL="
for %%c in ("%SystemRoot%\System32\curl.exe") do if exist "%%~c" set "CURL=%%~c"
REM ---- 更新源（Gitee 优先，GitHub 兜底；SFU_ROUTE/SFU_BASE_* 为调试覆盖项） ----
set "GITEE_RAW=https://gitee.com/novapupil/yinhufix/raw/master"
set "GH_RAW=https://raw.githubusercontent.com/Wmsqaq/yinhufix/master"
if defined SFU_BASE_GITEE set "GITEE_RAW=%SFU_BASE_GITEE%"
if defined SFU_BASE_GH set "GH_RAW=%SFU_BASE_GH%"
set "VERF=%TEMP%\sfk_upd_ver.txt"
set "ZIPF=%TEMP%\sfk_upd_pkg.zip"
set "HASHF=%TEMP%\sfk_upd_hash.txt"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo  [错误] 需要管理员权限。
    echo         请右键本文件, 选择"以管理员身份运行"。
    echo.
    pause
    exit /b 1
)
if not defined CURL (
    echo  [错误] 未找到系统 curl（%SystemRoot%\System32\curl.exe）。
    echo         Windows 10 1803+ 自带该组件，请勿删除。
    echo.
    pause
    exit /b 1
)

REM ---- 本地版本：从主程序标题行解析 ----
set "MAINBAT="
for %%f in ("%~dp0YinHuFix_*.bat") do (
    echo %%~nf | %SystemRoot%\System32\findstr.exe /i "AVInstall FixUpdate UnblockAV KillVariant SelfUpdate" >nul || set "MAINBAT=%%~ff"
)
if not defined MAINBAT (
    echo  [错误] 未找到主程序 YinHuFix_综合修复.bat。
    echo.
    pause
    exit /b 1
)
set "LVER="
for /f "tokens=2 delims==" %%v in ('findstr /b /c:"REM TOOLVER=" "%MAINBAT%" 2^>nul') do set "LVER=%%v"
if not defined LVER set "LVER=0"
echo.
echo  ============ 检查更新（Gitee / GitHub 双路线自动选择） ============
echo  本地版本: v%LVER%
echo.

REM ---- 第 1 步: 路线自动选择（Gitee 优先, 超时自动切 GitHub） ----
set "ROUTE="
set "RVER="
set "RURL="
set "RSHA="
set "RNOTE="
set "GTOKEN="
set "HTOKEN="
call :GETTOKENS
if /i not "%SFU_ROUTE%"=="github" (
    echo  [路线1] 正在连接 Gitee 源（国内直达）...
    call :FETCHVER "%GITEE_RAW%" "gitee"
    if defined RVER set "ROUTE=GITEE"
)
if not defined ROUTE if /i not "%SFU_ROUTE%"=="gitee" (
    echo  [路线2] Gitee 不可达, 改连 GitHub 源...
    call :FETCHVER "%GH_RAW%" "github"
    if defined RVER set "ROUTE=GH"
)
if not defined ROUTE (
    echo  [失败] 双路线均无法获取版本信息。
    echo         可能原因: 断网 / DNS 异常 / 仓库不存在或为私有且本机无凭据。
    echo         可稍后重试, 或到项目发布页手动下载新版。
    echo.
    echo  按任意键返回...
    pause >nul
    exit /b 0
)
if not defined RSHA (
    echo  [失败] 远端版本文件缺少 sha256 校验字段, 拒绝更新以防篡改。
    echo.
    pause
    exit /b 1
)
echo  [OK] 使用路线: %ROUTE%   远端版本: v%RVER%
if defined RNOTE echo  更新说明: %RNOTE%
echo.

REM ---- 第 2 步: 版本比较 ----
call :VERCMP "%LVER%" "%RVER%"
if "%VCMP%"=="NEW" goto DOUPDATE
if "%VCMP%"=="OLD" (
    echo  [提示] 远端版本 v%RVER% 比本地 v%LVER% 旧, 无需更新。
) else (
    echo  [OK] 已是最新版本 v%LVER%。
)
echo.
echo  按任意键返回...
pause >nul
exit /b 0

:DOUPDATE
choice /c YN /n /m "  发现新版本 v%RVER%(当前 v%LVER%), 是否下载并安装? (Y=更新 / N=跳过): "
if errorlevel 2 (
    echo  [跳过] 本次未更新。
    echo.
    pause
    exit /b 0
)
echo.
REM ---- 第 3 步: 下载更新包（所选路线, 失败自动切换另一路线） ----
set "ZOK=0"
call :DLZIP "%RURL%" "%ZIPF%"
if errorlevel 1 (
    echo  [提示] %ROUTE% 路线下载失败, 尝试另一路线...
    if "%ROUTE%"=="GITEE" (
        call :FETCHVER "%GH_RAW%" "github"
    ) else (
        call :FETCHVER "%GITEE_RAW%" "gitee"
    )
    if defined RURL (
        set "ROUTE=ALT"
        call :DLZIP "%RURL%" "%ZIPF%"
        if not errorlevel 1 set "ZOK=1"
    )
) else set "ZOK=1"
if "%ZOK%"=="0" (
    echo  [失败] 双路线均下载失败, 请检查网络后重试。
    echo.
    pause
    exit /b 1
)
REM ---- 第 4 步: SHA-256 完整性校验 ----
echo  [校验] 正在核对 SHA-256 ...
set "FSHA="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%ZIPF%" SHA256 2^>nul') do if not defined FSHA set "FSHA=%%h"
set "FSHA=!FSHA: =!"
set "RSHA=!RSHA: =!"
if /i not "!FSHA!"=="!RSHA!" (
    echo  [失败] 校验和不匹配, 下载包可能被篡改或传输损坏, 已删除。
    echo         期望: !RSHA!
    echo         实际: !FSHA!
    %K1% /f /q "%ZIPF%" >nul 2>&1
    echo.
    pause
    exit /b 1
)
echo  [OK] 完整性校验通过。
REM ---- 第 5 步: 解压并应用更新 ----
set "EXD=%TEMP%\YinHuUpdate_%RVER%"
%K1% /s /q "%EXD%" >nul 2>&1
powershell -NoProfile -Command "Expand-Archive -LiteralPath '%ZIPF%' -DestinationPath '%EXD%' -Force" >nul 2>&1
if errorlevel 1 (
    echo  [失败] 解压失败, 请手动解压: %ZIPF%
    echo.
    pause
    exit /b 1
)
set "NEWMAIN="
for %%f in ("%EXD%\YinHuFix_*.bat") do (
    echo %%~nf | %SystemRoot%\System32\findstr.exe /i "AVInstall FixUpdate UnblockAV KillVariant SelfUpdate" >nul || set "NEWMAIN=%%~ff"
)
if not defined NEWMAIN (
    echo  [失败] 更新包内容异常（缺少主程序）, 已放弃安装。
    %K1% /s /q "%EXD%" >nul 2>&1
    echo.
    pause
    exit /b 1
)
REM ---- 第 6 步: 生成安装器, 本程序退出后由其完成替换 ----
set "APPLY=%TEMP%\YinHuApply_%RVER%.bat"
> "%APPLY%" echo @echo off
>> "%APPLY%" echo ping -n 3 127.0.0.1 ^>nul
>> "%APPLY%" echo xcopy "%EXD%\*.*" "%~dp0" /y /q ^>nul
>> "%APPLY%" echo for %%%%h in (YinHuFix_UnblockAV.bat YinHuFix_FixUpdate.bat YinHuFix_AVInstall.bat YinHuFix_KillVariant.bat YinHuFix_SelfUpdate.bat) do attrib +h "%%%%h"
>> "%APPLY%" echo if exist "%~dp0杀毒软件安装包配置" attrib +h "%~dp0杀毒软件安装包配置"
>> "%APPLY%" echo rd /s /q "%EXD%"
>> "%APPLY%" echo %K1% /f /q "%ZIPF%" "%VERF%"
>> "%APPLY%" echo echo.
>> "%APPLY%" echo   更新到 v%RVER% 完成, 请重新运行主程序。
>> "%APPLY%" echo ping -n 4 127.0.0.1 ^>nul
>> "%APPLY%" echo del /f /q "%%~f0"
echo  [执行] 本窗口即将关闭, 更新将在后台完成...
start "" /min cmd /c ""%APPLY%""
exit
REM ============ 子程序区 ============

REM ---- :FETCHVER base platform ---- 从指定源取 version.txt 并解析
:FETCHVER
set "BASE=%~1"
set "PLAT=%~2"
set "RVER="
set "RURL="
set "RSHA="
set "RNOTE="
set "URL_G="
set "URL_H="
set "VFURL=%BASE%/version.txt"
set "EXTRA="
if "%PLAT%"=="gitee" if defined GTOKEN set "EXTRA=?access_token=%GTOKEN%"
set "HAUTH="
if "%PLAT%"=="github" if defined HTOKEN set "HAUTH=-H Authorization: token %HTOKEN%"
%CURL% -s -L %HAUTH% --connect-timeout 4 --max-time 15 "%VFURL%%EXTRA%" > "%VERF%" 2>nul
%KF% "version=" "%VERF%" >nul 2>&1
if not errorlevel 1 goto FVPARSE
REM ---- raw 路线失败: gitee 改走 contents API(base64), 兼容私有仓库 ----
if not "%PLAT%"=="gitee" goto :eof
if not defined GTOKEN goto :eof
%CURL% -s -L --connect-timeout 4 --max-time 15 "https://gitee.com/api/v5/repos/novapupil/yinhufix/contents/version.txt?access_token=%GTOKEN%" > "%VERF%" 2>nul
if not exist "%VERF%" %CURL% -s -L --connect-timeout 8 --max-time 20 "https://gitee.com/api/v5/repos/novapupil/yinhufix/contents/version.txt?access_token=%GTOKEN%" > "%VERF%" 2>nul
%KF% "content" "%VERF%" >nul 2>&1
if errorlevel 1 goto :eof
REM 解码时读写同一文件会先被重定向截断, 必须写临时文件再替换
powershell -NoProfile -Command "$j=Get-Content -LiteralPath '%VERF%' -Raw | ConvertFrom-Json; [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($j.content.Replace([string][char]10,'')))" > "%VERF%.b64" 2>nul
move /y "%VERF%.b64" "%VERF%" >nul 2>&1
:FVPARSE
for /f "tokens=1,* delims==" %%k in ('type "%VERF%" 2^>nul') do (
    if /i "%%k"=="version" set "RVER=%%l"
    if /i "%%k"=="url_gitee" set "URL_G=%%l"
    if /i "%%k"=="url_github" set "URL_H=%%l"
    if /i "%%k"=="sha256" set "RSHA=%%l"
    if /i "%%k"=="notes" set "RNOTE=%%l"
)
if "%PLAT%"=="gitee" (set "RURL=%URL_G%") else set "RURL=%URL_H%"
goto :eof

REM ---- :DLZIP url out ---- 下载更新包
:DLZIP
set "ZURL=%~1"
set "ZOUT=%~2"
%K1% /f /q "%ZOUT%" >nul 2>&1
REM 令牌只拼在请求里, 不回显
set "ZEXTRA="
echo %ZURL% | %KF% "gitee.com" >nul && if defined GTOKEN set "ZEXTRA=?access_token=%GTOKEN%"
set "ZAUTH="
echo %ZURL% | %KF% "github" >nul && if defined HTOKEN set "ZAUTH=-H Authorization: token %HTOKEN%"
%CURL% -s -L %ZAUTH% --connect-timeout 8 --max-time 120 -o "%ZOUT%" "%ZURL%%ZEXTRA%"
if errorlevel 1 goto :eof
if not exist "%ZOUT%" goto :eof
for %%s in ("%ZOUT%") do set "ZSZ=%%~zs"
if !ZSZ! lss 10240 goto :eof
exit /b 0

REM ---- :GETTOKENS ---- 仅当本机存有凭据时读取(不写入任何文件), 供私有仓库使用
:GETTOKENS
set "GITEXE="
for /f "delims=" %%g in ('where git 2^>nul') do if not defined GITEXE set "GITEXE=%%g"
if defined GITEXE (
    REM cmd 管道喂 git credential 有行尾兼容问题, 改用 PowerShell 喂入
    REM 解析用 type^|find + delims==（findstr/find 直接作 for 输入在该环境下不迭代）
    powershell -NoProfile -Command "'protocol=https','host=gitee.com','' | & '!GITEXE!' credential fill 2^>$null" > "%HASHF%" 2>nul
    for /f "tokens=2 delims==" %%p in ('type "%HASHF%" ^| %SystemRoot%\System32\find.exe "password"') do set "GTOKEN=%%p"
)
set "GHEXE="
for /f "delims=" %%g in ('where gh 2^>nul') do if not defined GHEXE set "GHEXE=%%g"
if defined GHEXE for /f "delims=" %%t in ('"%GHEXE%" auth token 2^>nul') do set "HTOKEN=%%t"
%K1% /f /q "%HASHF%" >nul 2>&1
goto :eof

REM ---- :VERCMP local remote ---- 比较版本, 结果 VCMP=NEW/OLD/EQ
:VERCMP
for /f "tokens=1,2 delims=." %%a in ("%~1") do (
    set /a LM=%%a 2>nul
    set /a LN=%%b 2>nul
)
for /f "tokens=1,2 delims=." %%a in ("%~2") do (
    set /a RM=%%a 2>nul
    set /a RN=%%b 2>nul
)
if not defined LM set /a LM=0
if not defined LN set /a LN=0
if not defined RM set /a RM=0
if not defined RN set /a RN=0
set "VCMP=EQ"
if !RM! gtr !LM! set "VCMP=NEW"
if !RM! equ !LM! if !RN! gtr !LN! set "VCMP=NEW"
if !RM! lss !LM! set "VCMP=OLD"
if !RM! equ !LM! if !RN! lss !LN! set "VCMP=OLD"
goto :eof
