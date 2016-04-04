import socket
import ssl
import time
import struct

env = "prod"

if env == "stage":
    metric = "25aa4c07-4a76-43ba-af53-81af7d1733a9.0000.12345 100 %d\r\n" % (int(time.time())) # stage
    host = "metrics.stage1.opvis.bluemix.net" # stage
    passwd = "5KilGEQ9qExi" # stage
else: #if env == "prod"
    metric = "d5c00fbb-90b6-4ace-b69a-0e4e7bd28083.0000.12345 100 %d\r\n" % (int(time.time())) # prod
    host = "metrics.opvis.bluemix.net" # prod
    passwd = "oLYMLA7ogscT" # prod
port = "9095"
tenant = "Crawler"

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
conn = ssl.wrap_socket(s, cert_reqs=ssl.CERT_NONE)
conn.connect((host, int(port)))

identifier = str(conn.getsockname()[0])
id_msg = "1I" + chr(len(identifier)) + identifier
sent = conn.write(id_msg)

auth_msg = "2S" + chr(len(tenant)) + tenant + chr(len(passwd)) + passwd
sent = conn.write(auth_msg)

chunk = conn.read(6)  # Expecting "1A"
code = bytearray(chunk)[:2]
print("MTGraphite authentication server response of %s" % code)
if code == "0A":
    raise "Invalid tenant auth, please check the tenant id or password!"

msgs = bytearray("1W")
msgs.extend(bytearray(struct.pack('!I', len([metric]))))
msgs.extend("1M")
msgs.extend(bytearray(struct.pack('!I', 1))) # sequence = 1
msgs.extend(bytearray(struct.pack('!I', len(metric))))
msgs.extend(metric)
len_sent = 0
while len_sent < len(msgs):
    written = conn.write(buffer(msgs, len_sent))
    if written == 0:
        raise RuntimeError("socket connection broken")
    len_sent += written
chunk = conn.read(6)  # Expecting "1A"+4byte_num_of_metrics_received
conn.close()
code = bytearray(chunk)[:2]
print("MTGraphite server response of %s" % code)
r = not (code == "1A") # 1A is success
exit(r)
