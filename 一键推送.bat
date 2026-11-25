@echo off
chcp 65001 >nul
title 云峰工作台 - 推送到 GitHub

echo.
echo  这个脚本把当前目录推到你的 GitHub 仓库，会自动触发云端编译。
echo  先确认：已经在 GitHub 建好一个空仓库（可以 Private）。
echo.

set /p REPO=粘贴仓库地址（形如 https://github.com/你的名/yunfeng-hub.git）: 
if "%REPO%"=="" (
    echo 没填地址，退出。
    pause
    exit /b
)

git --version >nul 2>&1
if errorlevel 1 (
    echo 这台电脑没装 Git，先去 https://git-scm.com/download/win 装一个再回来。
    pause
    exit /b
)

git init
git add .
git commit -m "云峰工作台 iOS 工程"
git branch -M main
git remote remove origin 2>nul
git remote add origin %REPO%
git push -u origin main

echo.
echo  推完了。打开仓库的 Actions 标签，等 Build Unsigned IPA 变绿，
echo  在运行详情页底部 Artifacts 下载 YunfengHub-unsigned-ipa。
echo.
pause
