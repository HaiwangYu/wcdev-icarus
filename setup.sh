source  /cvmfs/icarus.opensciencegrid.org/products/icarus/setup_icarus.sh
# setup icaruscode v10_06_00_06p04 -q e26:prof
# setup icaruscode v10_15_00_02 -q e26:prof
setup icaruscode v10_20_03 -q e26:prof

# source /exp/sbnd/app/users/yuhw/larsoft/v10_14_02/localProducts_larsoft_v10_14_02_02_e26_prof/setup
# mrbslp
path-prepend /exp/sbnd/app/users/yuhw/opt CMAKE_PREFIX_PATH

path-remove ()
{
    local IFS=':';
    local NEWPATH;
    local DIR;
    local PATHVARIABLE=${2:-PATH};
    for DIR in ${!PATHVARIABLE};
    do
        if [ "$DIR" != "$1" ]; then
            NEWPATH=${NEWPATH:+$NEWPATH:}$DIR;
        fi;
    done;
    export $PATHVARIABLE="$NEWPATH"
}

path-prepend ()
{
    path-remove "$1" "$2";
    local PATHVARIABLE="${2:-PATH}";
    export $PATHVARIABLE="$1${!PATHVARIABLE:+:${!PATHVARIABLE}}"
}

path-append ()
{
    path-remove "$1" "$2";
    local PATHVARIABLE="${2:-PATH}";
    export $PATHVARIABLE="${!PATHVARIABLE:+${!PATHVARIABLE}:}$1"
}

path-prepend /exp/sbnd/app/users/yuhw/opt/lib/ LD_LIBRARY_PATH
path-prepend /exp/sbnd/app/users/yuhw/opt/bin/ PATH

# path-prepend /exp/sbnd/app/users/yuhw/wire-cell-data WIRECELL_PATH
path-prepend /exp/sbnd/app/users/yuhw/wire-cell-toolkit/cfg WIRECELL_PATH

rs
export PS1=(app)$PS1

source /exp/sbnd/app/users/yuhw/wire-cell-python/venv/bin/activate