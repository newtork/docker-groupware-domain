#!/bin/bash

DIRECTORY="$(dirname "$0")"


if [[ "$1" == "help" || "$1" == "usage" || "$#" != "4" ]] ; then
	echo "dc.peer.repl.sh [HOST] [PORT] [USER] [DIR]"
	exit 1
fi

PEER_HOSTNAME="$1" && shift
PEER_PORT="$1" && shift
PEER_USER="$1" && shift
PEER_DIR="$1" && shift


# interactive arguments
. "$DIRECTORY/utils.arguments.inc.sh"

# self parameters
argument SYNC_USER_SELF "Replication user name" --default "root" --silent
argument USER_HOME_SELF "Replication user home" --default "$( eval echo ~$SYNC_USER_SELF )" --silent
argument SYNC_DIR_SELF "Replication local directory" --silent

# peer inputs
argument PEER_HOSTNAME "Peer hostname" --invalidate "localhost" --silent
argument PEER_PORT "Peer port" --silent
argument PEER_USER "Peer user" --silent
argument PEER_DIR "Peer directory" --silent


# fingerprint
fingerprint=$(ssh-keyscan -p $PEER_PORT -H $PEER_HOSTNAME 2>/dev/null)
echo "$fingerprint" >> ${USER_HOME_SELF}/.ssh/known_hosts

# Replication
sed \
	-e "s|TARGET_SYNC_DIR=.*|TARGET_SYNC_DIR=\"ssh://${PEER_USER}@${PEER_HOSTNAME}:${PEER_PORT}/${PEER_DIR}\"|" \
	-e "s|INITIATOR_SYNC_DIR=.*|INITIATOR_SYNC_DIR=\"${SYNC_DIR_SELF}\"|" \
	-e "s|SSH_RSA_PRIVATE_KEY=.*|SSH_RSA_PRIVATE_KEY=\"${USER_HOME_SELF}/.ssh/id_rsa\"|" \
	/etc/osync/sync.conf.tmp > /etc/osync/sync.${PEER_HOSTNAME}.conf

# Start replication
$SYNC_EXEC
