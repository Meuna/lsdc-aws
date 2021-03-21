import sys
import os
import time
from scapy.sendrecv import sniff

SERVICE = sys.argv[1]
PORT = sys.argv[2]
TIMEOUT = int(sys.argv[3])

pkt_filter = "port {}".format(PORT)

last_received = time.time()

while True:
    pkts = sniff(count=1, filter=pkt_filter, timeout=10)
    now = time.time()
    if len(pkts) > 0:
        last_received = now
        time.sleep(10)
    elif (now - last_received) > TIMEOUT:
        os.system('supervisorctl stop ' + SERVICE)
        os.system('shutdown -h now')
