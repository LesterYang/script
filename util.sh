#!/bin/bash


# output device
redirect="/dev/console"

# color code
c_null="\e[0m"
c_Red="\e[31m"
c_Green="\e[32m"
c_Yellow="\e[33m"
c_Blue="\e[34m"
c_Purple="\e[35m"
c_Cyan="\e[36m"
c_LRed="\e[1;31m"
c_LGreen="\e[1;32m"
c_LYellow="\e[1;33m"
c_LBlue="\e[1;34m"
c_LPurple="\e[1;35m"
c_LCyan="\e[1;36m"


# main
_func_="main()"
arglist="$@"
dbg="0"

#################
# options
#################
usage()
{
    echo " Usage: $0 OPTION [PARAMTERS]"                                        1>&2
    echo " OPTION"                                                              1>&2
    echo "     -p, --prefix             set target prefix"                      1>&2
    echo "     -s, --source             set source path"                        1>&2
    echo "                              [defaul : current working directory]"   1>&2
    echo "     -d, --debug              more information"                       1>&2
    echo "     -h, --help               help"                                   1>&2
    exit 0
}

parse_options()
{
	local SHORT_OPTS="hds:p:"
	local LONG_OPTS="help,debug,prefix:,source:"
	local opt=`getopt -l "$LONG_OPTS" -o "$SHORT_OPTS" -- "$@"`

	eval set -- "$opt"

	while true
	do
		case "$1" in
		    -h|--help)     
		        usage
		        ;;
		    -d|--debug)     
		        redirect="/dev/console"
		        ;;
            -s|--source)
		        if [ -d "$2" ];then
		        	location=$2
				else
					log_stderr "[line $LINENO] no $2 directory, using default path"
				fi
		        shift
				;;
			-p|--prefix)
                output=$2$output
                shift
                ;;
		    --)     
		        break
		        ;;
		    *)      
		        log_exit "[line $LINENO] option error"
		        ;;
		esac
		shift
	done
}

#################
# log
#################

log_exit()
{
	local pattern="${c_Red}--- log[E] --- : $1 ${c_null}"
	echo -e "$pattern" > $redirect
    exit 0
}

log_err()
{
	local pattern="${c_LRed}-- log[E] -- : $1${c_null}"
	echo -e "$pattern" > $redirect
}

log_notify()
{
	local pattern="-- log[N] -- : $1"
	local color="$2"
	
	if [ -n "$color" ];then
	    pattern="${color}${pattern}${c_null}"
	fi
	
	echo -e "$pattern" > $redirect
}

log_info()
{
    if [ "$dbg" == "0" ];then
        return
    fi
	
	local pattern="-- log[I] -- : $1"
	local color="$2"
	
	if [ -n "$color" ];then
	    pattern="${color}${pattern}${c_null}"
	fi
	
	echo -e "$pattern" > $redirect
}



# example
cd `dirname $0`
parse_options $arglist
exit_info "[line ${LINENO}] error" "$c_LCyan"

