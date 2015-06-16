#!/usr/bin/env python2

import sys
import os
import os.path as p
import logging
import  argparse
from logging.handlers import TimedRotatingFileHandler, SocketHandler
import serial

_logdir = p.realpath(p.join(p.dirname(__file__), 'logs'))

parser = argparse.ArgumentParser(
    formatter_class=argparse.ArgumentDefaultsHelpFormatter)
parser.add_argument('--port', default=os.environ.get('SERIAL_PORT', '/dev/tty.nodemcu'),
                    help="Which serial port to use")
parser.add_argument('--baud', default=os.environ.get('SERIAL_BAUD', 230400),
                    help="BAUD rate for the serial port")
parser.add_argument('--log-dir', nargs="?", default=_logdir,
                    help="Where to store log files")
parser.add_argument('--log-addr', nargs="?",
                    help="Where to netcat log data, host:port")
parser.add_argument('-q', '--quiet', default=False,
                    help="Disable log on stdout")


def applog(quiet=False):
    log = logging.getLogger('app')
    log.setLevel(logging.DEBUG)
    hndlr = logging.StreamHandler(sys.stdout)
    hndlr.setLevel(logging.INFO if quiet else logging.DEBUG)
    hndlr.setFormatter(logging.Formatter(
        u"%(asctime)s > %(message)s"))
    log.addHandler(hndlr)
    return log


def shelog(log_dir=None, log_addr=(None, None)):
    log = logging.getLogger('she')
    log.setLevel(logging.DEBUG)
    fmtr = logging.Formatter(u"%(asctime)s she %(message)s")

    if log_dir:
        hndlr = TimedRotatingFileHandler(os.path.join(log_dir, 'device.log'),
            when="midnight", interval=1, backupCount=14, encoding="utf8")
        hndlr.setLevel(logging.DEBUG)
        hndlr.setFormatter(fmtr)
        log.addHandler(hndlr)

    if log_addr[0]:
        hndlr = SocketHandler(*log_addr)
        hndlr.setLevel(logging.DEBUG)
        hndlr.setFormatter(fmtr)
        log.addHandler(hndlr)

    return log


def main():
    args = parser.parse_args()
    print("Starting with: %s" % (args,))

    log = applog(args.quiet)

    if args.log_dir:
        if not os.access(args.log_dir, os.W_OK):
            log.error("No write access to %s", args.log_dir)
            sys.exit(1)
        log.info("Log files will be stored in %s", args.log_dir)

    (host, port) = (None, None)
    if args.log_addr:
        try:
            host, port = args.log_addr.split(':')
            port = int(port)
            log.info("Log records will be sent via TCP to %s:%d", host, port)
        except (TypeError, ValueError) as e:
            log.error("Invalid --log-addr='%s': %s", args.log_addr, e)
            sys.exit(3)

    she = shelog(args.log_dir, (host, port))
    try:
        port = serial.Serial(args.port, baudrate=args.baud, timeout=0.2)
    except Exception as e:
        log.error("Unable to open serial port %s: %s", args.port, e)
        sys.exit(2)

    try:
        while True:
            line = port.readline()
            if not len(line):
                continue
            log.info("%s", line.rstrip("\r\n"))
            if line.endswith('\n'):
                she.info("said %s", line.rstrip("\r\n"))
            else:
                she.info("zzzz %s", line.rstrip("\r\n"))

            [h.flush() for h in she.handlers]

    except KeyboardInterrupt:
        port.close()
        sys.exit(0)
    except:
        log.exception("Unhandled mainloop error!!!")
        port.close()
        sys.exit(15)


if __name__ == '__main__':
    main()
