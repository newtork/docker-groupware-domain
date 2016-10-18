#!/bin/bash
#title           : domain-controller.sh
#description     : This script acts as a STDIN/STDOUT wrapper and provides additional arguments to the server startup routine.
#author          : newtork / Alexander Dümont
#date            : 2016-10-17
#version         : 0.1a
#usage           : bash domain-controller.sh help
#notes           : recommended to be run inside docker image "newtork/groupware-domain"
#bash_version    : 4.3.42(3)-release
#==============================================================================

#
# Notice:
# -------
#
# All arguments are expected to be correctly set.
#
#

# Arguments:
# ----------
#
# -d	DOMAIN_PATH
# -s	DOMAIN_NAME
# -n	DOMAIN_FQN
# -p	DOMAIN_ADMINPASSWORD
# -e	LISTEN_INTERFACE
# -l	LISTEN_IP
#


while getopts ":d:s:n:p:e:l:" opt; do
  case $opt in
    d) par_path="$OPTARG"
	   echo " DIR: $OPTARG"
    ;;
    s) par_name="$OPTARG"
	   echo " NAM: $OPTARG"
    ;;
    n) par_fqn="$OPTARG"
	   echo " FQN: $OPTARG"
    ;;
    p) par_passwd="$OPTARG"
	   echo " PWD: $OPTARG"
    ;;
    e) par_interface="$OPTARG"
	   echo " INT: $OPTARG"
    ;;
    l) par_ip="$OPTARG"
	   echo " IP:  $OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    ;;
  esac
done

if [ "$1" == "help" ]; then
	echo "Usage: 
		-d DOMAIN_PATH
		-s DOMAIN_NAME
		-n DOMAIN_FQN
		-p DOMAIN_ADMINPASSWORD
		-e LISTEN_INTERFACE
		-l LISTEN_IP"
		
	exit 0
fi

if [ "$par_ip" == "127.0.0.1" ]; then
	par_ip="$(ifconfig $par_interface | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')"
	echo "Info: Determined IP $par_ip"
fi


# trap function to execute commands after CTRL-C
savelyexit() {
	echo ""
	for service in samba smbd winbindd named; do
		if pgrep "$service" > /dev/null; then
			pkill "$service"
			echo "Exited $service."
		fi
	done 
	
	unlink /var/lib/samba/private/ > /dev/null 2&>1
	unlink /etc/samba/smb.conf > /dev/null 2&>1
	
	# sleep for short period of time to let trap quit smoothly
	sleep 1
	exit 0
}
trap savelyexit SIGINT SIGTERM EXIT
# additional signals could be INT SIGHUP

# check for already existing active directory
if [[ -e "/etc/samba/smb.conf" && -e "$par_path" && "$(ls -A $par_path)" ]]; then
	echo "Info: Using previous samba configuration."
else 
	if [[ -e "$par_path" && "$(ls -A $par_path)" ]]; then
		echo "Warning: Path for active directory was not empty."
	fi

	# clear samba path
	mkdir -p $par_path && rm -rf $par_path/*
	
	# clear default configuration
	rm -f /etc/samba/smb.conf
	
	# provision new domain
	samba-tool domain provision	\
		--use-rfc2307 \
		--realm=$par_fqn \
		--dns-backend=BIND9_DLZ \
		--domain=$par_name \
		--server-role=dc \
		--adminpass=$par_passwd \
		--option="interfaces=lo $par_interface" \
		--option="bind interfaces only=yes" \
		--use-xattrs=yes \
		--targetdir=$par_path
fi

# fix bind9, add configuration for samba
if ! grep "private/named.conf" /etc/bind/named.conf > /dev/null; then
	printf "Include \"$par_path/private/named.conf\";\n" >> /etc/bind/named.conf
fi
if ! grep "tkey-gssapi-keytab" /etc/bind/named.conf.options > /dev/null; then
	DIRECTORY_ESCAPED=$(sed 's/\//\\\//g' <<< $par_path)
	sed -i "s/^};$/tkey-gssapi-keytab \"$DIRECTORY_ESCAPED\/private\/dns.keytab\";\n};/" /etc/bind/named.conf.options
fi

# replace kerberos configuration, no link needed
cp $par_path/private/krb5.conf /etc/krb5.conf

# remove old/default samba config files
unlink /var/lib/samba/private/ > /dev/null 2&>1 || rm -rf /var/lib/samba/private/
unlink /etc/samba/smb.conf > /dev/null 2&>1 || rm -f /etc/samba/smb.conf

# fix samba private dir and smb config file
ln -s $par_path/private/ /var/lib/samba/private
ln -s $par_path/etc/smb.conf /etc/samba/smb.conf

# fix environment on runtime
HOSTNAME="$(</etc/hostname)"

# -> update hosts-file
tmpHosts=$(mktemp) && \
sed "s/^.*\s$HOSTNAME/$par_ip $HOSTNAME.$par_fqn $HOSTNAME/" /etc/hosts > $tmpHosts
cat $tmpHosts > /etc/hosts
rm $tmpHosts

# -> update kerberos settings (not needed)
# sed -i "s/127.0.0.1/$HOSTNAME.$par_fqn/g" /etc/krb5.conf

# -> replace resolv-file
cp /etc/resolv.conf /etc/resolv.conf.bak && \
printf "nameserver 127.0.0.1\ndomain $par_fqn\nsearch $par_fqn\n" > /etc/resolv.conf

# check Bind9/Named configuration
if [[ $(named-checkconf) ]]; then
	echo "Error: Bind9/Named was NOT configured correctly.";
fi

# start programs
echo "Info: Starting Samba (Active Directory)..."
service samba start

echo "Info: Starting Bind9/Named (DNS-Server)..."
service bind9 start && named

# fix active directory self ip 
sleep 1

# -> clear old ip mapping
echo "Clearing old IP mapping from DNS."
ifconfig | awk '/inet addr/{print substr($2,6)}' | while read line; do
	samba-tool dns delete 127.0.0.1 $par_fqn $HOSTNAME A $line -UAdministrator --password=$par_passwd > /dev/null 2&>1
done

# -> add current ip mapping
echo "Adding current IP mapping to DNS."
samba-tool dns add 127.0.0.1 $par_fqn . A $par_ip -UAdministrator --password=$par_passwd > /dev/null 2&>1
samba-tool dns add 127.0.0.1 $par_fqn $HOSTNAME A $par_ip -UAdministrator --password=$par_passwd > /dev/null 2&>1



# get services status, 0=running, 1=terminated
running() {
	for service in samba smbd winbindd named; do
		if ! pgrep "$service" > /dev/null; then
			echo "Warning: $service is not running."
			return 1
		fi
	done
	return 0
}

# check whether server has started and is still running
sleep 1
if running; then
	echo "Started."
	echo "Type \"help\" to list commands."

	# read from stdin and redirect to fifo pipe while server is running
	printf "\n> "
	while read line && running; do
		if [ "$line" == "help" ]; then
			printf "\nYou can use the following commands to monitor the active directory: 
	host    Check dns lookup for the active directory.
	data    Check the samba active directory database.
	samba   Display local samba network shares.
	proc    Display running processes of the domain controller.
	ports   Display port usage of the domain controller.
	build   Display samba build options.
	repl    Display replication status.
	exit    Shutdown the domain controller.\n";
				
		elif [ "$line" == "host" ]; then
			printf "\nLooking for LDAP in domain...\n"
			host -t SRV _ldap._tcp.$par_fqn.
			printf "\nLooking for Kerberos in domain...\n"
			host -t SRV _kerberos._udp.$par_fqn.
			printf "\nLooking for this computer in domain...\n"
			host -t A $HOSTNAME.$par_fqn.;
			
		elif [ "$line" == "data" ]; then
			printf "\nChecking samba database...\n"
			samba-tool dbcheck;
			
		elif [ "$line" == "samba" ]; then
			printf "\nLooking for samba root shares in domain...\n"
			smbclient -L localhost -U%;
			
		elif [ "$line" == "proc" ]; then
			printf "\nListing running samba processes...\n"
			ps axf | egrep "samba|smbd|winbindd|named";
			
		elif [ "$line" == "ports" ]; then
			printf "\nListing samba port usages...\n"
			netstat -tulpn | egrep "samba|smbd|named";
			
		elif [ "$line" == "build" ]; then
			printf "\nListing samba build options...\n" 
			smbd -b;
			
		elif [ "$line" == "repl" ]; then
			printf "\nChecking DNS Replication...\n"
			samba-tool drs showrepl;
			
		elif [ "$line" == "exit" ]; then
			break;
			
		elif [ "$line" == "" ]; then
			printf "> "
			continue;
		
		else
			printf "\nUnknown command: $line\nType \"help\" to list commands.\n"
		fi
	
	printf "\n> "
	done < /dev/stdin

fi

echo "Exiting..."
exit 0