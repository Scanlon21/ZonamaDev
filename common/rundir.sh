#!/bin/bash
#
# rundir.sh - Run all scripts in a directory based on script's name (i.e. myname.d/*)
#
# Typical usage is a symlink to this script or a script that sets ME= and source's this script
#
# Author: Lord Kator <lordkator@swgemu.com>
#
# Created: Sat Dec 26 15:39:04 EST 2015
#

if [ -z "$ME" ]; then
    pushd $(dirname ${BASH_SOURCE[0]}) > /dev/null
    export ME=$(pwd -P)'/'$(basename ${BASH_SOURCE[0]})
    popd > /dev/null

    if [ ! -d $ME'.d' ]; then
	echo "Usage: $0 - Run files in directory ${0}.d/"
	exit 0
    fi
fi

TAG=$(basename $ME)
RUN_STEP="init"
HAVEX=false

if xset q > /dev/null 2>&1; then
    HAVEX=true
fi

# Run output through some stuff to make display more useful and capture errors
if [ "X$CHILD_STATUS" = "X" ]; then
    export CHILD_STATUS="/tmp/${TAG}-status-$$"
    echo 253 > $CHILD_STATUS
    ts=$(type -P ts)
    if [ -n "$ts" ]; then
	$ME -- $* 2>&1 | $ts -s | logger -i -t ${TAG} -s 2>&1
    else
	$ME -- $* 2>&1 | logger -i -t ${TAG} -s 2>&1
    fi
    st=$(<$CHILD_STATUS)
    if [ $st -eq 0 ]; then
	logger -i -t ${TAG} -s "** $ME SUCCESS **"
    else
	logger -i -t ${TAG} -s "** $ME FAILED! STATUS=$st ** ABORT **"
    fi
    rm -f $CHILD_STATUS
    exit $st
fi

## Assets Directory
ASSETS_DIR=$(dirname $ME)'/../assets'

# Trap various failures
TMPFILES=()

trap 'st=$?;echo $st > '${CHILD_STATUS}';rm -f ${TMPFILES[@]};msg "UNEXPECTED EXIT=$st"' 0
trap 'msg "UNEXPECTED SIGNAL SIGHUP!";echo 21 > $CHILD_STATUS' HUP
trap 'msg "UNEXPECTED SIGNAL SIGINT!";echo 22 > $CHILD_STATUS' INT
trap 'msg "UNEXPECTED SIGNAL SIGTERM!";echo 23 > $CHILD_STATUS' TERM

msg() {
    local hd="##"$(echo "$1"|sed 's/./#/g')"##"
    echo -e "$hd\n# $1 #\n$hd"
}

notice() {
    if $HAVEX; then
	notify-send --icon=${ASSETS_DIR}/swgemu_icon.png --expire-time=0 "$1" "$2"
	echo "USER NOTICE: $1 - $2"
    else
	echo "**NOTICE** $1: $2"
    fi
}

delete_on_exit() {
    TMPFILES+=($1)
}

error() {
    err_msg=$1
    err_code=251
    if [ "X$2" != "X" ]; then
	err_code=$2
    fi

    msg "ERROR WHILE PROCESSING $RUN_STEP: $err_msg ($err_code)"

    if $HAVEX; then
	zenity --error --title="${TAG} FAILED" --text="The ${TAG} process failed at step ${RUN_STEP} with error:\n\n${err_msg} (${err_code})" < /dev/null > /dev/null 2>&1 &
    fi

    exit $err_code
}

command_window() {
    # TODO do we need to detect other terminals in case this one's not installed?
    xfce4-terminal --maximize --icon=${ASSETS_DIR}/swgemu_icon.png --hide-menubar --hide-toolbar --title="$1" --command="$2"
}

yorn() {
  if $HAVEX; then
       zenity --question --text="$@"
       return $?
  else
      if tty -s; then
	  echo -n -e "$@ Y\b" > /dev/tty
	  read yorn < /dev/tty
	  case $yorn in
	    [Nn]* ) return 1;;
	  esac
      fi
  fi

  return 0
}

# We at least made it this far!
echo 252 > $CHILD_STATUS

###################
## CHILD PROCESS ##
###################

if [ "X$1" = "X--" ]; then
    shift
fi

msg "START $ME $* git-tag: "$(cd $(dirname $ME);git describe --always)

# Check for FORCE flag
FORCE=false

if [ "X$1" = "X-f" -o "X$1" = "X--force" ]; then
    FORCE=true
    shift
    echo "**NOTICE** User requested we force the run."
fi

## Run LOCK
LOCKTMP=$(mktemp /tmp/${TAG}.lock-XXXXXX)
LOCKFILE=/tmp/${TAG}.lock

delete_on_exit $LOCKTMP

echo "$$ "$(date +%s) > ${LOCKTMP}

if ln ${LOCKTMP} ${LOCKFILE}; then
    :
else
    read pid tm_lock < ${LOCKFILE}
    tm_now=$(date +%s)

    let "tm_delta=${tm_now} - ${tm_lock}"

    if kill -0 $pid; then
	msg "PID $pid HAS HAD LOCK FOR ${tm_delta} SECOND(S), EXITING"
	exit 0
    else
	msg "Stealing lock from PID $pid which has gone away, locked ${tm_delta} second(s) ago"
	if ln -f ${LOCKTMP} ${LOCKFILE}; then
	    read pid tm_lock < ${LOCKFILE}
	    if [ "$pid" -eq "$$" ]; then
		msg "STOLE LOCK, PROCEEDING"
	    else
		msg "Can't steal lock, somone got in before us!? pid=${pid}"
		exit 2
	    fi
	else
	    msg "Failed to steal lock, **ABORT**"
	    exit 1
	fi
    fi
fi

delete_on_exit $LOCKFILE

run_dir=$(echo ${ME}'.d')

cd $run_dir

steps=$(echo ${run_dir}/*)

# Did the user call us with specific steps?
if [ -n "$1" ]; then
    msg "Custom steps: $@"
    # 00* always run
    steps=$(echo ${run_dir}/00*)

    for i in $@
    do
	fn="${run_dir}/$i"
	if [ -f $fn ]; then
	    steps="${steps} ${fn}"
	else
	    msg "Invalid step: $i file: ${fn} not found"
	fi
    done

    # 99* always run
    steps="$steps $(echo ${run_dir}/99*)"
else
    echo "Steps: "$(echo "$steps" | sed "s!${run_dir}/!!g")
fi

for step in $steps
do
    RUN_STEP=$(basename $step)
    msg "Run $step md5:"$(md5sum $step)
    source $step
done

msg "$ME COMPLETE AFTER $SECONDS SECOND(S)"

#############
## Success ##
#############
trap - 0
echo 0 > $CHILD_STATUS
rm -f ${TMPFILES[@]}
exit 0

# vi:sw=4 ft=sh
