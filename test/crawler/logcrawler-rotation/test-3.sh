# test logging with a hard link
#TEST_DIR=/var/log/crawler_container_logs
TEST_DIR=/tmp

echo "Cleaning up"
# cleanup
rm ${TEST_DIR}/test.log
rm ${TEST_DIR}/test.log.1
rm /var/log/crawler_container_logs/test.log
echo hola >> `tempfile`

sleep 10

echo "Creating links"
touch /tmp/test.log
ln -f ${TEST_DIR}/test.log /var/log/crawler_container_logs/test.log

inode_link=`ls -i /var/log/crawler_container_logs/test.log | head -n 1 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
inode_log=`ls -i /tmp/test.log | head -n 1 | awk '{print $1}'`
grep $inode_log /root/.sincedb* 

sleep 1

echo "Logging 1, 2"
echo 1 >> ${TEST_DIR}/test.log
sleep 1
echo 2 >> ${TEST_DIR}/test.log
sleep 3

inode_link=`ls -i /var/log/crawler_container_logs/test.log | head -n 1 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
inode_log=`ls -i /tmp/test.log | head -n 1 | awk '{print $1}'`
grep $inode_log /root/.sincedb* 

echo "Rotating log"
mv ${TEST_DIR}/test.log /tmp/test.log.1
#sleep 1

inode_link=`ls -i /var/log/crawler_container_logs/test.log | head -n 1 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
inode_log=`ls -i /tmp/test.log | head -n 1 | awk '{print $1}'`
grep $inode_log /root/.sincedb* 

echo "Logging 3,4,5"
echo 3 >> ${TEST_DIR}/test.log
#sleep 1
echo 4 >> ${TEST_DIR}/test.log 
#sleep 1
echo 5 >> ${TEST_DIR}/test.log 

inode_link=`ls -i /var/log/crawler_container_logs/test.log | head -n 1 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
inode_log=`ls -i /tmp/test.log | head -n 1 | awk '{print $1}'`
grep $inode_log /root/.sincedb* 

sleep 10

echo "Linking again"
ln -f ${TEST_DIR}/test.log /var/log/crawler_container_logs/test.log

inode_link=`ls -i /var/log/crawler_container_logs/test.log | head -n 1 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
inode_log=`ls -i /tmp/test.log | head -n 1 | awk '{print $1}'`
grep $inode_log /root/.sincedb* 

sleep 3
echo "Logging 6"
echo 6 >> ${TEST_DIR}/test.log 
sleep 3
inode_link=`ls -i /var/log/crawler_container_logs/test.log | head -n 1 | awk '{print $1}'`
grep $inode_link /root/.sincedb* 
inode_log=`ls -i /tmp/test.log | head -n 1 | awk '{print $1}'`
grep $inode_log /root/.sincedb* 

