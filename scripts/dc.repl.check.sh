mkdir -p $SYNC_SSH_SELF

if [ ! -e $SYNC_SSH_SELF/id_rsa ] ; then
	if ssh-keygen -t rsa -N "" -f $SYNC_SSH_SELF/id_rsa > /dev/null ; then
		cat $SYNC_SSH_SELF/id_rsa.pub >> $SYNC_SSH_SELF/authorized_keys
		service ssh restart
	else
		echo "Error: Failed to generate SSH key." #>&2
	fi
fi

