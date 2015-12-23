import augeas
import sys
import json

class nginx_conf:

  # nginx SSL module
  # http://nginx.org/en/docs/http/ngx_http_ssl_module.html

  def __init__(self):
    self.aug = augeas.Augeas(root="/")
    self.ciphers = [ "EECDH+AESGCM" , "EDH+AESGCM", "AES256+EECDH", "AES256+EDH"]
    self.ssl_protocols_recommended  = [ "TLSv1.1", "TLSv1.2"] #use
    self.ssl_protocols_deprecated = [ "SSLv2", "SSLv3" ] #definitely not use
    self.ssl_protocols_notrecommended = [ "TLSv1" ] #grudgingly use

    # cipher details
    # https://www.openssl.org/docs/manmaster/apps/ciphers.html
    # AESGCM: AES in Galois Counter Mode (GCM): these ciphersuites are only supported in TLS v1.2.

    # ECDHE, EECDH: cipher suites using authenticated ephemeral ECDH key agreement.

    # AES128, AES256, AES: cipher suites using 128 bit AES, 256 bit AES or either 128 or 256 bit AES.

  def isNginx(self):
    aug = self.aug
    isnginx = aug.match("/files/etc/nginx/nginx.conf")
    if isnginx == None:
      return False
    return True
 

  def isTLSUsed(self):
    aug = self.aug
    ssl = aug.get("/files/etc/nginx/nginx.conf/http/server/listen")
    if ssl == None:
      return [0, "SSL is not used for this nginx server"]

    if ssl.lower().find("ssl") >= 0:
      return [1, "SSL is used for this nginx server"]
    else:
      return [0, "SSL is not used for this nginx srver"]

  def server_ssl_certificate(self):
    aug = self.aug
    cert = aug.get("/files/etc/nginx/nginx.conf/http/server/ssl_certificate")
    if cert == None:
      return [0 , "TLS certificate configuration not defined."]
    else:
      return [1 , "TLS certificate configuration is definedi."]


  def server_ssl_certificate_key(self):
    aug = self.aug
    cert_key = aug.get("/files/etc/nginx/nginx.conf/http/server/ssl_certificate_key")
    if cert_key == None:
      return [0, "TLS certificate key is not defined"]
    else:
      return [1, "TLS certificate key is defined"]


  def server_listen(self):
    aug = self.aug
    listen = aug.get("/files/etc/nginx/nginx.conf/http/server/listen")
    if listen == None:
      return [0, "TLS listen port is not defined"]
    else:
      if listen.find("443") >= 0:
        return [1, "TLS listen port is defined and is 443"]
      else:
        return [1, "TLS port is defined but it is not 443"]


  def server_ssl_protocols(self):
    aug = self.aug
    ssl_protocols = aug.get("/files/etc/nginx/nginx.conf/http/server/ssl_protocols")
    if ssl_protocols == None:
      return [0, "SSL protocols are not defined"]

    arr = ssl_protocols.split(" ")


    # check if deprecated protocols are used, e.g., SSLv2, SSLv3
    deprecated = ""
    for item in arr:
      if item in self.ssl_protocols_deprecated:
        deprecated = deprecated + " " + item

    if deprecated != "":
      return [0, "the protocols " + deprecated + " have been deprecated. Consider using TLSv1.1 or TLSv1.2"]
  
  
    # check if not recommended protocols are used, e.g., TLSv1
    notrecommended = ""
    for item in arr:
      if item in self.ssl_protocols_notrecommended: 
        notrecommended = notrecommended + " " + item

    if notrecommended != "":
      return [0, "the use of protocols" + notrecommended + " is not recommended. Consider using TLSv1.1 or TLSv1.2"]

    # check if only recommended protocols are used
    recommended = ""
    flag=0
    for item in arr:
      if item not in self.ssl_protocols_recommended:
        flag = 1
        recommended = recommended + " " + item

    if flag == 1:
      return [0, "the use of protocols " + recommended + " is not recommended. Consider using TLSv1.1 or TLSv1.2"]
    
    return [1, "Recommended ssl_protocols are configured"] 


def main():
  ng = nginx_conf()
  output = dict()

  if True == ng.isNginx():
    output["app"] = "nginx"



  #Check if TLS is being used
  arr = ng.isTLSUsed()
  if arr[0] <= 0:
    output["tls_used"]=False
    print json.dumps(output)
    #print arr[1]
    sys.exit(0)

  #Check if TLS certs are used
  arr = ng.server_ssl_certificate()
  if arr[0] <=0:
    output["tls_certs"]=arr[1]
    #print "SSL is used. However, " + arr[1]
    print json.dumps(output)
    sys.exit(0)

  #Check if TLS certificate key is defined
  arr = ng.server_ssl_certificate_key()
  if arr[0] <= 0:
    output["tls_cert_key"]=arr[1]
    print json.dumps(output)
    #print "SSL is used. However, " + arr[1]
    sys.exit(0)

  arr = ng.server_ssl_protocols()
  if arr[0] <= 0:
    output["tls_protocols"] = arr[1]
    print json.dumps(output)
    #print "SSL is used. However, " + arr[1]
    sys.exit(0)

  #TLS cert is defined. Check for other TLS configurations
  #if arr[0] > 0:
  #  print ng.server_listen()


if __name__ == "__main__":
    main()


