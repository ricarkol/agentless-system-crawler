# test logging without links
TEST_DIR=/var/log/crawler_container_logs
echo 1 >> ${TEST_DIR}/test.log
sleep 1
echo 2 >> ${TEST_DIR}/test.log
sleep 1
mv ${TEST_DIR}/test.log /tmp/test.log.1
sleep 1
echo 3 >> ${TEST_DIR}/test.log
sleep 1
echo 4 >> ${TEST_DIR}/test.log 
