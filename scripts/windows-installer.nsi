; Windows installer for the game, built on macOS with makensis (Homebrew).
; scripts/release.sh calls it once per architecture:
;
;   makensis -DTITLE=... -DPKG=... -DVERSION=... -DARCH=64 \
;            -DSRCDIR=... -DICON=... -DOUTFILE=... scripts/windows-installer.nsi
;
; The install is per-user, into %LOCALAPPDATA%\Programs: no admin rights and
; no UAC prompt, which matters because the exe is not signed yet and an
; elevation prompt for an unknown publisher is where people give up.

Unicode true

!include "MUI2.nsh"
!include "FileFunc.nsh"

!ifndef TITLE
  !error "TITLE is required"
!endif
!ifndef PKG
  !error "PKG is required"
!endif
!ifndef VERSION
  !error "VERSION is required"
!endif
!ifndef SRCDIR
  !error "SRCDIR is required (the folder holding ${PKG}.exe and the DLLs)"
!endif
!ifndef OUTFILE
  !error "OUTFILE is required"
!endif
!ifndef ARCH
  !define ARCH "64"
!endif

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PKG}"

Name "${TITLE}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${TITLE}"
InstallDirRegKey HKCU "Software\${PKG}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
ShowInstDetails hide
ShowUnInstDetails hide

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${TITLE}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${TITLE} installer (${ARCH}-bit)"
VIAddVersionKey "LegalCopyright" ""

!ifdef ICON
  !define MUI_ICON "${ICON}"
  !define MUI_UNICON "${ICON}"
!endif

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PKG}.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open ${TITLE}"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Section "Install"
  SetOutPath "$INSTDIR"
  File /r "${SRCDIR}\*.*"

  CreateShortCut "$SMPROGRAMS\${TITLE}.lnk" "$INSTDIR\${PKG}.exe"
  CreateShortCut "$DESKTOP\${TITLE}.lnk" "$INSTDIR\${PKG}.exe"

  WriteUninstaller "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "Software\${PKG}" "InstallDir" "$INSTDIR"

  ; Makes it appear in Settings > Apps, so it can be removed the usual way.
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${TITLE}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${PKG}.exe"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\${TITLE}.lnk"
  Delete "$DESKTOP\${TITLE}.lnk"

  ; Only ever recurse into a directory this installer wrote, which the
  ; uninstaller sitting in it is the evidence for.
  IfFileExists "$INSTDIR\uninstall.exe" 0 +3
    Delete "$INSTDIR\uninstall.exe"
    RMDir /r "$INSTDIR"

  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "Software\${PKG}"
SectionEnd
