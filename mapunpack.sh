#!/bin/bash

gdccpath="tools/GDCC"
arwad="$gdccpath/gdcc-ar-wad"
mapsdir="maps"
unpackdir="$mapsdir/unpacked"

function strip_path_and_ext {
    local output_var_=$1    # Name of variable to store output in
    local input_path_=$2    # Path to reduce to a file name without an extension

    local filename_=$(basename "$input_path_")
    eval $output_var_=\${filename_%%.*}
}

function rebuild_wads {
    # Rebuild map wads from lumps
    for lumplogpath in $mapsdir/*.lumps.txt; do
        strip_path_and_ext wadname "${lumplogpath}"
        local wadpath=$mapsdir/$wadname.wad
        local tempwadpath=$wadpath.repacked

        # Get the map name and build a string of lumps in order of their appearance
        unset lumps
        unset mapname
        while read lumppath; do
            lumpname=${lumppath#*/}
            if test -n "$lumpname"; then
                lumps="$lumps file:$lumpname=$unpackdir/$lumppath"
            fi

            if test -z "$mapname"; then
                mapname=${lumppath%/*}
            fi
        done <$lumplogpath

        # Find the newest file in the output directory
        local outputpath=$unpackdir/$mapname
        local newest=`ls -t $outputpath/* | head -1`

        # No need to repack if the newest file is the timestamp
        if [ "$newest" == "$outputpath/timestamp" ]; then
            echo "Skipped $wadname"

        else
            # Remove the old temporary wad if it exists
            if test -f "$tempwadpath"; then
                rm $tempwadpath
            fi

            # Write to temporary wad file
            echo "Building $wadname ..."
            $arwad -o$tempwadpath $lumps
            if test ! -f "$tempwadpath"; then
                echo "Error: Failed to write to $tempwadpath"
                echo "Skipped $wadname"

            else
                # Replace old wad with temporary wad
                mv -f $tempwadpath $wadpath 2>/dev/null

                # Move failed, prompt user to try again
                if test -f "$tempwadpath"; then
                    echo
                    local tryagain=1
                    while [ $tryagain == 1 ]; do
                        echo "Error: Failed to overwrite $wadname.wad. Is the file open in gzdoombuilder?"
                        read -p "Try again? (y/n): " -r

                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            mv -f $tempwadpath $wadpath 2>/dev/null
                            if test ! -f "$tempwadpath"; then
                                echo "Overwrote $wadname.wad"
                                tryagain=0
                            fi

                        elif [[ $REPLY =~ ^[Nn]$ ]]; then
                            echo "Skipped $wadname"
                            tryagain=0

                        fi
                    done
                fi

                if test ! -f "$tempwadpath"; then
                    # Recreate timestamp file with current time
                    > $outputpath/timestamp
                fi
            fi
        fi
    done
    echo "Done"
}

function explode_wads {
    local alwaysunpack=0

    # Explode wads into individual lumps
    for wadpath in $mapsdir/*.wad; do
        strip_path_and_ext wadname "${wadpath}"
        local wadname=$wadname

        # Generate the lump list file
        local lumplogpath=$mapsdir/$wadname.lumps.txt
        $arwad --list=$lumplogpath wad:$wadpath

        # Get the map name from the lump file (remove the slash)
        local mapname=`cat $lumplogpath | head -1`
        mapname=${mapname%/*}

        # Check the timestamp for whether the unpack is even necessary
        local unpack=1
        local timestamppath=$unpackdir/$mapname/timestamp
        if test -f "$timestamppath"; then

            # Build a string of lumps newer than the timestamp
            unset newer
            while read lumppath; do
                local lumpname=${lumppath#*/}
                if test -n "$lumpname"; then
                    if [ "$unpackdir/$lumppath" -nt "$timestamppath" ]; then
                        if test -z "$newer"; then
                            newer="$lumpname"
                        else
                            newer="$newer, $lumpname"
                        fi
                    fi
                fi
            done <$lumplogpath

            # Determine whether the wad should be unpacked based on newer lumps
            if test -z "$newer"; then
                # No lumps are newer, only unpack if wad is newer than timestamp
                if [ "$timestamppath" -nt "$wadpath" ]; then
                    unpack=0
                fi

            elif [ $alwaysunpack == 0 ]; then
                # Prompt the user to unpack anyway
                local tryagain=1
                while [ $tryagain == 1 ]; do
                    echo
                    echo "Warning: Unpacking $wadname.wad will overwrite newer lump(s): $newer"
                    read -p "         Unpack $wadname.wad anyways? (y/n/Y): " -r

                    tryagain=0
                    if [[ $REPLY == "Y" ]]; then
                        alwaysunpack=1

                    elif [[ $REPLY == "y" ]]; then
                        :

                    elif [[ $REPLY =~ ^[Nn]$ ]]; then
                        unpack=0

                    else
                        tryagain=1

                    fi
                done
            fi
        fi

        # Unpack the wad into a subdirectory
        if [ $unpack == 1 ]; then
            echo "Unpacking $wadname.wad ..."
            $arwad --extract -o$unpackdir wad:$wadpath

            # Create the timestamp file for unpack time
            > $timestamppath

        else
            echo "Skipped $wadname"
        fi
    done
    echo "Done"
}

if [ "$1" == "rebuild" ]; then
    rebuild_wads

elif [ "$1" == "explode" ]; then
    explode_wads

else
    echo "Usage: $0 rebuild|explode"
    echo
    echo "Where:"
    echo "    rebuild: Regnerate wad files. Use after a 'git pull'"
    echo "    explode: Unpack map lumps. Use before a 'git push'"

fi
