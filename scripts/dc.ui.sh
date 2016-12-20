#!/bin/bash

function startRepl() {
	local servers=$(echo "${HOSTNAME_SELF} ${HOSTNAME_PEER}")
	local dcs=$(echo "dc=${AD_FQN}" | sed "s/\./,dc=/g")
	for target in $servers ; do
		source=$(echo $servers | sed "s/ *${target} *//")
		
		# replication root
		samba-tool drs replicate $target $source $dcs -d $DEBUG -U$AD_ADMIN%$AD_PASSWORD

		for subject in \
			DC=ForestDnsZones \
			CN=Configuration \
			DC=DomainDnsZones \
			CN=Schema,CN=Configuration
		do
			samba-tool drs replicate $target $source $subject,$dcs -d $DEBUG -U$AD_ADMIN%$AD_PASSWORD
		done
	done
}

# get services status, 0=running, 1=terminated
function running() {
	for service in samba smbd winbindd named sshd; do
		if ! pgrep "${service}" > /dev/null; then
			echo "Warning: ${service} is not running." >&2
			return 1
		fi
	done
	return 0
}



savelyexit() {
	if [ "$exiting" == "true" ] ; then
		exit 0
	fi
	exiting=true
	
	for service in ssh bind9 samba; do
		service $service stop
	done 
	
	for service in samba smbd winbindd named; do
		if pgrep "$service" > /dev/null; then
			pkill "$service"
			echo "Exited $service."
		fi
	done 
	
	unlink /var/lib/samba/private/ > /dev/null 2>&1
	unlink /etc/samba/smb.conf > /dev/null 2>&1
	
	# sleep for short period of time to let trap quit smoothly
	sleep 1
	exit 0
}

# trap function to execute commands after CTRL-C
#  additional signals could be INT SIGHUP
trap savelyexit SIGINT SIGTERM EXIT


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
	key     Returns the SSH key for sysvol replication.
	samba   Display local samba network shares.
	proc    Display running processes of the domain controller.
	ports   Display port usage of the domain controller.
	build   Display samba build options.
	status  Display replication status.
	repl    Start replication.
	exit    Shutdown the domain controller.\n";
				
		elif [ "$line" == "host" ]; then
			printf "\nLooking for LDAP in domain...\n"
			host -t SRV _ldap._tcp.$AD_FQN.
			printf "\nLooking for Kerberos in domain...\n"
			host -t SRV _kerberos._udp.$AD_FQN.
			printf "\nLooking for this computer in domain...\n"
			host -t A $HOSTNAME_SELF.$AD_FQN.;
			
		elif [ "$line" == "data" ]; then
			printf "\nChecking samba database...\n"
			samba-tool dbcheck;
			
		elif [ "$line" == "key" ]; then
			cat $SYNC_SSH_SELF/id_rsa;
			
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
			
		elif [ "$line" == "status" ]; then
			printf "\nChecking DRS Replication...\n"
			samba-tool drs showrepl;
			
		elif [ "$line" == "repl" ]; then
			printf "\nStarting DRS Replication...\n"
			startRepl;
			
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