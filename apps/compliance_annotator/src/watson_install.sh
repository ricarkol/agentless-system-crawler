export SERVICE_PKG_NAME=scanner-commandline-tool
chown -R cloudadmin /home/cloudadmin/$SERVICE_PKG_NAME
chmod -R 755 /home/cloudadmin/$SERVICE_PKG_NAME
cd /home/cloudadmin/$SERVICE_PKG_NAME

mkdir -p /opt/$SERVICE_PKG_NAME
cp * /opt/$SERVICE_PKG_NAME
cp vulnerability_annotator.conf /etc/init
initctl start vulnerability_annotator
