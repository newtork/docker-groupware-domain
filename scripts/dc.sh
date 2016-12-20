#!/bin/bash
#title           : dc.sh
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


#########################################
###                                   ###
###              Defaults             ###
###                                   ###
#########################################

HOSTNAME_SELF="$(</etc/hostname)"
ADAPTERS=$( ip addr | grep -Po '^\d+: \w+' | sed 's/.*: //' | tr '\n' ' ' )
SYNC_PORT_SELF=$( grep -Po '(?<=Port ).*' /etc/ssh/sshd_config )
DIRECTORY="$(dirname "$0")"
DEFAULT_IP=$(ifconfig $INTERFACE | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
DEBUG=1 # for debugging, use 3
CLEAR_OLD_IP="false"
XATTR="yes"


#########################################
###                                   ###
###             Parameters            ###
###                                   ###
#########################################

exiting=false
joining=false
interactive=false
joined=false


#########################################
###                                   ###
###             Arguments             ###
###                                   ###
#########################################

set +a # make sure variables are not automatically exported

while [[ $# -gt 0 ]]
do
	key="$1"
	case $key in

		-d|--dir)
		AD_PATH="$2"
		shift
		;;
		-n|--name)
		AD_NAME="$2"
		shift
		;;
		-f|--fqn)
		AD_FQN="$2"
		shift
		;;
		-p|--password)
		AD_PASSWORD="$2"
		shift
		;;
		
		# custom network settings
		--interface)
		INTERFACE="$2"
		shift
		;;
		--ip)
		IP_SELF="$2"
		shift
		;;
		
		# connection to other domain controller
		--peer-ip)
		IP_PEER="$2"
		shift
		;;
		--peer-name)
		HOSTNAME_PEER="$2"
		shift
		;;
		--peer-port)
		SYNC_PORT_PEER="$2"
		shift
		;;
		--peer-user)
		SYNC_USER_PEER="$2"
		shift
		;;
		--self-user)
		SYNC_USER_SELF="$2"
		shift
		;;
		
		# other arguments
		--no-xattr)
		XATTR="no"
		;;
		
		-h|--help|help)
			if [ -z "$DC_SH_ALIAS" ] ; then
				DC_SH_ALIAS=${0##*/}
			fi
			
			echo "Usage: $DC_SH_ALIAS [OPTION]...

Miscellaneous:
	-i, --interactive  ask for every mandatory argument
	-h, --help, help   display this help text and exit
	-j, --join, join   force domain joining behaviour
	--no-xattr         disable extended attributes
			
Mandatory:
	-d, --dir          Active Directory local path
	-n, --name         Active Directory short name
	-f, --fqn          Active Directory fully qualified name
	-p, --password     Active Directory administrator password

Recommended:
	--interface        Specify ethernet adapter, e.g. eth1
	--ip               Specify listening ip address
	--self-user        Specify self replication user

Joining an existing domain:
	--peer-ip          Peer IP address
	--peer-name        Peer hostname
	--peer-user        Peer replication user
	--peer-port        Peer replication port"
			exit 0
		;;
		
		-j|--join|join)
			joining="true"
		;;
		
		-i|--interactive)
			interactive="true"
		;;
		
		*)
			echo "Unknown Option: $1" >&2
		;;
	esac
	shift
done

# force joining if peer hostname or ip is provided
if [[ ! -z "$IP_PEER" || ! -z "$HOSTNAME_PEER" ]] ; then
	joining="true"
fi



#########################################
###                                   ###
###              Arguments            ###
###                                   ###
#########################################

# interactive arguments
. "$DIRECTORY/utils.arguments.inc.sh"
[ "$interactive" == "true" ] && ASK="--ask" || ASK=""


# conditional argument, peer hostname provided without ip
if [[ -z "$IP_PEER" && ! -z "$HOSTNAME_PEER" && "$interactive" != "true" ]]; then
	IP_PEER=$(host $HOSTNAME_PEER | grep -Po "(?<=has address )[0-9\.]+")
	if [ -z "$IP_PEER" ] ; then
		echo "Info: Resolved ${HOSTNAME_PEER} to ip address ${IP_PEER}"
	else
		argument HOSTNAME_PEER "Primary Domain Controller Name" $ASK
	fi
fi

# conditional argument, peer ip provided without hostname
if [[ ! -z "$IP_PEER" && -z "$HOSTNAME_PEER" && "$interactive" != "true" ]]; then
	tryName=$(host $IP_PEER | sed 's/^.* //')
	if echo "$tryName" | grep "\.$" ; then
		HOSTNAME_PEER=$(echo $tryName | sed 's/\.$//')
		echo "Info: Resolved ${IP_PEER} to ${HOSTNAME_PEER}"
	else
		argument IP_PEER "Primary Domain Controller IP" $ASK
	fi
fi

# conditional argument, not explicitly joining but interactive
if [[ "$joining" != "true" && "$interactive" == "true" ]] ; then
	ask_joining="N"
	argument ask_joining "Joining an existing domain? y/N" $ASK
	[ "$ask_joining" == "y" ] && joining="true"
fi

# conditional argument, if joining a domain, ensure required data
if [ "$joining" == "true" ]; then
	argument IP_PEER "Primary Domain Controller IP" $ASK
	argument HOSTNAME_PEER "Primary Domain Controller Name" $ASK
	argument SYNC_PORT_PEER "Primary Domain Controller Sync Port" --default "$SYNC_PORT_SELF" $ASK
	argument SYNC_USER_PEER "Sync Peer User name" --default $SYNC_USER_SELF --skip $ASK
fi


# list available network adapters; if only two, take non-loopback
ADAPTERS_FIRST=$(echo $ADAPTERS | sed 's/lo *//' | sed 's/ .*//')
NETWORK_TEXT="Network adapter"
if [[ $(echo $ADAPTERS | wc -l) < 3 ]] ; then
	NETWORK_DEFAULT=$ADAPTERS_FIRST
else
	NETWORK_TEXT=$(printf "The following network adapters are avaialble: $ADAPTERS\n$NETWORK_TEXT")
fi

		
# simple arguments
argument AD_ADMIN "Domain-Administrator user" --default "Administrator" --save $ASK
argument AD_PATH "Active Directory working path" --save $ASK
argument AD_NAME "Domain name (short)" --save $ASK
argument AD_FQN "Domain realm (long)" --save $ASK
argument AD_PASSWORD "Domain-Administrator password" --redacted --save $ASK
argument INTERFACE "$NETWORK_TEXT" --default "${NETWORK_DEFAULT}" $ASK
argument IP_SELF "Network IP" --default "${DEFAULT_IP}" --invalidate "127.0.0.1" --invalidate "localhost"  --invalidate "" --skip $ASK

argument SYNC_DIR_SELF "SysVol path" --default "${AD_PATH}/state/sysvol" --save --skip $ASK
argument SYNC_USER_SELF "Sync Local User name" --default "root" $ASK
argument SYNC_SSH_SELF "Sync Local User private key location" --default "$(eval echo ~$SYNC_USER_SELF)/.ssh/" --save $ASK
argument SYNC_EXEC "Sync Local executable" --default "service osync-srv start" --save $ASK




#########################################
###                                   ###
###             Functions             ###
###                                   ###
#########################################

function prepareLocalConfiguration() {

	local tmpHosts=$(mktemp)
	
	# add self with domain to tmp hosts file
	sed "s/^.*\s${HOSTNAME_SELF}$/${IP_SELF}\t${HOSTNAME_SELF}.${AD_FQN}\t${HOSTNAME_SELF}/" /etc/hosts > $tmpHosts
	
	# add peer with domain to tmp hosts file
	if [[ ! -z "$IP_PEER" && ! -z "$HOSTNAME_PEER" ]] ; then
		printf "${IP_PEER}\t${HOSTNAME_PEER}.${AD_FQN}\t${HOSTNAME_PEER}\n" >> $tmpHosts
	fi
	
	# write hosts file
	cat $tmpHosts > /etc/hosts && rm $tmpHosts
	
	
	# backup current resolv.conf, before clearing
	cp /etc/resolv.conf /etc/resolv.conf.bak
	
	# write local nameserver
	echo "nameserver 127.0.0.1" > /etc/resolv.conf
	
	# additional nameserver, if provided
	for var in "$@" ; do
		echo "nameserver ${var}" >> /etc/resolv.conf
	done
	
	# domain and search settings
	echo "domain ${AD_FQN}" >> /etc/resolv.conf
	echo "search ${AD_FQN}" >> /etc/resolv.conf
}


function dnsRemove() {
	# $1 : dns server target
	# $2 : subject host name
	# $3 : subject ip address
	local subject="$2" && [ "$subject" == "." ] && subject="" || subject="$subject."
	samba-tool dns delete $1 $AD_FQN $subject$AD_FQN A $3 -U$AD_ADMIN%$AD_PASSWORD >/dev/null #2>&1
}

function dnsAdd() {
	# $1 : dns server target
	# $2 : subject host name
	# $3 : subject ip address
	local subject="$2" && [ "$subject" == "." ] && subject="" || subject="$subject."
	samba-tool dns add $1 $AD_FQN $subject$AD_FQN A $3 -U$AD_ADMIN%$AD_PASSWORD >/dev/null #2>&1
}


function configureSamba() {
	# fix bind9, add configuration for samba
	if ! grep "private/named.conf" /etc/bind/named.conf > /dev/null; then
		printf "Include \"${AD_PATH}/private/named.conf\";\n" >> /etc/bind/named.conf
	fi
	if ! grep "tkey-gssapi-keytab" /etc/bind/named.conf.options > /dev/null; then
		DIRECTORY_ESCAPED=$( echo $AD_PATH | sed 's/\//\\\//g')
		sed -i "s/^};$/tkey-gssapi-keytab \"${DIRECTORY_ESCAPED}\/private\/dns.keytab\";\n};/" /etc/bind/named.conf.options
	fi
	
	# remove old/default samba config files
	unlink /var/lib/samba/private 2>/dev/null || rm -rf /var/lib/samba/private
	unlink /etc/samba/smb.conf 2>/dev/null || rm -f /etc/samba/smb.conf

	# fix samba private dir and smb config file
	ln -s $AD_PATH/private /var/lib/samba/private
	ln -s $AD_PATH/etc/smb.conf /etc/samba/smb.conf
	
	# replace kerberos configuration, no link needed
	cp $AD_PATH/private/krb5.conf /etc/krb5.conf

	# check Bind9/Named configuration
	if [[ $(named-checkconf) ]]; then
		echo "Error: Bind9/Named was NOT configured correctly." >&2
	fi
}


function checkRequirements() {
	return 0
}

####### TODO
####### TODO what when default.. install??
####### TODO
function checkPreviousSamba() {
	if [[ -e "$AD_PATH" && "$(ls -A $AD_PATH)" && -e "${AD_PATH}/etc/smb.conf" && -e "${AD_PATH}/etc/smb.conf" ]]; then
		echo "Info: Using previous samba configuration."
		return 0
	elif [[ -e "/etc/samba/smb.conf" && "$(ls -A /var/lib/samba/private)" ]]; then
		echo "Info: Using incompatible configuration."
		return 0
	else
		return 1
	fi
}


function clearSamba() {
	if [[ -e "$AD_PATH" && "$(ls -A $AD_PATH)" ]]; then
		echo "Warning: Path for active directory is not empty." >&2
		echo "All files inside \"$AD_PATH\" will be deleted. Continue anyway? [y]"
		read continue
		if [ ! "$continue" = "y" ] ; then
			return 1;
		fi
	fi
	
	# clear old ip mapping
	if [[ "$CLEAR_OLD_IP" == "true" ]] ; then
		echo "Clearing old IP mapping from DNS."
		ifconfig | awk '/inet addr/{print substr($2,6)}' | while read line; do
			dnsRemove 127.0.0.1 $HOSTNAME_SELF $line
		done
	fi
	
	# clear samba path
	mkdir -p $AD_PATH && rm -rf $AD_PATH/*
	
	# clear default configuration
	rm -f /etc/samba/smb.conf
	return 0
}

function joinSamba() {
	if ! clearSamba ; then
		echo "Domain preparation aborted."
		return 1
	fi
	
	echo "Info: Joining existing domain."
	mkdir -p $AD_PATH/cache/
	mkdir -p $AD_PATH/private/tls/
	if ! samba-tool domain join $AD_FQN DC \
		-U"$AD_NAME/$AD_ADMIN" \
		--dns-backend=BIND9_DLZ \
		--option="interfaces=lo ${INTERFACE}" \
		--option="bind interfaces only=yes" \
		--targetdir=$AD_PATH \
		--password=$AD_PASSWORD
	then
		echo "Error: Failed to join the domain." >&2
		return 1
	fi
	return 0
}


function createSamba() {
	if ! clearSamba ; then
		echo "Domain preparation aborted."
		return 1
	fi
	
	echo "Info: Creating new domain."
	if ! samba-tool domain provision \
		--use-rfc2307 \
		--realm=$AD_FQN \
		--dns-backend=BIND9_DLZ \
		--domain=$AD_NAME \
		--server-role=dc \
		--adminpass=$AD_PASSWORD \
		--option="interfaces=lo ${INTERFACE}" \
		--option="bind interfaces only=yes" \
		--use-xattrs=$XATTR \
		--targetdir=$AD_PATH
	then
		echo "Error: Failed to create the domain." >&2
		return 1
	fi
	return 0
}


#########################################
###                                   ###
###               Logic               ###
###                                   ###
#########################################



# check for local replication key
. "$DIRECTORY/dc.repl.check.sh"

if ! checkRequirements ; then
	exit 1
fi

if [ -z "$HOSTNAME_PEER" ] || [ -z "$IP_PEER" ]; then
	checkPreviousSamba || createSamba || exit 1
	prepareLocalConfiguration
else
	prepareLocalConfiguration $IP_PEER
	if ! checkPreviousSamba ; then
		dnsAdd $HOSTNAME_PEER $HOSTNAME_SELF $IP_SELF
		joinSamba || exit 1
	fi
	joined=true
fi


# fix local file linking
configureSamba

# start programs
echo "Info: Starting replication..."
service ssh start
$SYNC_EXEC

echo "Info: Starting Samba (Active Directory)..."
service samba start || samba

echo "Info: Starting Bind9/Named (DNS-Server)..."
service bind9 start && named

# wait a second, in case something takes longer than expected
sleep 1

if [ "$joined" == "true" ] ; then
	# join replication
	. "$DIRECTORY/dc.repl.join.sh"
	# fix missing local service principle names
	. "$DIRECTORY/dc.peer.spn.sh" $HOSTNAME_SELF $IP_SELF >/dev/null
fi

# initiate UI
. "$DIRECTORY/dc.ui.sh"

# done
echo "Exiting..."
unset AD_PASSWORD
exit 0
