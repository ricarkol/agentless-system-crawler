LOGSTASH_ROOT=/root/Downloads/logstash-1.4.2

java -jar ${LOGSTASH_ROOT}/vendor/jar/jruby-complete-1.7.11.jar -I../../collector/log_crawler/src/mtlumberjack-gem/lib/mtlumberjack/. mtlumberjack-tester-forever.rb
