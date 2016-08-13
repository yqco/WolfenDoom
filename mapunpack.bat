@ECHO OFF
setlocal enabledelayedexpansion

set GDCC_PATH=tools\GDCC
set ARWAD=%GDCC_PATH%\gdcc-ar-wad.exe
set MAP_DIR=maps
set UNPACK_DIR=%MAP_DIR%\unpacked



REM
REM                          TODO - Fix :pack. We need to make sure the wad
REM                                 is newer than ALL lumps, not just the
REM                                 timestamp.
REM
REM
REM
REM






REM Prompt the user for a task.
REM
:menu
    echo [1] Rebuild WADs (after git pull)
    echo [2] Explode WADs (before git push)
    echo [X] Exit
    set /p useroption="> "
    echo.

    if "!useroption!" equ "1" goto pack
    if "!useroption!" equ "2" goto unpack
    if "!useroption!" equ "x" goto :EOF
    goto menu



REM Package map lumps into wad files
REM
REM Lumps are written to a temporary wad file before overwriting the original
REM wad. Parses the <wadname>.lumps.txt created during unpack to determine the
REM lumps and their order within the new wad.
REM
REM Also creates a timestamp file in the output directory which is used to
REM store the date of the pack. This allows the batch script to check if the
REM lumps have been updated since it was packed.
REM
:pack
    for %%f in (!MAP_DIR!\*.lumps.txt) do (
        set lumplogpath=%%f
        set lumplog=%%~nf

        REM Remove the last 6 characters to strip ".lumps" extension
        set wadname=!lumplog:~0,-6!
        set wadpath=!MAP_DIR!\!wadname!.wad
        set tempwadpath=!wadpath!.repacked
        if exist !tempwadpath! (
            rm !tempwadpath!
        )

        REM Get map name from first lump (might differ from wad name)
        set mapname=
        for /f %%L in (!lumplogpath!) do (
            set lumpname=%%L
            if "!mapname!" == "" (
                REM Remove the trailing slash
                set mapname=!lumpname:~0,-1!
            )
        )

        set outputdir=!UNPACK_DIR!\!mapname!
        set timestamppath=!outputdir!\timestamp

        REM Find the newest lump; iterate lump names from oldest to newest.
        set newest=
        for /f %%L in ('dir /b/a-d/od/t:w !outputdir!') do (
            set newest=%%L
        )

        REM Timestamp is newest file, no need to repack
        if "!newest!" equ "timestamp" (
            echo Skipped !wadname!

        ) else (
            REM Parse lumplog for list and order of wad lumps
            set lumps=
            for /f %%l in (!lumplogpath!) do (
                set lumppath=%%l
                set lumpname=%%~nl
                if "!lumpname!" neq "" (
                    set lumps=!lumps! file:!lumpname!=!UNPACK_DIR!\!lumppath!
                )
            )

            REM Write lumps to a temporary wad. (Safe way of overwriting.)
            if "!lumps!" neq "" (
                echo Packing !wadname!.wad ...

                %ARWAD% -o!tempwadpath! !lumps!

                if not exist !tempwadpath! (
                    echo Error: Failed to write lumps to temporary wad: !tempwadpath!

                ) else (
                    REM Replace old wad with new one
                    move /y !tempwadpath! !wadpath! >NUL 2>NUL

                    REM Could not overwrite old WAD, file might be in-use.
                    if exist !tempwadpath! (
                        echo Error: Could not overwrite !wadname!.wad. Is it open in gzdoombuilder?
                        set /p promptrepeat="->       Try again? (y/[n]): "
                        if "!promptrepeat!" equ "y" (
                            move /y !tempwadpath! !wadpath! >NUL 2>NUL

                        ) else (
                            echo Skipped !wadname!
                        )
                    )
                    
                    if exist !tempwadpath! (
                        REM Create a blank file to store the pack timestamp
                        copy /y NUL !timestamppath! >NUL
                    )
                )
            )
        )
    )
    echo Done
    echo.
goto :EOF




REM Unpack map lumps
REM
REM Lumps are exported into a subfolder of %UNPACK_DIR% with the same name as
REM the map (not necessarily the name of the wad). A file containing all the
REM wad's lumps is created next to the wad with the name: <wadname>.lumps.txt
REM
REM Also creates a timestamp file in the output directory which is used to
REM store the date of the unpack. This allows the batch script to check if the
REM wad has been updated since it was unpacked.
REM
:unpack
    if not exist !UNPACK_DIR! (
        mkdir !UNPACK_DIR!
    )

    REM Whether to always unpack and overwrite files
    set alwaysunpack=0
    for %%w in (!MAP_DIR!\*.wad) do (
        set wadpath=%%w
        set wadname=%%~nw
        set lumplog=!wadname!.lumps.txt
        set lumplogpath=!MAP_DIR!\!lumplog!

        REM Generate a list of the map's lumps (used to get map name)
        %ARWAD% --list=!lumplogpath! wad:!wadpath!

        REM Get map name from first lump (might differ from wad name)
        set mapname=
        for /f %%L in (!lumplogpath!) do (
            set lumpname=%%L
            if "!mapname!" == "" (
                REM Remove the trailing slash
                set mapname=!lumpname:~0,-1!
            )
        )

        REM Ensure the output folder exists
        set outputdir=!UNPACK_DIR!\!mapname!
        if not exist !outputdir! (
            mkdir !outputdir!
        )
        set timestamppath=!outputdir!\timestamp

        REM Check if any of the lumps have been modified
        set unpack=1
        if exist !timestamppath! (

            REM Iterate over lump names from oldest to newest, build a string
            REM of all the lumps that are newer than the timestamp file
            set seentimestamp=0
            set modified=
            for /f %%L in ('dir /b/a-d/od/t:w !outputdir!') do (
                if !seentimestamp! == 1 (
                    if "!modified!" == "" (
                        set modified= %%L
                    ) else (
                        set modified=!modified!, %%L
                    )
                ) else if "%%L" == "timestamp" (
                    set seentimestamp=1
                )
            )

            REM Determine whether the wad should be unpacked or not
            if "!modified!" == "" (
                REM Temporarily move the timestamp file into the map directory
                REM to compare if the wad is newer
                set temptimestamppath=!MAP_DIR!\timestamp
                move /y !timestamppath! !temptimestamppath! >NUL 2>NUL

                if not exist !temptimestamppath! (
                    echo Error: Could not move !wadname!'s timestamp file into the map directory
                    set unpack=0

                ) else (
                    REM Iterate over wads and timestamp from oldest to newest
                    set looking=1
                    set oldest=
                    for /f %%f in ('dir /b/a-d/od/t:w !MAP_DIR!') do (
                        if !looking! == 1 (
                            REM Find which is the oldest: the timestamp, or the wad
                            if "%%f" == "timestamp" (
                                set oldest=%%f
                                set looking=0

                            ) else if "%%f" == "!wadname!.wad" (
                                set oldest=%%f
                                set looking=0
                            )
                        )
                    )

                    REM Move the timestamp back to its original directory
                    move /y !temptimestamppath! !timestamppath! >NUL

                    REM Wad is older than timestamp, unpacked files are up-to-date
                    if "!oldest!" neq "timestamp" (
                        set unpack=0
                    )
                )

            ) else if !alwaysunpack! == 0 (
                REM Prompt user to overwrite newer lumps
                echo.
                echo Warning: Unpacking !wadname!.wad will overwrite newer lump(s^^^):!modified!
                set /p promptoverwrite="->       Unpack !wadname!.wad anyway? (y/[n]/a): "
                if "!promptoverwrite!" equ "a" (
                    set unpack=1
                    set alwaysunpack=1
                ) else if "!promptoverwrite!" neq "y" (
                    set unpack=0
                )

            ) else (
                set unpack=!alwaysunpack!
            )
        )

        REM Unpack wad file
        if !unpack! == 1 (
            echo Unpacking !wadname!.wad ...
            %ARWAD% --extract -o!UNPACK_DIR! wad:!wadpath!

            REM Create a blank file to store the unpack timestamp
            copy /y NUL !timestamppath! >NUL
        ) else (
            echo Skipped !wadname!
        )
    )
    echo Done
    echo.
goto :EOF

