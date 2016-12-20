#!/bin/bash

DIRECTORY="$(dirname "$0")"


if [[ "$1" == "help" || "$1" == "usage" || "$#" != "2" ]] ; then
	echo "dc.peer.spn.sh [HOST] [IP]"
	exit 1
fi

PEER_HOSTNAME="$1"
shift
PEER_IP="$1"
shift

# interactive arguments
. "$DIRECTORY/utils.arguments.inc.sh"


# self parameters
argument AD_PATH "Active Directory working path" --silent
argument AD_NAME "Domain name (short)" --silent
argument AD_FQN "Domain realm (long)" --silent
argument AD_ADMIN "Domain-Administrator user" --silent
argument AD_PASSWORD "Domain-Administrator password" --redacted --silent

# peer inputs
argument PEER_HOSTNAME "Peer hostname" --invalidate "localhost" --silent
argument PEER_IP "Peer IP" --invalidate "127.0.0.1" --invalidate "localhost" --silent


# LDAP service additions (SPN)
GUID_SELF=$(ldbsearch -H $AD_PATH/private/sam.ldb "(invocationId=*)" --cross-ncs objectguid | grep -Pzo "(?<=\n)\N+,CN=${PEER_HOSTNAME^^}\N+\nobjectGUID: \N+" | tail -n 1 | sed "s/.* //")
HOST_FQN=$(echo "${PEER_HOSTNAME,,}.${AD_FQN,,}")
for spn in \
	HOST/${HOST_FQN}/${AD_NAME^^} \
	HOST/${HOST_FQN}/${AD_FQN,,} \
	ldap/${HOST_FQN} \
	ldap/${HOST_FQN}/${AD_NAME^^} \
	ldap/${HOST_FQN}/${AD_FQN,,} \
	ldap/${PEER_HOSTNAME^^} \
	ldap/${HOST_FQN}/DomainDnsZones.${AD_FQN,,} \
	ldap/${HOST_FQN}/ForestDnsZones.${AD_FQN,,} \
	ldap/${GUID_SELF}._msdcs.${AD_FQN,,}
do
	samba-tool spn add ${spn} ${PEER_HOSTNAME^^}$ -U${AD_ADMIN}%${AD_PASSWORD} 2>/dev/null \
	 || echo "Skipped ${spn} on ${PEER_HOSTNAME^^}"
done

# DNS additions
samba-tool dns add 127.0.0.1 ${AD_FQN,,} . A ${PEER_IP} -U${AD_ADMIN}%${AD_PASSWORD} >/dev/null 2>&1 \
 || echo "Skipped [A] ${AD_FQN,,} <- ${PEER_IP}"
 
samba-tool dns add 127.0.0.1 ${AD_FQN,,} . NS ${HOST_FQN} -U${AD_ADMIN}%${AD_PASSWORD} 2>/dev/null \
 || echo "Skipped [NS] ${AD_FQN,,} <- ${HOST_FQN}"
 
samba-tool dns add 127.0.0.1 _msdcs.${AD_FQN,,} ${GUID_SELF} CNAME $HOST_FQN -U${AD_ADMIN}%${AD_PASSWORD} 2>/dev/null \
 || echo "Skipped [CNAME] _msdcs.${AD_FQN,,} <- ${GUID_SELF}"
