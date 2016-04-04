# test logging with a symlink
#TEST_DIR=/var/log/crawler_container_logs

# cleanup
rm -f /tmp/test.log
rm -f /tmp/tmplink
rm -f /tmp/tmplink2
rm -f /var/log/crawler_container_logs/test.log
tmp=`tempfile`
echo hola1 > `tempfile`
ln -s $tmp /tmp/tmplink
tmp=`tempfile`
echo hola1 > `tempfile`
ln -s $tmp /tmp/tmplink2
sync

sleep 1

echo "Creating links"
ln -s /tmp/test.log /var/log/crawler_container_logs/test.log
touch /tmp/test.log

inode_link=`ls -i /var/log/crawler_container_logs/test.log | tail -n 10 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
ls -i /tmp/test.log

echo "Logging 1, 2, 3"
echo 1 >> /tmp/test.log
sleep 1
echo 2 >> /tmp/test.log
sleep 1
echo 3 >> /tmp/test.log
sleep 3

inode_link=`ls -i /var/log/crawler_container_logs/test.log | tail -n 10 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 

echo "Rotating log"
mv /tmp/test.log /tmp/test.log.1
touch /tmp/test.log
#sleep 1

inode_link=`ls -i /var/log/crawler_container_logs/test.log | tail -n 10 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
ls -i /tmp/test.log

echo "Logging 4,5,6"
echo 4 >> /tmp/test.log
#sleep 1
echo 5 >> /tmp/test.log 
#sleep 1
echo 6 >> /tmp/test.log 
echo 7 >> /tmp/test.log 
echo 8 >> /tmp/test.log 

inode_link=`ls -i /var/log/crawler_container_logs/test.log | tail -n 10 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 

sleep 5

echo "Linking again"
rm -f /var/log/crawler_container_logs/test.log
ln -s /tmp/test.log /var/log/crawler_container_logs/test.log2
mv /var/log/crawler_container_logs/test.log2 /var/log/crawler_container_logs/test.log
inode_link=`ls -i /var/log/crawler_container_logs/test.log | tail -n 10 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
