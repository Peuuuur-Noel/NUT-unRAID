#!/bin/sh
# Slackware startup script for Network UPS Tools
# Copyright 2010 V'yacheslav Stetskevych
# Edited for unRAID by macester macecapri@gmail.com
# Revised by Derek Macias 2017.05.01
#

PROG="nut"
PLGPATH="/boot/config/plugins/$PROG"
CONFIG=$PLGPATH/$PROG.cfg
DPATH=/usr/bin
export PATH=$DPATH:$PATH

# read our configuration
[ -e "$CONFIG" ] && source $CONFIG

start_driver() {
    /usr/sbin/upsdrvctl -u root start 2>&1 || exit 1
}

start_upsd() {
    if pgrep upsd 2>&1 >/dev/null; then
        echo "$PROG upsd is running..."
    else
        /usr/sbin/upsd -u root || exit 1
    fi
}

start_upsmon() {
    if pgrep upsmon 2>&1 >/dev/null; then
        echo "$PROG upsmon is running..."
    else
        /usr/sbin/upsmon -u root || exit 1
    fi
}

stop() {
    echo "Stopping the UPS services... "
    if pgrep upsd 2>&1 >/dev/null; then
        /usr/sbin/upsd -c stop 2>&1 >/dev/null
    fi
    if pgrep upsmon 2>&1 >/dev/null; then
        /usr/sbin/upsmon -c stop 2>&1 >/dev/null
    fi
    /usr/sbin/upsdrvctl stop 2>&1 >/dev/null
    sleep 2
    if [ -f /var/run/nut/upsmon.pid ]; then
        rm /var/run/nut/upsmon.pid
    fi
}

write_config() {
    echo "Writing $PROG config"
    # Killpower flag permissions
    #[ -e /etc/nut/flag ] && chmod 777 /etc/nut/flag

    # Add nut user and group for udev at shutdown
    GROUP=$( grep -ic "218" /etc/group )
    USER=$( grep -ic "218" /etc/passwd )

    if [ $GROUP -ge 1 ]; then
        echo "$PROG group already configured"
    else
        groupadd -g 218 nut
    fi

    if [ $USER -ge 1 ]; then
        echo "$PROG user already configured"
    else
        useradd -u 218 -g nut -s /bin/false nut
    fi

    if [ $MANUAL == "disable" ]; then

        # add the name
        sed -i "1 s~.*~[${NAME}]~" /etc/nut/ups.conf

        # Add the driver config
        if [ $DRIVER == "custom" ]; then
                sed -i "2 s/.*/driver = ${SERIAL}/" /etc/nut/ups.conf
        else
                sed -i "2 s/.*/driver = ${DRIVER}/" /etc/nut/ups.conf
        fi

        # add the port
        sed -i "3 s~.*~port = ${PORT}~" /etc/nut/ups.conf

        # add mode standalone/netserver
        sed -i "1 s/.*/MODE=${MODE}/" /etc/nut/nut.conf

        # Add SNMP-specific config
        if [ $DRIVER == "snmp-ups" ]; then
            var10="pollfreq = ${POLL}"
            var11="community = ${COMMUNITY}"
            var12='snmp_version = v2c'
        else
            var10=''
            var11=''
            var12=''
        fi

        sed -i "4 s/.*/$var10/" /etc/nut/ups.conf
        sed -i "5 s/.*/$var11/" /etc/nut/ups.conf
        sed -i "6 s/.*/$var12/" /etc/nut/ups.conf

        # Set monitor ip address, user, password and mode
        if [ $MODE == "slave" ]; then
            MONITOR="slave"
        else
            MONITOR="master"
        fi

        var1="MONITOR ${NAME}@${IPADDR} 1 ${USERNAME} ${PASSWORD} ${MONITOR}"
        sed -i "1 s,.*,$var1," /etc/nut/upsmon.conf

        # Set which shutdown script NUT should use
        sed -i "2 s,.*,SHUTDOWNCMD \"/sbin/poweroff\"," /etc/nut/upsmon.conf

        # Set which notification script NUT should use
        sed -i "6 s,.*,NOTIFYCMD \"/usr/sbin/nut-notify\"," /etc/nut/upsmon.conf

        # Set if the ups should be turned off
        if [ $UPSKILL == "enable" ]; then
            var8='POWERDOWNFLAG /etc/nut/flag/killpower'
            sed -i "3 s,.*,$var8," /etc/nut/upsmon.conf
        else
            var9='POWERDOWNFLAG /etc/nut/flag/no_killpower'
            sed -i "3 s,.*,$var9," /etc/nut/upsmon.conf
        fi

        # Set upsd users
        var13="[admin]"
        var14="password=adminpass"
        var15="actions=set"
        var16="actions=fsd"
        var17="instcmds=all"
        var18="[${USERNAME}]"
        var19="password=${PASSWORD}"
        var20="upsmon master"
        var21="[slaveuser]"
        var22="password=slavepass"
        var23="upsmon slave"
        sed -i "1 s,.*,$var13," /etc/nut/upsd.users
        sed -i "2 s,.*,$var14," /etc/nut/upsd.users
        sed -i "3 s,.*,$var15," /etc/nut/upsd.users
        sed -i "4 s,.*,$var16," /etc/nut/upsd.users
        sed -i "5 s,.*,$var17," /etc/nut/upsd.users
        sed -i "6 s,.*,$var18," /etc/nut/upsd.users
        sed -i "7 s,.*,$var19," /etc/nut/upsd.users
        sed -i "8 s,.*,$var20," /etc/nut/upsd.users
        sed -i "9 s,.*,$var21," /etc/nut/upsd.users
        sed -i "10 s,.*,$var22," /etc/nut/upsd.users
        sed -i "11 s,.*,$var23," /etc/nut/upsd.users
    fi

    # Link shutdown scripts for poweroff in rc.0 and rc.6
    if [ $( grep -ic "/etc/rc.d/rc.nut restart_udev" /etc/rc.d/rc.6 ) -ge 1 ]; then
        echo "UDEV lines already exist in rc.0,6"
    else
        sed -i '/\/bin\/mount -v -n -o remount,ro \//a [ -x /etc/rc.d/rc.nut ] && /etc/rc.d/rc.nut restart_udev' /etc/rc.d/rc.6
    fi

    if [ $( grep -ic "/etc/rc.d/rc.nut shutdown" /etc/rc.d/rc.6 ) -ge 1 ]; then
        echo "UPS shutdown lines already exist in rc.0,6"
    else
         sed -i -e '/# Now halt /a [ -x /etc/rc.d/rc.nut ] && /etc/rc.d/rc.nut shutdown' -e //N /etc/rc.d/rc.6
    fi
}

case "$1" in
    shutdown) # shuts down the UPS driver
        if [ -f /etc/nut/flag/killpower ]; then
            echo "Shutting down UPS driver..."
            /usr/sbin/upsdrvctl shutdown
        fi
        ;;
    start)  # starts everything (for a ups server box)
        sleep 1
        write_config
        sleep 1
        if [ "$SERVICE" == "enable" ]; then
            if [ "$MODE" != "slave" ]; then
                start_driver
                sleep 1
                start_upsd
            fi
            start_upsmon
        else
            echo "$PROG service is not enabled..."
        fi
        ;;
    start_upsmon) # starts upsmon only (for a ups client box)
        start_upsmon
        ;;
    stop) # stops all UPS-related daemons
        sleep 1
        write_config
        sleep 1
        stop
        ;;
    reload)
        sleep 1
        write_config
        sleep 1
        if [ "$SERVICE" == "enable" ]; then
            if [ "$MODE" != "slave" ]; then
                start_driver
                sleep 1
                /usr/sbin/upsd -c reload
            fi
            /usr/sbin/upsmon -c reload
        fi
        ;;
    restart_udev)
        if [ -f /etc/nut/flag/killpower ]; then
            echo "Restarting udev to be able to shut the UPS inverter off..."
            /etc/rc.d/rc.udev start
            sleep 10
        fi
        ;;
    write_config)
        write_config
        ;;
    *)
    echo "Usage: $0 {start|start_upsmon|stop|shutdown|reload|restart|write_config}"
esac