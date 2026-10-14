@ECHO OFF
@REM ==================================================================
@REM REMOTE OPS - GUI BASLATICI
@REM 1) C:\Temp\YD_RemoteOps.App\Logs ve PulledLogs klasorlerini olusturur
@REM 2) :MAIN bolumunu calistirir; tum ciktisi Logs\YD_ReoP_[bat adi]_[domain]_[kullanici].log
@REM    dosyasina eklenir
@REM 3) :MAIN, isletim sistemi mimarisine uygun 64 bit Windows PowerShell 5.1 ile
@REM    RemoteOps.App.ps1 (WPF arayuz) dosyasini -ExecutionPolicy Bypass ile baslatir
@REM 4) PowerShell'in exit code'u bu bat'in exit code'u olarak dondurulur
@REM ==================================================================
@SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION
@SET SEE_MASK_NOZONECHECKS=1
@SET EXITCODE=0
@PROMPT $D$S$T$_
@SET host=%COMPUTERNAME%
@SET host2=%host:~-3%
@SET host3=%host:~0,5%
@REM Calisma klasorleri yoksa olustur; olusturulamazsa (yetki yok) 1 ile cik.
@IF NOT EXIST "C:\Temp\YD_RemoteOps.App\Logs" MKDIR "C:\Temp\YD_RemoteOps.App\Logs"
@IF NOT EXIST "C:\Temp\YD_RemoteOps.App\Logs" EXIT /B 1
@IF NOT EXIST "C:\Temp\YD_RemoteOps.App\PulledLogs" MKDIR "C:\Temp\YD_RemoteOps.App\PulledLogs"
@IF NOT EXIST "C:\Temp\YD_RemoteOps.App\PulledLogs" EXIT /B 1
@REM :MAIN'i calistir ve tum ciktisini launcher log dosyasina ekle.
@CALL :MAIN >> "C:\Temp\YD_RemoteOps.App\Logs\YD_ReoP_%~n0_%UserDomain%_%UserName%.log" 2>&1
@PROMPT
@ECHO EXITCODE=%EXITCODE%
@EXIT /B %EXITCODE%

:MAIN
@ECHO =============================================================
@ECHO STARTING EXECUTION
@ECHO CURRENTDIR="%~dp0"


@REM Calisma dizinini bu bat'in klasoru yap.
PUSHD "%~dp0"

@REM 32 bit bir cmd icinde calisiyorsak (WOW64) SYSNATIVE ile 64 bit PowerShell secilir;
@REM boylece GUI her zaman isletim sisteminin yerel mimarisinde calisir.
IF %PROCESSOR_ARCHITECTURE% == x86 (
	IF NOT DEFINED PROCESSOR_ARCHITEW6432 (
		SET _WSCRIPT="%SYSTEMROOT%\SYSTEM32\WindowsPowerShell\v1.0\Powershell.exe"
		SET OS_ARCHITECTURE=i386
	) ELSE (
		SET _WSCRIPT="%SYSTEMROOT%\SYSNATIVE\WindowsPowerShell\v1.0\Powershell.exe"
		SET OS_ARCHITECTURE=x64
	)
) ELSE (
	SET _WSCRIPT="%SYSTEMROOT%\SYSTEM32\WindowsPowerShell\v1.0\Powershell.exe"
	SET OS_ARCHITECTURE=x64
)


@REM GUI'yi baslat. Pencere kapanana kadar bu satirda beklenir.
CALL %_WSCRIPT% -ExecutionPolicy ByPass -NoLogo -File "%~dp0RemoteOps.App.ps1"
@ECHO %DATE% %TIME% Running Cmd:[%_WSCRIPT% -ExecutionPolicy ByPass -NoLogo -File "%~dp0RemoteOps.App.ps1"]



::FINISHED
@ECHO %DATE% %TIME% EXITCODE=!ERRORLEVEL!
@SET EXITCODE=!ERRORLEVEL!
@ECHO %DATE% %TIME% FINISHED EXECUTION
@ECHO =============================================================
@EXIT /B
