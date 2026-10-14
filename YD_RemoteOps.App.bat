@ECHO OFF
@REM ==================================================================
@REM YD RemoteOps App - ANA BASLATICI (kullanicinin cift tikladigi dosya)
@REM Tek isi: RemoteOps.App\RemoteOps.App.bat dosyasini cagirmak ve onun
@REM exit code'unu aynen geri dondurmek. Akis devami icin:
@REM   RemoteOps.App\RemoteOps.App.bat , ardindan RemoteOps.App.ps1 (GUI)
@REM Ayrintili diyagram: docs\CALISMA_MANTIGI.md
@REM ==================================================================
CALL "%~dp0RemoteOps.App\RemoteOps.App.bat"
EXIT /B %ERRORLEVEL%