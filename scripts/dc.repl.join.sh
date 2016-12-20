#!/bin/bash

mkdir -p $SYNC_SSH_SELF

if  ssh-keyscan -p $SYNC_PORT_PEER -H $IP_PEER >> $SYNC_SSH_SELF/known_hosts 2>/dev/null \
 && ssh-keyscan -p $SYNC_PORT_PEER -H $HOSTNAME_PEER >> $SYNC_SSH_SELF/known_hosts 2>/dev/null
then
	
	# get private peer key from user input
	until ssh $SYNC_USER_PEER@$IP_PEER -p $SYNC_PORT_PEER \
		"echo \"${SYNC_USER_SELF}@${IP_SELF}:${SYNC_PORT_SELF}\" >> ${SYNC_HOME_PEER}/peers" #2>/dev/null
	do
		echo "Please enter the SSH private key for replication:"
		read line
		echo "" > $SYNC_SSH_SELF/id_rsa
		until [ "$line" == "" ] ; do
			echo $line >> $SYNC_SSH_SELF/id_rsa
			read line
		done
		
		echo $(ssh-keygen -y -f $SYNC_SSH_SELF/id_rsa) $SYNC_USER_SELF@$HOSTNAME_SELF > $SYNC_SSH_SELF/id_rsa.pub
	done < /dev/stdin

	echo "Info: Accepted replication key. Trust established."
	cat $SYNC_SSH_SELF/id_rsa.pub >> $SYNC_SSH_SELF/authorized_keys
	service ssh restart
	
	
	# add self to peer hosts file and nameserver
	ssh $SYNC_USER_PEER@$IP_PEER -p $SYNC_PORT_PEER "\
		printf \"${IP_SELF}\t${HOSTNAME_SELF}.${AD_FQN}\t${HOSTNAME_SELF}\n\" >> /etc/hosts && \
		printf \"nameserver ${IP_SELF}\\n%s\\n\" \"\$(</etc/resolv.conf)\" > /etc/resolv.conf" \
	|| echo "Error: Could not add to remote nameserver list." >&2
	
	# add self to peer spn / dns list
	ssh $SYNC_USER_PEER@$IP_PEER -p $SYNC_PORT_PEER "\
		${LOCAL_DIR_PEER}/dc.peer.spn.sh ${HOSTNAME_SELF} ${IP_SELF}" >/dev/null \
	|| echo "Error: Could not add to remote SPN / DNS list." >&2
	
	# start syncing on peer
	ssh $SYNC_USER_PEER@$IP_PEER -p $SYNC_PORT_PEER "\
		${LOCAL_DIR_PEER}/dc.peer.repl.sh ${HOSTNAME_SELF} ${SYNC_PORT_SELF} ${SYNC_USER_SELF} ${SYNC_DIR_SELF}" \
	|| echo "Error: Could not add to remote known-hosts." >&2
	
else
	echo "Error: Could not establish the ssh connection to $IP_PEER on port $SYNC_PORT_PEER." >&2
fi