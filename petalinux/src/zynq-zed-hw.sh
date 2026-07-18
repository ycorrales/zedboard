#!/bin/sh
### BEGIN INIT INFO
# Provides:          zynq_hardware_daemon
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Integrated Zynq Telemetry Hardware Endpoint Daemon
### END INIT INFO

DAEMON=/usr/bin/zynq-zed-hardware
NAME=zynq-zed-hardware-daemon

case "$1" in
start)
  echo "Starting background platform optimization service ($NAME): "
  start-stop-daemon -S -x $DAEMON
  echo "done."
  ;;
stop)
  echo "Halting background platform optimization service ($NAME): "
  start-stop-daemon -K -x $DAEMON
  echo "done."
  ;;
restart)
  $0 stop
  $0 start
  ;;
*)
  echo "Usage: /etc/init.d/zynq-daemon.sh {start|stop|restart}"
  exit 1
  ;;
esac

exit 0
