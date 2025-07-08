:: Inspired
::  https://github.com/skeeto/dotfiles/blob/3de1fcfa2eb4987387f84b779aba5163555f5d2c/init.bat
::  https://github.com/TairikuOokami/Windows/blob/main/Windows%20Tweaks.bat
::  https://qiita.com/__S/items/128ce3cb30a54a1b3a6e
::  https://gist.github.com/kajott/05b84fb630b4bc6c90337131f320a5c9
::  https://coolvitto.hateblo.jp/entry/2024/03/19/214513

:: A one-shot, first-time Windows configuration script that disables some
:: Windows misfeatures and sets paths to my usual preferences. I wish this
:: script could do more, especially to disable Windows' built-in adware and
:: spyware, but following Microsoft's usual mediocrity, Windows remains a
:: toy operating system with most configuration inaccessible to scripts.

:: CAUTION! only edit HKCU, not HKLM!

:: First, create backup directory
set date_yymmdd=%date:~0,4%%date:~5,2%%date:~8,2%
set time2=%time: =0%
set time_hhmmss=%time2:~0,2%%time2:~3,2%%time2:~6,2%
set backup_dir=%localappdata%\registry-backup\%date_yymmdd%_%time_hhmmss%
mkdir "%backup_dir%"

:: Annoyances
set key=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer
reg export "%key%" "%backup_dir%\Explorer.reg"
reg add "%key%" /f /v AltTabSettings                    /t REG_DWORD /d 1

set key=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced
reg export "%key%" "%backup_dir%\Explorer_Advanced.reg"
reg add "%key%" /f /v TaskbarGlomLevel                  /t REG_DWORD /d 2
  :: Display hidden file
reg add "%key%" /f /v Hidden                            /t REG_DWORD /d 1
reg add "%key%" /f /v ShowSuperHidden                   /t REG_DWORD /d 1
reg add "%key%" /f /v HideFileExt                       /t REG_DWORD /d 0
reg add "%key%" /f /v ShowCortanaButton                 /t REG_DWORD /d 0
reg add "%key%" /f /v ShowTaskViewButton                /t REG_DWORD /d 0
reg add "%key%" /f /v StoreAppsOnTaskbar                /t REG_DWORD /d 0
reg add "%key%" /f /v MultiTaskingAltTabFilter          /t REG_DWORD /d 3
reg add "%key%" /f /v TaskbarAnimations                 /t REG_DWORD /d 0
reg add "%key%" /f /v DisallowShaking                   /t REG_DWORD /d 1
reg add "%key%" /f /v Start_ShowClassicMode             /t REG_DWORD /d 1
reg add "%key%" /f /v TaskbarAl                         /t REG_DWORD /d 0
reg add "%key%" /f /v TaskbarSi                         /t REG_DWORD /d 0
reg add "%key%" /f /v TaskbarDa                         /t REG_DWORD /d 0
  :: Shoud disable if use tiling window manager.        
reg add "%key%" /f /v JointResize                       /t REG_DWORD /d 0
reg add "%key%" /f /v SnapFill                          /t REG_DWORD /d 0
reg add "%key%" /f /v SnapAssist                        /t REG_DWORD /d 0
  :: Open "PC" as "Open exploler" instead of "Quick Access".
reg add "%key%" /f /v LaunchTo                          /t REG_DWORD /d 1
  :: Ads
reg add "%key%" /f /v ShowSyncProviderNotifications     /t REG_DWORD /d 0
reg add "%key%" /f /v Start_IrisRecommendations         /t REG_DWORD /d 0
reg add "%key%" /f /v UseCompactMode                    /t REG_DWORD /d 1

set key=HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager
reg export "%key%" "%backup_dir%\ContentDeliveryManager.reg"
reg add "%key%" /f /v RotatingLockScreenOverlayEnabled  /t REG_DWORD /d 0

set key="HKCU\Control Panel\International\User Profile"
reg export %key% "%backup_dir%\User_Profile.reg"
reg add %key% /f /v HttpAcceptLanguageOptOut          /t REG_DWORD /d 0

set key=HKCU\Software\Policies\Microsoft\Windows\CloudContent
reg export "%key%" "%backup_dir%\Policies_CloudContent.reg"
reg add "%key%" /f /v DisableWindowsSpotlightWindowsWelcomeExperience  /t REG_DWORD /d 1

set key=HKCU\Software\Microsoft\Windows\CurrentVersion\CDP
reg export "%key%" "%backup_dir%\CDP.reg"
reg add "%key%" /f /v RomeSdkChannelUserAuthzPolicy     /t REG_DWORD /d 0
reg add "%key%" /f /v CdpSessionUserAuthzPolicy         /t REG_DWORD /d 0

:: Set legacy contect menu
set key=HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32
reg export "%key%" "%backup_dir%\86ca1aa0-34aa-4e8b-a509-50c905bae2a2_InprocServer32.reg"
reg add "%key%" /f /ve                          /t REG_SZ    /d ""

set key=HKCU\Software\Microsoft\Windows\CurrentVersion\Search
reg export "%key%" "%backup_dir%\Search.reg"
reg add "%key%" /f /v SearchboxTaskbarMode      /t REG_DWORD /d 0
reg add "%key%" /f /v BingSearchEnabled         /t REG_DWORD /d 0
reg add "%key%" /f /v AllowCortana              /t REG_DWORD /d 0
reg add "%key%" /f /v CortanaConsent            /t REG_DWORD /d 0

set key=HKCU\Control Panel\Desktop
reg export "%key%" "%backup_dir%\Desktop.reg"
  :: Cannot judge whether the curosr is cursor or I/l
  @REM reg add "%key%" /f /v CursorBlinkRate           /t REG_SZ    /d -1
reg add "%key%" /f /v MenuShowDelay             /t REG_SZ    /d 0
reg add "%key%" /f /v UserPreferencesMask       /t REG_BINARY /d 9012078010000000
reg add "%key%" /f /v JPEGImportQuality         /t REG_DWORD /d 100

set key=HKCU\Control Panel\Desktop\WindowMetrics
reg export "%key%" "%backup_dir%\WindowMetrics.reg"
reg add "%key%" /f /v MinAnimate                /t REG_SZ    /d 0
reg add "%key%" /f /v CaptionHeight             /t REG_SZ    /d -55

set key=HKCU\Control Panel\Accessibility
reg export "%key%" "%backup_dir%\Accessibility.reg"
reg add "%key%" /f /v DynamicScrollbars         /t REG_DWORD /d 0

:: I use taskber pinning.
@REM set key=HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Taskband
@REM reg delete "%key%" /f /v Favorites

set key=HKCU\SOFTWARE\Policies\Microsoft\Windows\Explorer
reg export "%key%" "%backup_dir%\Policies_Windows_Explorar.reg"
reg add "%key%" /f /v DisableSearchBoxSuggestions /t REG_DWORD /d 1


set key=HKCU\Software\Microsoft\Siuf\Rules
reg export "%key%" "%backup_dir%\Siuf_Rules.reg"
reg add "%key%" /f /v NumberOfSIUFInPeriod      /t REG_DWORD  /d 0
reg add "%key%" /f /v PeriodInNanoSeconds       /t REG_DWORD  /d 0

set key="HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"
reg export %key% "%backup_dir%\Shell.reg"
reg add %key% /f /v "FolderType"              /t REG_SZ     /d "NotSpecified"
