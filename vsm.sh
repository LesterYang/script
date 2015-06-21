#!/bin/bash
############################################################################
# Name
#   vsm.sh : virtual sound manager
#
# Description
#   This tool is used to control audio pcm device volume/mute, and switch  
#   external audio sources from the shell
#
# Options
#   -h,--help    Show usage     
#
# Error code:
#   0    Success
#   1    Required parameter is missing
#   2    Parameter error
#   3    Double set device
#   4    Record is running
#   5    Record is already stopped
#   6    Can't find record pid
#   7    Can't find usb audio card
############################################################################

#################
# Configuration
#################
VERSION=1.6

asound_conf="/etc/asound.conf"
vsm_dirct="/tmp/vsm"

usb_capture_status="$vsm_dirct/usb_capture_status"
usb_capture_pid="$vsm_dirct/usb_capture_pid"
usb_capture_playback="qsisw6"
usb_auto_set_capture="line"

HDMI_capture_status="$vsm_dirct/HDMI_capture_status"
HDMI_capture_pid="$vsm_dirct/HDMI_capture_pid"
HDMI_capture_playback="qsisw7"

android_capture_status="$vsm_dirct/android_capture_status"
android_capture_pid="$vsm_dirct/android_capture_pid"
android_capture_playback="qsisw8"

NEGATIVE_ONE=255

vsm_numid_conf=""

#############
# Function
#############
usage()
{
    echo " Virtual Sound Manager"                                               1>&2
    echo " Usage: $0 OPTION [PARAMTERS]"                                        1>&2
    echo " OPTION"                                                              1>&2
    echo "     -c, --connect            connect usb audio source(mic or line)"  1>&2
    echo "     -d, --disconnect         disconnect usb audio source"            1>&2
    echo "     -C, --capture DEV        capture device, defult [usb]"           1>&2
    echo "                              DEV : usb, HDMI, android, ..."          1>&2
    echo "         --init               initialize capture device"              1>&2
    echo "     -D, --device  DEV        pcm device"                             1>&2
    echo "                              DEV : qsisw0, qsisw1, ..."              1>&2
    echo "         --debug              debug mode"                             1>&2
    echo "     -S, --subdev  DEV        sub pcm device"                         1>&2
    echo "                              DEV : sub0, sub1, ..."                  1>&2
    echo "         --softvol DEV        softvol pcm name"                       1>&2
    echo "     -h, --help               help"                                   1>&2
    echo "     -m, --mute    VAL        set mute or not (VAL: 0, 1)"            1>&2
    echo "     -s, --source  DEV        set usb audio source (DEV: mic, line)"  1>&2
    echo "     -v, --volume  VAL        set output volume (VAL: 0~100)"         1>&2
    echo "         --version            show version"                           1>&2
    echo "ENVIRONMENT VARIABLE"                                                 1>&2
    echo "     VS_DEBUG                 set 1 for debug"                        1>&2
}

exit_info()
{
    echo "== vms error == $_func_,$@" 1>&2
    exit $ret
}

log()
{
    if [ "$dbg" == "1" ];then
        echo -e "--  vms log  -- $_func_ : $@" 1>&2
    fi
}

get_audio_card()
{
    # $1:keyword
    local card=$(cat /proc/asound/cards | grep "$1" | grep '\[' | head -n1 |awk '{print $1}')
    
    if [ -z $card ];then
        card="$NEGATIVE_ONE"
        log "search cards (keyword:$1)"
        log "card list ->\n`cat /proc/asound/cards`"    
    fi

    return $card
}

get_audio_numid()
{
    # $1:card, $2:name
    local numid=$(amixer -c $1 controls | grep "$2" | head -n1 | awk -F ',' '{print substr($1, 7, length($1))}')

    if [ -z $numid ];then
        numid="$NEGATIVE_ONE"
        log "go to get numid (name:$2)"  
        log "amixer controls ->\n`amixer -c $1 controls`"  
    fi

    return $numid
}

get_usb_source_item()
{
    # $1:card, $2:id, $3:keyword
    local item=$(amixer -c $1 cget numid=$2 | grep "$3" | head -n1 |awk -F '#' '{print substr($2, 0, 1)}')

    if [ -z $item ];then
        item="$NEGATIVE_ONE"
        log "go to get usb source(keyword:$3)"
        log "amixer cget numid $2 info ->\n`amixer -c $1 cget numid=$2`" 
    fi

    return $item
}

start_record()
{
    local card=""
    local param=""

    echo "start to record ..."

    case "$capture_dev" in
        usb)    
            get_audio_card USB-Audio
            card=$?
            ;;
        HDMI)  
            get_audio_card HDMI
            card=$?
	        param="-f dat"
            ;;
        android)  
            get_audio_card Android
            card=$?
	        param="-f cd"
            ;;
        *)      
            ret="2"
            exit_info "$LINENO : no such capture source"
            ;;
    esac

    if [ "$card" == "$NEGATIVE_ONE" ];then
        ret="7"
        exit_info "$LINENO : no $capture_dev audio device"
    fi

    echo "1" > $capture_status
    arecord $param -D"plughw:$card,0" | aplay -D"$capture_playback"

    if [ "$?" != 0 ];then
        echo "0" > $capture_status
        sync 
    fi 
}

stop_record()
{
    _func_="stop_record()"

    local r_pid=`cat $capture_pid`	
    local ps_info="/tmp/vsm/tmp_ps_info"
    
    if [ "r_pid" == "0" ];then
        ret="6"
        exit_info "$LINENO : no record pid"
    fi
    
    ps l | grep $r_pid > $ps_info

    echo "stop recording ..."	
    while IFS=' ' read -r -a line
    do
        if [ "${line[3]}" == "$r_pid" ];then
            echo "kill ${line[9]} pid : ${line[2]}"
            kill ${line[2]}
        fi
    done  < $ps_info

    kill $r_pid
    rm $ps_info
    echo "0" > $capture_status
    sync
}

set_capture_usb_source()
{
    _func_="set_capture_usb_source()"
    local name=""

    case "$capture_src_item" in
        mic)    name="Mic"      ;;
        line)   name="Line"     ;;
        mixer)  name="Mixer"    ;;
        *)      ret="2";        exit_info "$LINENO : no such capture source";;
    esac

    get_audio_card USB-Audio
    local card=$?

    if [ "$card" == "$NEGATIVE_ONE" ];then
        ret="7"
        exit_info "$LINENO : no usb audio card"
    fi

    get_audio_numid "$card" "Capture Source"
    local numid=$?

    if [ "$numid" == "$NEGATIVE_ONE" ];then
        exit_info "$LINENO : there is only one capture source"
    fi

    get_usb_source_item $card $numid $name
    local item=$?

    if [ "$item" == "$NEGATIVE_ONE" ];then
        ret="2"
        exit_info "$LINENO : keyword name, please notice author!!"
    fi

    amixer -c $card cset numid=$numid $item $redirect
}

set_audio_volume()
{
    _func_="set_audio_volume()"

    if [ -z $pcm_dev ];then
        ret="1"
        exit_info "$LINENO : no device, using option -D or --device"
    fi

    if [ -z $pcm_sub_dev ];then
        # default front
        pcm_sub_dev="sub0"
    fi

    local num=$(echo $pcm_dev | tr -d "qsisw")
    
    if [ -z $(echo $pcm_dev | grep qsisw) ] ;then
        ret="2"
        exit_info "$LINENO : device must be qsiswX"
    fi
	
    test -z `echo $num | tr -d "[0-9]"` || exit_info "$LINENO : device qsiswX, X must is numeric"
	
    local name=""

    case "$pcm_sub_dev" in
        sub0)  name="sw${num}_sub0"  ;;
        sub1)  name="sw${num}_sub1"  ;;
        sub2)  name="sw${num}_sub2"  ;;
        sub3)  name="sw${num}_sub3"  ;;
        *)     ret="2";             exit_info "$LINENO : no such subdev name";;
    esac

    amixer -c $master_card sset $name ${vol}% $redirect
}

set_softvol()
{
    amixer -c $master_card sset $softvol_dev ${vol}% $redirect
}

set_audio_mute()
{
    _func_="set_mute()"
	
    if [ -z "$pcm_dev" ];then
        ret="1"
        exit_info "$LINENO : no device, using option -D"
    fi

    if [ -z $(echo $pcm_dev | grep qsisw) ];then
        ret="2"
        exit_info "$LINENO : mute only for qsiswX"
    fi

    pcm_dev=$(echo $pcm_dev | sed 's/qsisw/qsidmix/g')

    if [ "$mute" == "0" ];then
        amixer -c $master_card sset $pcm_dev 100% $redirect
    else
        amixer -c $master_card sset $pcm_dev 0% $redirect
    fi
}

set_capture_param()
{
    if [ -z $capture_dev ];then
        #ret="1"
        #exit_info "$LINENO : no capture device, using option -C or --capture"

        # default usb
        capture_dev="usb"
    fi

    case "$capture_dev" in
        usb)
            capture_pid=$usb_capture_pid
            capture_status=$usb_capture_status
            capture_playback=$usb_capture_playback
            ;;
        HDMI)
            capture_pid=$HDMI_capture_pid
            capture_status=$HDMI_capture_status
            capture_playback=$HDMI_capture_playback
            ;;
        android)
            capture_pid=$android_capture_pid
            capture_status=$android_capture_status
            capture_playback=$android_capture_playback
            ;;
        *)
            ret="2"
            exit_info "$LINENO : no such capture device"
            ;;
    esac
}

set_all_capture_max_vol()
{
    if [ -z $capture_dev ];then
        ret="1"
        exit_info "$LINENO : no capture device, using option -C or --capture"
    fi

    local card=""
    local numid=""

    case "$capture_dev" in
        usb)    
            get_audio_card USB-Audio
            card=$?
            ;;
        HDMI)  
            get_audio_card HDMI
            card=$?            
            ;;
        android)  
            exit_info "$LINENO : not support $capture_dev now"
            ;;
        *)      
            ret="2"
            exit_info "$LINENO : no such capture source"
            ;;
    esac

    if [ "$card" == "$NEGATIVE_ONE" ];then
        ret="7"
        exit_info "$LINENO : no $capture_dev audio device"
    fi
   
    local all_id=$(amixer -c $card controls | grep Volume | awk -F ',' '{print substr($1, 7, length($1))}')
    
    # format all_id for following parse
    all_id=$(echo "$all_id" | sed 'a,' | tr -d '\n')

    local max=$(echo $all_id | awk -F ',' '{print NF}')
    local i=0

    while [ "$i" -lt "$max" ];do
        numid=$(echo $all_id | awk -F ',' '{print $'$i' }')
        amixer -c $card cset numid=$numid 100% $redirect
        i=$((++i))
    done
}

check_option_argument()
{
    if [ "`echo $2 | head -c 1`" == "-" ];then
        ret="2"
        exit_info "$LINENO : miss an argument for $1"
    fi
}

unit_test()
{
    echo "start unit test"
}


###########
# main()
###########

# initialize parameters
declare -a execute
declare -i idx=0
ret="0"
dbg=$VS_DEBUG
redirect="> /dev/null"

vol=""
mute=""
softvol_dev=""

pcm_dev=""
pcm_sub_dev=""
capture_src_item=""

capture_dev=""
capture_pid=""
capture_status=""
capture_playback=""

master_card=""

_func_="main()"
SHORT_OPTS="s:hcdv:D:m:S:C:"
LONG_OPTS="source:,help,connect,disconnect,volume:,device:,version,mute:,test:,subdev:,capture:,softvol:,init,debug"
arglist="$@"

# check parameters
if [ "$#" == "0" ];then
    ret="1"
    exit_info "$LINENO : no paramter, using option -h or --help for more information"
fi

if [ -f $asound_conf ];then
    master_card=$(cat $asound_conf | grep "QSI_MASTER_CARD" |awk -F '=' '{print $2}')
    if [ "`cat $asound_conf | grep "QSI_VSM_VERSION" |awk -F '=' '{print $2}'`" != "$VERSION" ];then
        echo "Warning, vsm version is not matched !!" 1>&2
    fi
fi

master_card=${master_card:=3}

test ! -d $vsm_dirct              && mkdir -p $vsm_dirct
test ! -f $usb_capture_status     && echo "0" > $usb_capture_status
test ! -f $usb_capture_pid        && echo "0" > $usb_capture_pid
test ! -f $HDMI_capture_status    && echo "0" > $HDMI_capture_status
test ! -f $HDMI_capture_pid       && echo "0" > $HDMI_capture_pid
test ! -f $android_capture_status && echo "0" > $android_capture_status
test ! -f $android_capture_pid    && echo "0" > $android_capture_pid

# parser parameters
opt=`getopt -l "$LONG_OPTS" -o "$SHORT_OPTS" -- "$@"`
eval set -- "$opt"
while true; do

    case "$1" in
        --init)
            execute[$((++idx))]="e_init_capture"
            ;;
        -h|--help)     
            usage
            ;;
        -s|--source)
            check_option_argument $1 $2
            capture_src_item=$(echo $2 | tr "[A-Z] [a-z]")
            execute[$((++idx))]="e_set_capture_source"
            shift
            ;;
        -C|--capture)
            check_option_argument $1 $2
            capture_dev=$(echo $2 | tr "[A-Z] [a-z]")
            shift
            ;;
        -c|--connect)
            execute[$((++idx))]="e_start_record"
            ;;
        -d|--disconnect)
            execute[$((++idx))]="e_stop_record"
            ;;
        --softvol)
            check_option_argument $1 $2
            softvol_dev=$2
            execute[$((++idx))]="e_set_softvol"
            shift
            ;;
        -v|--volume)
            check_option_argument $1 $2
            vol=$2
            if [ -z $(echo $vol | tr -d "[0-9]") ] ;then
                execute[$((++idx))]="e_set_volume"
            else
                ret="2"
                exit_info "$1 argument isn't numeric"
            fi
            shift
            ;;
        -m|--mute)
            check_option_argument $1 $2
            mute="$2"
            if [ -z $(echo $mute | tr -d "[0-9]") ] ;then
                execute[$((++idx))]="e_set_mute"
            fi
            shift
            ;;
        --version)
            echo "Virtual Sound Manager Version : $VERSION"
            ;;
        -D|--device)
            check_option_argument $1 $2
            if [ -z "$pcm_dev" ];then
                pcm_dev=$2
            else
                ret="3"
                exit_info "$LINENO : double set pcm"
            fi
            shift
            ;;
        -S|--subdev)
            check_option_argument $1 $2
            if [ -z "$pcm_sub_dev" ];then
                pcm_sub_dev=$2
            else
                ret="3"
                exit_info "$LINENO : double set sub pcm"
            fi
            shift
            ;;
        --debug)
            dbg="1"
            ;;	
        --test)
            unit_test
            ;;
        --)     
            break
            ;;
        *)      
            ret="2"
            exit_info "$LINENO : parse options"
            ;;
    esac
    shift
done

log "args -> $arglist"
log "vesrion $VERSION"
log "card $master_card"

if [ "$idx" == "0" ];then
    exit $ret
fi

if [ "$dbg" == "1" ];then
    redirect=" "
fi

# execute functions
for exec_func in ${execute[@]}
do
    case "$exec_func" in
        e_init_capture)
            set_all_capture_max_vol
            if [ "$capture_dev" == "usb" ] && [ ! -z "$usb_auto_set_capture" ]; then
                capture_src_item="$usb_auto_set_capture"
                set_capture_usb_source
            fi
            ;;
        e_start_record)
            set_capture_param
            if [ "`cat $capture_status`" == "0" ];then	
                start_record &
                echo "$!" > $capture_pid
            else
                ret="4"
                exit_info "$capture_dev record is running"
            fi
            ;;
        e_stop_record)
            set_capture_param
            if [ "`cat $capture_status`" == "1" ];then
                stop_record
            else
                ret="5"
                exit_info "$capture_dev is already stopped"
            fi
            ;;
        e_set_volume)
            if [ -z $softvol_dev ];then
                set_audio_volume
            fi
            ;;
        e_set_softvol)
            if [ -z $vol ];then
                ret="1"
                exit_info "$LINENO : no volume, using option -v or --volume"
            fi
            set_softvol
            ;;
        e_set_mute)
            set_audio_mute
            ;;
        e_set_capture_source)
            set_capture_usb_source
            ;;
        *)                 
            ret="1"
            break
            ;;
    esac
done

exit $ret

