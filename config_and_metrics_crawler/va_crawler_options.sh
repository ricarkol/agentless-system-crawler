# these options are uesed in the --options parameter of crawler.py by
# regcrawler and by livecrawler

REGCRAWLER_FEATURES="os,disk,file,package,config,dockerhistory,dockerinspect"
LIVECRAWLER_FEATURES="package,config,file,os"

REGCRAWLER_OPTION_CONNECTION="{}"

REGCRAWLER_OPTION_FILE="{
    \"exclude_dirs\": [
        \"boot\",
        \"dev\",
        \"proc\",
        \"sys\",
        \"mnt\",
        \"tmp\",
        \"var/cache\",
        \"usr/share/man\",
        \"usr/share/doc\",
        \"usr/share/mime\"
    ],
    \"root_dir\": \"/\"
}"
LIVECRAWLER_OPTION_FILE=$REGCRAWLER_OPTION_FILE

REGCRAWLER_OPTION_PACKAGE="{}"
LIVECRAWLER_OPTION_PACKAGE=$REGCRAWLER_OPTION_PACKAGE

REGCRAWLER_OPTION_PROCESS="{}"

REGCRAWLER_OPTION_CONFIG="{
    \"exclude_dirs\": [
        \"dev\",
        \"proc\",
        \"mnt\",
        \"tmp\",
        \"var/cache\",
        \"usr/share/man\",
        \"usr/share/doc\",
        \"usr/share/mime\"
    ],
    \"known_config_files\": [
        \"etc/login.defs\",
        \"etc/passwd\",
        \"etc/hosts\",
        \"etc/mtab\",
        \"etc/group\",
        \"vagrant/vagrantfile\",
        \"vagrant/Vagrantfile\",
        \"etc/motd\",
        \"etc/login.defs\",
        \"etc/shadow\",
        \"etc/login.defs\",
        \"etc/shadow\",
        \"etc/pam.d/system-auth\",
        \"etc/pam.d/common-password\",
        \"etc/pam.d/password-auth\",
        \"etc/pam.d/system-auth\",
        \"etc/pam.d/other\",
        \"etc/pam.d/common-auth\",
        \"etc/pam.d/common-account\",
        \"etc/pam.d/password-auth\",
        \"etc/pam.d/system-auth\",
        \"etc/pam.d/common-password\",
        \"etc/pam.d/password-auth\",
        \"etc/pam.d/system-auth\",
        \"etc/pam.d/common-auth\",
        \"etc/pam.d/common-account\",
        \"etc/cron.daily/logrotate\",
        \"etc/logrotate.conf\",
        \"etc/logrotate.d/*\",
        \"etc/sysctl.conf\",
        \"etc/rsyslog.conf\",
        \"etc/ssh/sshd_config\",
        \"etc/hosts.allow\",
        \"etc/hosts.deny\",
        \"etc/hosts.equiv\",
        \"etc/pam.d/rlogin\",
        \"etc/pam.d/rsh\",
        \"etc/pam.d/rexec\",
        \"etc/snmpd.conf\",
        \"etc/snmp/snmpd.conf\",
        \"etc/snmp/snmpd.local.conf\",
        \"usr/local/etc/snmp/snmpd.conf\",
        \"usr/local/etc/snmp/snmpd.local.conf\",
        \"usr/local/share/snmp/snmpd.conf\",
        \"usr/local/share/snmp/snmpd.local.conf\",
        \"usr/local/lib/snmp/snmpd.conf\",
        \"usr/local/lib/snmp/snmpd.local.conf\",
        \"usr/share/snmp/snmpd.conf\",
        \"usr/share/snmp/snmpd.local.conf\",
        \"usr/lib/snmp/snmpd.conf\",
        \"usr/lib/snmp/snmpd.local.conf\",
        \"etc/hosts\",
        \"etc/hostname\",
        \"etc/mtab\",
        \"usr/lib64/snmp/snmpd.conf\",
        \"usr/lib64/snmp/snmpd.local.conf\",
        \"etc/services\",
        \"etc/init/ssh.conf\"
    ],
    \"discover_config_files\": false,
    \"root_dir\": \"/\"
}"
LIVECRAWLER_OPTION_CONFIG=$REGCRAWLER_OPTION_CONFIG

REGCRAWLER_OPTION_METRIC="{}"

REGCRAWLER_OPTION_DISK="{}"

REGCRAWLER_OPTION_OS="{}"
LIVECRAWLER_OPTION_OS=$REGCRAWLER_OPTION_OS
