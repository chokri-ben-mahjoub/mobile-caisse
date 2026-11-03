@echo off
rem Ouvre la caisse en plein ?cran (mode kiosque tactile) avec Edge, sinon Chrome.
set "PAGE=file:///%~dp0caisse-pos-desktop.html"
set "PAGE=%PAGE:\=/%"
where msedge >nul 2>nul && (start "" msedge --kiosk "%PAGE%" --edge-kiosk-type=fullscreen --no-first-run & exit /b)
start "" chrome --kiosk "%PAGE%"
