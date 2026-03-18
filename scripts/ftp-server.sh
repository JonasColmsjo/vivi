#!/usr/bin/env bash
# ftp-server.sh — Start/stop anonymous FTP server on host for VM file transfers
# Usage: ftp-server.sh <host> <host_root> <ftpdir> <ftp_bind> <ftp_python> start|stop
set -euo pipefail

HOST="${1:?usage: ftp-server.sh <host> <host_root> <ftpdir> <ftp_bind> <ftp_python> start|stop}"
HOST_ROOT="${2:?}"
FTPDIR="${3:?}"
FTP_BIND="${4:?}"
FTP_PYTHON="${5:?}"
ACTION="${6:-start}"

case "$ACTION" in
    start)
        if ssh "$HOST" "ss -tlnp | grep -q ':21 '" 2>/dev/null; then
            echo "FTP server already running on port 21"
            exit 0
        fi
        echo "Starting FTP server on $HOST (${FTP_BIND}:21)..."
        ssh "$HOST" "mkdir -p '$FTPDIR'"
        ssh "$HOST_ROOT" "nohup $FTP_PYTHON << 'PYEOF' > /tmp/ftpd-root.log 2>&1 &
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer
from pyftpdlib.authorizers import DummyAuthorizer
a = DummyAuthorizer()
a.add_anonymous('$FTPDIR', perm='elradfmw')
h = FTPHandler
h.authorizer = a
h.passive_ports = range(60000, 60100)
s = FTPServer(('$FTP_BIND', 21), h)
s.serve_forever()
PYEOF"
        sleep 1
        if ssh "$HOST" "ss -tlnp | grep -q ':21 '" 2>/dev/null; then
            echo "FTP server started. Upload dir: $FTPDIR"
        else
            echo "ERROR: FTP server failed to start. Check /tmp/ftpd-root.log on $HOST"
            exit 1
        fi
        ;;
    stop)
        echo "Stopping FTP server..."
        ssh "$HOST_ROOT" "pkill -f 'pyftpdlib' 2>/dev/null" || true
        echo "Stopped."
        ;;
    *)
        echo "Usage: ftp-server.sh <host> <host_root> <ftpdir> <ftp_bind> <ftp_python> start|stop"
        exit 1
        ;;
esac
