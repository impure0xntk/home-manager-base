:: Toggle Windows proxy settings.
:: Usage: toggle-proxy.bat [on|off]
:: Without arguments, toggles based on the current ProxyEnable value.

setlocal enabledelayedexpansion
set "proxy_server=@PROXY_SERVER@"
set "proxy_url=@PROXY_URL@"
set "no_proxy=@NO_PROXY@"
set "arg=%~1"

if "%arg%" == "" (
  set "enabled=0x0"
  if "!enabled!" == "0x0" ( set "arg=on" ) else ( set "arg=off" )
)

if /i "%arg%" == "on" (
  setx HTTP_PROXY "%proxy_url%" > nul
  setx HTTPS_PROXY "%proxy_url%" > nul
  setx http_proxy "%proxy_url%" > nul
  setx https_proxy "%proxy_url%" > nul
  setx NO_PROXY "%no_proxy%" > nul
  set HTTP_PROXY=%proxy_url%
  set HTTPS_PROXY=%proxy_url%
  set http_proxy=%proxy_url%
  set https_proxy=%proxy_url%
  set NO_PROXY=%no_proxy%
  echo Proxy enabled: %proxy_server%
) else if /i "%arg%" == "off" (
  reg delete "HKCU\Environment" /f /v HTTP_PROXY > nul 2>&1
  reg delete "HKCU\Environment" /f /v HTTPS_PROXY > nul 2>&1
  reg delete "HKCU\Environment" /f /v http_proxy > nul 2>&1
  reg delete "HKCU\Environment" /f /v https_proxy > nul 2>&1
  reg delete "HKCU\Environment" /f /v NO_PROXY > nul 2>&1
  set HTTP_PROXY=
  set HTTPS_PROXY=
  set http_proxy=
  set https_proxy=
  set NO_PROXY=
  echo Proxy disabled.
) else (
  echo Usage: %~nx0 [on^|off]
  endlocal
  exit /b 1
)

endlocal
