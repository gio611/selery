::
:: Copyright: 2017-2018 sel-project
:: License: MIT
::

@echo off

set compiler=dmd
set build=debug
set arch=
set config=default
set plugins=
set portable=

:loop
if "%1"=="" (
	goto build
) else if "%1" == "-h" (
	goto help
) else if "%1" == "--help" (
	goto help
) else if "%1" == "--dmd" (
	set compiler=dmd
) else if "%1" == "--ldc" (
	set compiler=ldc2
) else if "%1" == "-c" (
	set compiler=%2
	shift
) else if "%1" == "debug" (
	set build=debug
) else if "%1" == "release" (
	set build=release
) else if "%1" == "-a" (
	set arch=%2
	shift
) else if "%1" == "default" (
	set config=default
) else if "%1" == "classic" (
	set config=default
) else if "%1" == "hub" (
	set config=hub
) else if "%1" == "node" (
	set config=node
) else if "%1" == "--no-plugins" (
	set plugins=--no-plugins
) else if "%1" == "-np" (
	set plugins=--no-plugins
) else if "%1" == "--portable" (
	set portable=--portable
) else if "%1" == "--clean" (
	del dub.selections.json
	del builder\dub.selections.json
	del builder\init\dub.selections.json
)
shift
goto loop

:build
if "%arch%" == "" (
	if /I "%processor_architecture%" == "amd64" (
		set arch=x86_64
	) else if /I "%processor_architecture%" == "x86_64" (
		set arch=x86_64
	) else (
		set arch=x86
	)
)
if "%arch%" == "x86" (
	if "%compiler%" == "dmd" (
		set arch=x86_mscoff
	)
)
cd builder\init
dub run --compiler=%compiler% --build=%build% --arch=%arch% -- %config% %plugins% %portable%
if %errorlevel% neq 0 (
	cd ..\..
	exit /b %errorlevel%
)
cd ..
dub build --compiler=%compiler% --build=%build% --arch=%arch%
cd ..
goto :eof

:help
echo Usage: build.bat [-h] [--dmd^|--ldc^|-c COMPILER] [debug^|release] [-a ARCH] [default^|hub^|node] [-np] [--clean]
echo(
echo Optional aguments:
echo   -h, --help            Show this message and exit
echo   --dmd, --ldc          Compile using the DMD or LDC compiler
echo   -c COMPILER           Compile using the spcified compiler
echo   debug, release        Compile using DUB's debug or release mode
echo   -a ARCH               Specify the architecture to build for
echo   default, hub, node    Compile the specified configuration for Selery
echo   -np, --no-plugins     Compile without plugins
echo   --clean               Remove dub.selections.json files
